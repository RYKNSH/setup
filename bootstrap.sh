#!/bin/bash
# =============================================================================
# RYKNSH Brain Bootstrap
# ryknsh-brain リポジトリをクローン（または更新）して install.sh を実行する
#
# Usage (curl ワンライナー):
#   curl -fsSL https://raw.githubusercontent.com/RYKNSH/setup/main/bootstrap.sh | bash
#
# オプション (環境変数で上書き可):
#   BRAIN_REPO         — brain repo の URL（省略時は自動検出）
#   BRAIN_INSTALL_DIR  — クローン先ディレクトリ（省略時: ~/.claude）
#   BRAIN_FLAGS        — install.sh に渡すフラグ（例: --dev / --copy）
#
# 自動検出の優先順位:
#   1. BRAIN_REPO 環境変数
#   2. brain.conf（ローカル: スクリプト同階層 / カレントディレクトリ / RYKNSH_DIR）
#   3. brain.conf（リモート: public setup リポジトリから curl で取得）
#   4. 既存インストールの ${BRAIN_INSTALL_DIR}/telemetry.conf
#   5. gh CLI で RYKNSH/ryknsh-brain を探索
# =============================================================================

set -euo pipefail

# ── デフォルト値（brain.conf / 環境変数で上書き可） ────────────────────────
# bootstrap.sh は public リポジトリにあるため、Brain repo URL をここに持つことは問題ない
BRAIN_REPO="${BRAIN_REPO:-https://github.com/RYKNSH/ryknsh-brain.git}"
BRAIN_INSTALL_DIR="${BRAIN_INSTALL_DIR:-${HOME}/.claude}"

# このスクリプト自身が置かれている public setup リポジトリの raw URL
SETUP_RAW_URL="https://raw.githubusercontent.com/RYKNSH/setup/main"

# ── ログ関数 ────────────────────────────────────────────────────────────────
log_info()  { echo "  ℹ️  $1"; }
log_ok()    { echo "  ✅ $1"; }
log_warn()  { echo "  ⚠️  $1"; }
log_error() { echo "  ❌ $1" >&2; }

# ── brain.conf を探してsource ─────────────────────────────────────────────
# 優先順位:
#   1. スクリプトと同階層（git clone して直接実行した場合）
#   2. カレントディレクトリ（curl | bash 経由で RYKNSH dir から実行した場合）
#   3. 環境変数 RYKNSH_DIR が設定されている場合
#   4. public setup リポジトリから curl で取得（新規マシンの curl | bash）
load_brain_conf() {
  local candidates=(
    "$(cd "$(dirname "${BASH_SOURCE[0]:-$(pwd)}")" 2>/dev/null && pwd)/brain.conf"
    "${PWD}/brain.conf"
    "${RYKNSH_DIR:+${RYKNSH_DIR}/brain.conf}"
  )
  for conf in "${candidates[@]}"; do
    if [[ -f "$conf" ]]; then
      # shellcheck source=/dev/null
      source "$conf"
      return 0
    fi
  done

  # ローカルに見つからない場合は public setup リポジトリから取得
  local _tmp_conf
  _tmp_conf=$(mktemp)
  if curl -fsSL "${SETUP_RAW_URL}/brain.conf" -o "$_tmp_conf" 2>/dev/null; then
    # shellcheck source=/dev/null
    source "$_tmp_conf"
    rm -f "$_tmp_conf"
    return 0
  fi
  rm -f "$_tmp_conf"
  return 1
}

# conf をロード（失敗しても続行 — 環境変数や他の検出手段で補完）
# stderr は捨てるが、ファイルが存在したのに失敗した場合はユーザーに知らせる
_brain_conf_err=$(mktemp)
trap 'rm -f "$_brain_conf_err"' EXIT
if ! load_brain_conf 2>"$_brain_conf_err"; then
  if [[ -s "$_brain_conf_err" ]]; then
    log_warn "brain.conf の読み込みに失敗しました: $(< "$_brain_conf_err")"
  fi
fi
rm -f "$_brain_conf_err"

# ── ターゲットディレクトリ確定 ──────────────────────────────────────────────
CLAUDE_DIR="${BRAIN_INSTALL_DIR:-${HOME}/.claude}"

# ── Brain Repo URL 解決 ───────────────────────────────────────────────────
resolve_brain_repo() {
  # 1. 環境変数（brain.conf で設定された値 or シェルから渡された値）
  if [[ -n "${BRAIN_REPO:-}" ]]; then
    echo "$BRAIN_REPO"
    return 0
  fi

  # 2. 既存インストールの telemetry.conf（リモートURLを保持している）
  if [[ -f "${CLAUDE_DIR}/telemetry.conf" ]]; then
    local url
    url=$(head -1 "${CLAUDE_DIR}/telemetry.conf" | tr -d '[:space:]')
    if [[ -n "$url" ]]; then
      echo "$url"
      return 0
    fi
  fi

  # 3. gh CLI — 認証済みユーザーの org から ryknsh-brain を探す
  if command -v gh &>/dev/null; then
    local url
    # まず RYKNSH org を直接探索
    url=$(gh repo view RYKNSH/ryknsh-brain --json url -q '.url' 2>/dev/null || echo "")
    if [[ -n "$url" ]]; then
      # gh は https URL を返す（.git なし）— 末尾に .git を付与
      echo "${url%.git}.git"
      return 0
    fi
    # 認証済みユーザーの ryknsh-brain も探す（fork運用時）
    local gh_user
    gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "")
    if [[ -n "$gh_user" ]]; then
      url=$(gh repo view "${gh_user}/ryknsh-brain" --json url -q '.url' 2>/dev/null || echo "")
      if [[ -n "$url" ]]; then
        echo "${url%.git}.git"
        return 0
      fi
    fi
  fi

  echo ""
  return 1
}

# ── メイン処理 ───────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   RYKNSH Brain Bootstrap             ║"
echo "╚══════════════════════════════════════╝"
echo ""

BRAIN_REPO_URL=$(resolve_brain_repo || true)

# URL 簡易バリデーション（git が受け付ける形式か確認）
if [[ -n "$BRAIN_REPO_URL" ]] && ! [[ "$BRAIN_REPO_URL" =~ ^(https?://|git@|ssh://) ]]; then
  log_warn "BRAIN_REPO_URL の形式が不正です: ${BRAIN_REPO_URL}"
  log_warn "https:// または git@ で始まる URL を指定してください。"
  BRAIN_REPO_URL=""
fi

if [[ -z "$BRAIN_REPO_URL" ]]; then
  log_error "Brain repo URL を特定できませんでした。"
  echo ""
  echo "  以下のいずれかで再実行してください:"
  echo ""
  echo "  # 方法 1: 環境変数で指定"
  echo "  BRAIN_REPO=https://github.com/RYKNSH/ryknsh-brain.git bash bootstrap.sh"
  echo ""
  echo "  # 方法 2: gh CLI でログイン後に再実行"
  echo "  gh auth login && bash bootstrap.sh"
  echo ""
  exit 1
fi

log_info "Brain repo : ${BRAIN_REPO_URL}"
log_info "Target dir : ${CLAUDE_DIR}"
echo ""

# git の対話的プロンプトを無効化（認証待ちでハングするのを防ぐ）
export GIT_TERMINAL_PROMPT=0

# ── Clone or Pull ────────────────────────────────────────────────────────

if [[ -d "${CLAUDE_DIR}/.git" ]]; then
  # 既存リポジトリ — remote が一致するか確認してから pull
  existing_remote=$(git -C "$CLAUDE_DIR" remote get-url origin 2>/dev/null || echo "")
  if [[ "$existing_remote" != "$BRAIN_REPO_URL" ]]; then
    log_warn "既存の ${CLAUDE_DIR} のリモート (${existing_remote}) が指定の URL と異なります。"
    log_warn "スキップします。手動で確認してください。"
    exit 1
  fi
  echo "  🔄 既存リポジトリを更新中..."
  if ! git -C "$CLAUDE_DIR" pull --ff-only 2>&1; then
    log_warn "git pull --ff-only に失敗しました。uncommitted な変更がある可能性があります。"
    log_warn "次のコマンドで状態を確認してください:"
    echo "    git -C \"${CLAUDE_DIR}\" status"
    echo "    git -C \"${CLAUDE_DIR}\" stash && bash bootstrap.sh"
    exit 1
  fi
  log_ok "更新完了"

elif [[ -d "${CLAUDE_DIR}" ]] && [[ -n "$(ls -A "${CLAUDE_DIR}" 2>/dev/null)" ]]; then
  # ディレクトリは存在するが git repo ではない（手動セットアップ済み等）
  log_warn "${CLAUDE_DIR} は既に存在しますが git リポジトリではありません。"
  log_warn "バックアップして空にしてから再実行するか、次のコマンドで初期化してください:"
  echo ""
  echo "  mv \"${CLAUDE_DIR}\" \"${CLAUDE_DIR}.bak\" && bash bootstrap.sh"
  echo ""
  exit 1

else
  # 新規クローン（bootstrap 用途なので shallow clone で十分）
  echo "  📦 クローン中 (${BRAIN_REPO_URL})..."
  git clone --depth 1 "$BRAIN_REPO_URL" "$CLAUDE_DIR"
  log_ok "クローン完了"
fi

# ── install.sh に委譲 ────────────────────────────────────────────────────

INSTALL_SCRIPT="${CLAUDE_DIR}/install.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
  log_error "install.sh が見つかりません: ${INSTALL_SCRIPT}"
  log_error "Brain repo の構造が想定と異なる可能性があります。"
  exit 1
fi

echo ""
echo "  🚀 install.sh を実行中..."
echo ""

# shellcheck disable=SC2086
bash "$INSTALL_SCRIPT" ${BRAIN_FLAGS:-}
