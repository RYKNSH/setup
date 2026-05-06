#!/bin/bash
# =============================================================================
# RYKNSH Brain — All-in-One Setup
#
# 「ターミナルを開いた」状態から Brain 動作可能な状態まで 1 コマンドで到達する。
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/RYKNSH/setup/main/setup-all.sh | bash
#
# このスクリプトは以下を順に実行する (各ステップ idempotent):
#   1. Xcode Command Line Tools 確認 (= git があるか)
#   2. Homebrew インストール (未インストールなら)
#   3. GitHub CLI (gh) インストール (未インストールなら)
#   4. gh auth login (未ログインなら → 対話的)
#   5. Brain bootstrap.sh 実行 (= clone + install + 全自動配備)
#
# 中断・失敗時は同じコマンドで再実行可能 (= 進捗を維持して続きから)
# =============================================================================

set -euo pipefail

# ── カラー出力 ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_R='\033[0;31m'; C_G='\033[0;32m'; C_Y='\033[1;33m'; C_B='\033[0;34m'; C_0='\033[0m'
else
  C_R=''; C_G=''; C_Y=''; C_B=''; C_0=''
fi

log_info()  { echo -e "  ℹ️  $1"; }
log_ok()    { echo -e "  ${C_G}✅${C_0} $1"; }
log_warn()  { echo -e "  ${C_Y}⚠️${C_0}  $1"; }
log_error() { echo -e "  ${C_R}❌${C_0} $1" >&2; }
log_step()  { echo -e "\n${C_B}▶${C_0} ${C_B}$1${C_0}"; }
log_skip()  { echo -e "  ⏭️  $1"; }

SETUP_RAW_URL="https://raw.githubusercontent.com/RYKNSH/setup/main"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   🚀 RYKNSH Brain — All-in-One Setup                         ║"
echo "║                                                              ║"
echo "║   このスクリプトは以下を全自動で行います:                     ║"
echo "║   1) Xcode CLT  2) Homebrew  3) gh CLI                       ║"
echo "║   4) gh auth login  5) Brain インストール                    ║"
echo "║                                                              ║"
echo "║   所要時間: 5〜10分 (ネットワーク速度による)                  ║"
echo "║   中断時は同じコマンドで再実行可能                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Xcode Command Line Tools
# ─────────────────────────────────────────────────────────────────────────────
log_step "Step 1/5: Xcode Command Line Tools"

if xcode-select -p >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  log_skip "Xcode CLT は既にインストール済"
else
  log_info "Xcode CLT をインストールします (ダイアログが出ます — 「インストール」をクリック)"
  xcode-select --install 2>&1 || true
  echo ""
  log_warn "Xcode CLT のインストールが完了するまでお待ちください"
  log_warn "完了後、もう一度同じコマンドで再実行してください:"
  echo ""
  echo "  curl -fsSL ${SETUP_RAW_URL}/setup-all.sh | bash"
  echo ""
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Homebrew
# ─────────────────────────────────────────────────────────────────────────────
log_step "Step 2/5: Homebrew"

if command -v brew >/dev/null 2>&1; then
  log_skip "Homebrew は既にインストール済 ($(brew --version | head -1))"
else
  log_info "Homebrew をインストール中... (Mac のログインパスワードを聞かれる場合があります)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Apple Silicon Mac の PATH 設定
  if [ -d /opt/homebrew/bin ]; then
    if ! grep -q '/opt/homebrew/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
      log_ok "PATH を ~/.zprofile に追加"
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -d /usr/local/bin ]; then
    eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"
  fi
  log_ok "Homebrew インストール完了"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: GitHub CLI
# ─────────────────────────────────────────────────────────────────────────────
log_step "Step 3/5: GitHub CLI (gh)"

if command -v gh >/dev/null 2>&1; then
  log_skip "gh は既にインストール済 ($(gh --version | head -1))"
else
  log_info "gh をインストール中..."
  brew install gh
  log_ok "gh インストール完了"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: gh auth login
# ─────────────────────────────────────────────────────────────────────────────
log_step "Step 4/5: GitHub にログイン"

if gh auth status >/dev/null 2>&1; then
  log_skip "既にログイン済 ($(gh api user --jq '.login' 2>/dev/null || echo unknown))"
else
  log_info "GitHub Web 認証フローを開始します"
  log_info "ブラウザが開いたら 8桁コード を入力 → Authorize をクリック"
  echo ""
  # --web で web flow 強制、--git-protocol で HTTPS 選択、--hostname で github.com 固定
  # この3つで対話プロンプトのほとんどが skip され、最後の「Press Enter to launch」と
  # 8桁コード入力だけが対話的になる
  if ! gh auth login --web --hostname github.com --git-protocol https; then
    log_error "gh auth login に失敗"
    log_error "再実行: curl -fsSL ${SETUP_RAW_URL}/setup-all.sh | bash"
    exit 1
  fi
  log_ok "GitHub ログイン完了"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Brain bootstrap (clone + install)
# ─────────────────────────────────────────────────────────────────────────────
log_step "Step 5/5: Brain インストール (bootstrap.sh)"

curl -fsSL "${SETUP_RAW_URL}/bootstrap.sh" | bash

# ─────────────────────────────────────────────────────────────────────────────
# 完了
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${C_G}╔══════════════════════════════════════════════════════════════╗${C_0}"
echo -e "${C_G}║   ✅ All-in-One Setup 完了                                    ║${C_0}"
echo -e "${C_G}╠══════════════════════════════════════════════════════════════╣${C_0}"
echo -e "${C_G}║                                                              ║${C_0}"
echo -e "${C_G}║   次のステップ:                                              ║${C_0}"
echo -e "${C_G}║                                                              ║${C_0}"
echo -e "${C_G}║   1. Claude アプリを起動                                      ║${C_0}"
echo -e "${C_G}║   2. チャット欄に  /ry-in  と入力                             ║${C_0}"
echo -e "${C_G}║                                                              ║${C_0}"
echo -e "${C_G}║   これで初回セッションが完了し、すべての準備が整います。       ║${C_0}"
echo -e "${C_G}║                                                              ║${C_0}"
echo -e "${C_G}╚══════════════════════════════════════════════════════════════╝${C_0}"
echo ""
