#!/bin/bash
# =============================================================================
# RYKNSH Brain — Emergency Repair
#
# 「auto_update が止まった」「telemetry が来ない」「fix/auto-commit-* で凍結」
# 等の症状から brain を main に戻して最新化する救済スクリプト。
#
# 使い方 (curl ワンライナー):
#   curl -fsSL https://raw.githubusercontent.com/RYKNSH/setup/main/repair.sh | bash
#
# 何をやるか:
#   1. brain repo を fetch
#   2. uncommitted を stash で退避
#   3. main に強制 checkout (--force で)
#   4. origin/main に reset (= local diverged を捨てる)
#   5. install.sh を再実行 (= 最新の hook / settings を反映)
#
# 失われるもの: brain repo 内の手元未 commit 変更 (= stash には残る)
# 失われないもの: ~/.claude/.* の各種設定 / sessions / projects 等
# =============================================================================

set -uo pipefail

if [ -t 1 ]; then
  C_R='\033[0;31m'; C_G='\033[0;32m'; C_Y='\033[1;33m'; C_B='\033[0;34m'; C_0='\033[0m'
else
  C_R=''; C_G=''; C_Y=''; C_B=''; C_0=''
fi

ok()   { echo -e "  ${C_G}✅${C_0} $1"; }
warn() { echo -e "  ${C_Y}⚠️${C_0}  $1"; }
fail() { echo -e "  ${C_R}❌${C_0} $1"; }
info() { echo -e "  ${C_B}ℹ️${C_0}  $1"; }

# bootstrap.sh は ~/.claude をクローン先とするため標準は ~/.claude/.git。
# 旧バージョンや手動セットアップで ~/.claude/brain/.git になっているケースも救済。
if [ -d "${HOME}/.claude/.git" ]; then
  BRAIN_DIR="${HOME}/.claude"
elif [ -d "${HOME}/.claude/brain/.git" ]; then
  BRAIN_DIR="${HOME}/.claude/brain"
else
  BRAIN_DIR="${HOME}/.claude"  # for the error message below
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   🔧 RYKNSH Brain — Emergency Repair                          ║"
echo "║                                                              ║"
echo "║   症状: auto_update が止まった / telemetry が来ない /        ║"
echo "║         fix/auto-commit-* ブランチで凍結している              ║"
echo "║                                                              ║"
echo "║   解決: 強制的に main に戻して最新版を取得し install.sh 再実行 ║"
echo "║   所要時間: 1〜3 分                                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -d "$BRAIN_DIR/.git" ]; then
  fail "$HOME/.claude (または $HOME/.claude/brain) が brain repo として存在しません"
  fail "新規 install を試みてください: curl -fsSL https://raw.githubusercontent.com/RYKNSH/setup/main/setup-all.sh | bash"
  exit 1
fi
info "Brain repo: $BRAIN_DIR"

cd "$BRAIN_DIR"

echo "🔍 Step 1/5: 現状診断"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
HAS_UNCOMMITTED="no"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  HAS_UNCOMMITTED="yes"
fi
HAS_UNTRACKED="no"
if [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
  HAS_UNTRACKED="yes"
fi
LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo unknown)
info "現在ブランチ: $CURRENT_BRANCH"
info "uncommitted変更: $HAS_UNCOMMITTED"
info "untracked file: $HAS_UNTRACKED"
info "ローカル HEAD:  ${LOCAL_HEAD:0:7}"
echo ""

echo "📥 Step 2/5: origin から fetch"
if git fetch origin main 2>&1 | tail -3; then
  ok "fetch 完了"
else
  fail "fetch 失敗 — ネットワークまたは認証を確認してください"
  exit 1
fi
echo ""

echo "📦 Step 3/5: 手元の変更を stash で退避"
STASH_NAME="repair-$(date +%Y%m%d-%H%M%S)"
if [ "$HAS_UNCOMMITTED" = "yes" ] || [ "$HAS_UNTRACKED" = "yes" ]; then
  if git stash push -u -m "$STASH_NAME" 2>&1 | tail -2; then
    ok "stash 作成: $STASH_NAME"
    info "復元する場合: git -C $BRAIN_DIR stash list && git stash pop"
  else
    warn "stash 失敗 — 強制 checkout に進みます (= 手元変更は失われます)"
  fi
else
  ok "退避すべき変更なし"
fi
echo ""

echo "🔀 Step 4/5: main に強制 checkout + origin/main に reset"
if git checkout --force main 2>&1 | tail -2; then
  ok "main にチェックアウト"
else
  fail "main checkout 失敗"
  exit 1
fi

if git reset --hard origin/main 2>&1 | tail -2; then
  ok "origin/main に reset"
else
  fail "reset 失敗"
  exit 1
fi
NEW_HEAD=$(git rev-parse HEAD)
info "新 HEAD: ${NEW_HEAD:0:7}"
echo ""

# fix/auto-commit-* ブランチは捨てる (= ローカルだけのゴミ枝)
echo "🧹 Step 4.5/5: 古い fix/auto-commit-* ブランチを削除"
DELETED=$(git branch | awk '/fix\/auto-commit-/ {print $1}' | head -10)
if [ -n "$DELETED" ]; then
  echo "$DELETED" | while read -r br; do
    [ -n "$br" ] && git branch -D "$br" 2>/dev/null && echo "    削除: $br"
  done
  ok "ローカル fix branch クリーンアップ完了"
else
  ok "削除すべき fix branch なし"
fi
echo ""

echo "🚀 Step 5/5: install.sh 再実行 (= 最新 hook / settings を配備)"
if bash "$BRAIN_DIR/install.sh"; then
  ok "install.sh 完了"
else
  warn "install.sh が一部 warning を出しました — 上のログを確認してください"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ✅ Repair 完了                                              ║"
echo "║                                                              ║"
echo "║   次回 claude を起動すると:                                   ║"
echo "║   - auto_update が正常に走る                                  ║"
echo "║   - session 終了時に telemetry issue が送信される             ║"
echo "║   - 失敗があれば diagnostic queue に集約される                ║"
echo "║                                                              ║"
echo "║   stash 内容を見るには: git -C $BRAIN_DIR stash list"
echo "╚══════════════════════════════════════════════════════════════╝"
