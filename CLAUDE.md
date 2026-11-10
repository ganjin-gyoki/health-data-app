## 個人ナレッジの自動読み込み（リモートセッション）

このリポジトリには `.claude/hooks/session-start.sh` が設定されています。Claude Code on the web 等のリモートセッションでは、起動時に ganjin-gyoki/claude-knowledge（プライベートリポジトリ）を `.claude/claude-knowledge/` に取得し、プロジェクトルートの `CLAUDE.local.md` から `@import` して個人ナレッジ（日本語ライティング規約・LaTeXテンプレート・各プロジェクトの技術ナレッジ等）をコンテキストへ読み込みます。ローカルPCでは `~/.claude/CLAUDE.md` 側の設定が同じ役割を果たすため、このフックはリモート限定です。

取得に失敗した場合、フックは黙って終わらずに復旧手順を出力し、同じ内容を `CLAUDE.local.md` にも書きます。private リポジトリはセッションスコープに入っていないと clone できないため、`add_repo` で `ganjin-gyoki/claude-knowledge` を追加してからフックを再実行してください。クラウド環境の環境変数に `CLAUDE_KNOWLEDGE_TOKEN`（claude-knowledge への読み取り権限を持つ GitHub トークン）を設定しておくと、この手順自体が不要になります。

`.claude/agents/` の `light-worker`・`log-digger`・`code-searcher`・`test-runner`・`Explore`・`web-researcher` は claude-knowledge の `agents/` から配布したサブエージェント定義です。リモートセッションでも使えるようリポジトリに置いています。直接編集せず、claude-knowledge 側を直して `apply_hook.py` で配り直してください。
