#!/bin/bash
# 個人ナレッジ（ganjin-gyoki/claude-knowledge）をリモートセッションのコンテキストへ読み込む。
#
# ローカルPCでは ~/.claude/CLAUDE.md 側の @import が同じ役割を果たすため、
# 二重読み込みを避けてリモート限定にしている。
#
# 設計上の要点（2026-09-11、スマホから読み込めない原因を調べて書き直した）:
#
#  1. 起動時に読み込まれる CLAUDE.local.md は「プロジェクトルート」のものだけ。
#     旧版は .claude/CLAUDE.local.md に書いていたが、.claude/ はサブディレクトリ
#     なので起動時には読まれない（Claude がそのディレクトリのファイルを読んだとき
#     にオンデマンドで読まれるだけ）。ここではルートに書く。
#     出典: docs/claude-code/ja/memory.md「CLAUDE.md ファイルの読み込み方法」
#
#  2. 失敗しても黙って終わらない。SessionStart の stdout は Claude が読む
#     コンテキストとして追加されるので、失敗時はそこへ復旧手順を出す。
#     stderr はユーザーにしか表示されず Claude には届かないので使わない。
#     出典: docs/claude-code/ja/hooks.md「終了 0」の節
#
#  3. private リポジトリの clone は、セッションスコープ外だと認証情報が
#     プロキシから注入されず失敗する。CLAUDE_KNOWLEDGE_TOKEN があればそれを
#     使い、無ければ add_repo による復旧手順を案内する。
#
#  4. 復旧手順は stdout と CLAUDE.local.md の両方へ出す（2026-09-14 追加）。
#     stdout だけに頼ると、フック自体が起動に失敗した回（実行権限が無い等）に
#     何も残らない。CLAUDE.local.md はプロジェクトルートにあり起動時に必ず
#     読まれるので、こちらが確実な経路になる。取得に成功したときは @import 行、
#     失敗したときは復旧手順そのものを、同じファイルへ書き分ける。

set -uo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
KNOWLEDGE_DIR="$PROJECT_DIR/.claude/claude-knowledge"
IMPORT_FILE="$PROJECT_DIR/CLAUDE.local.md"
LEGACY_IMPORT_FILE="$PROJECT_DIR/.claude/CLAUDE.local.md"
REPO_SLUG="ganjin-gyoki/claude-knowledge"
HOOK_PATH="$PROJECT_DIR/.claude/hooks/session-start.sh"

TOKEN="${CLAUDE_KNOWLEDGE_TOKEN:-}"
if [ -n "$TOKEN" ]; then
  REPO_URL="https://x-access-token:${TOKEN}@github.com/${REPO_SLUG}.git"
else
  REPO_URL="https://github.com/${REPO_SLUG}.git"
fi

# git の出力をそのまま stdout に出すとトークンが混ざりうるので、必ず伏せる。
redact() {
  local text="$1"
  if [ -n "$TOKEN" ]; then
    text="${text//$TOKEN/***}"
  fi
  printf '%s' "$text"
}

git_output=""
if [ -d "$KNOWLEDGE_DIR/.git" ]; then
  # 取得済みなら更新する。失敗しても手元のコピーで続行できる。
  git_output=$(git -C "$KNOWLEDGE_DIR" pull --ff-only 2>&1)
else
  rm -rf "$KNOWLEDGE_DIR"
  git_output=$(git clone --depth 1 "$REPO_URL" "$KNOWLEDGE_DIR" 2>&1)
fi
git_output=$(redact "$git_output")

# 旧版が置いていた、読み込まれない import ファイルを片付ける。
rm -f "$LEGACY_IMPORT_FILE"

if [ -f "$KNOWLEDGE_DIR/knowledge.md" ]; then
  cat > "$IMPORT_FILE" << 'EOF'
# 個人ナレッジ（自動読み込み・claude-knowledgeリポジトリ由来）

@.claude/claude-knowledge/knowledge.md
EOF
  echo "[session-start] 個人ナレッジを取得し、$IMPORT_FILE から読み込んだ。"

  # 配布したサブエージェント定義（apply_hook.py が .claude/agents/ に置く）が
  # 正本より古くないかを確かめる。エージェント定義は起動時に読まれるので、
  # ここで直しても今のセッションには反映されない。気づけるよう1行だけ出す。
  stale=""
  for src in "$KNOWLEDGE_DIR"/agents/*.md; do
    [ -f "$src" ] || continue
    dst="$PROJECT_DIR/.claude/agents/$(basename "$src")"
    if ! cmp -s "$src" "$dst"; then
      stale="$stale $(basename "$src" .md)"
    fi
  done
  if [ -n "$stale" ]; then
    echo "[session-start] .claude/agents/ のサブエージェント定義が claude-knowledge の正本と違う（${stale# }）。このセッションでは使えないか古い版が動く。scripts/session-start-hook/apply_hook.py で配り直す（§9）。"
  fi
  exit 0
fi

# 取得できなかった。壊れた @import を残さず、代わりに復旧手順そのものを書く。
# stdout（フックが起動できた回だけ届く）と CLAUDE.local.md（起動時に必ず読まれる）
# の両方へ同じ内容を出す。
RECOVERY=$(cat << EOF
# 個人ナレッジが未読込（claude-knowledge の取得に失敗）

[session-start] 個人ナレッジ（$REPO_SLUG）を取得できなかった。
ナレッジが未読込のまま作業を始めないこと。日本語ライティング規約や各プロジェクトの
恒久ルールが全て欠けた状態になる。

原因: リモートセッションでは、セッションスコープに入っていないリポジトリへの
git 認証情報がプロキシから注入されない。$REPO_SLUG は private なので、
スコープに追加するまで clone できない。

復旧手順（最初のツール呼び出しとして、この順に実行する）:
  1. add_repo を owner="ganjin-gyoki", repo="claude-knowledge" で呼ぶ
  2. bash "$HOOK_PATH" を実行する
  3. 成功すると $KNOWLEDGE_DIR/knowledge.md が置かれる。
     CLAUDE.local.md はセッション開始後に作られても自動では読み込まれないので、
     このセッションでは knowledge.md を直接 Read してコンテキストに入れる
     （次回以降のセッションは起動時に自動で読み込まれる）

毎回この手順を踏みたくない場合は、クラウド環境の環境変数に
CLAUDE_KNOWLEDGE_TOKEN として claude-knowledge への読み取り権限を持つ
GitHub のトークンを設定する。設定されていればこのフックが自動で使う。

git の出力:
$git_output
EOF
)

printf '%s\n' "$RECOVERY" > "$IMPORT_FILE"
printf '%s\n' "$RECOVERY"
