# Claude Code — Romy入口（旧BulletGO。Vault・NotionではBulletGO）

@AGENTS.md

上のAGENTS.mdはこの開発リポジトリの共通ルール。Vaultのノートは自動importせずObsidian MCPで読む。

開始時にObsidian MCPのviewで `/Users/kitaderuwa/obsidian` の `CLAUDE.md` と、そこが指定する `AIOS/bootstrap.md`・MI・共通安全規則・triggers・BulletGO Hubを原文で読む。Vaultの物理パスとMCPの相対パスを区別し、viewにはVaultルート相対パスを指定する。

Obsidian / Notion / Xcodeの登録・認証・実際の読取を確認する。未接続や取得不能なら報告し、仕様や接続成功を推測しない。MCPの初期接続手順はVaultの `tools/claude-code.md`。入口を置いただけで接続完了とは扱わない。

`xcodebuild` を直接使うときは `xcbeautify` でログを整形する。`swiftlint` / `swiftformat` は今回変更したファイルだけに使う（詳細はAGENTS.mdのVerification）。

日常のトリガーはVault共通手順に従い、実装のGit・変更範囲・検証はこのリポジトリのAGENTS.mdに従う。Dailyフッターは `Claude更新:`。定期実行は既存Work / Codex側に残す。
