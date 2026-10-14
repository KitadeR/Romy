# AGENTS.md

## 共通運用とプロジェクトの入口（2026-10-06）

- このファイルはRomy（アプリ名。2026-10-14決定、旧BulletGO。ストア名はリリース前に最終確認）開発リポジトリの実装・Git・検証ルール。日常のVault運用・トリガー・外部操作の境界は共通運用側を参照し、全文をここへ複製しない。
- MacのVaultは `/Users/kitaderuwa/obsidian`。ノートの読書き・一覧・リンク調査はObsidian MCPを使う。MCP名は実際の接続で確認する。未接続・障害・不足は報告し、フォールバックはVaultのアクセス規則に従う。
- 作業開始時にObsidian MCPのviewで `AIOS/bootstrap.md` → `AIOS/MI.md` → `AIOS/operating-rules.md` → `AIOS/triggers.md` → 該当手順・Topic-Router・ `Projects/Romy/Hub.md` を原文で読む。
- Work/Codexの共通運用入口はVaultのAGENTS.md、Claude CodeはVaultのCLAUDE.mdとtools/claude-code.md。入口が別ディレクトリにあるだけで自動読込済みとしない。
- 旧開発入口の全文はVaultの `AIOS/archive/BulletGO_開発入口旧版_2026-10-06.md` に非適用の履歴として保存した。

## Product Context と資料の正

- 現行の方向・採用範囲・未決定事項はRomy Hubと、 `AIOS/manuals/notion-obsidian.md` が指定する最新Notionから確認する。ここに製品仕様を固定しない。
- Projectsの現行説明・採用判断・進捗はNotion。Obsidianは原資料・経緯・ログ・現行コピーと反映履歴。現行仕様で判断する前に必要なNotionを最新取得する。不可ならコピーの取得/反映日時と未確認を示し、未決定を推測で実装しない。
- Hubが旧版・参考・非採用として扱う資料や旧実装の完了/残作業を、新版の採用範囲や進捗として復活させない。再構築方針の採用だけでコードの削除・全面変更の実行許可があると解釈しない。
- 毎回全資料を読む必要はない。共通入口とHubを読み、依頼に関係する採用済みの設計・資料だけを追加で読む。必要な判断を解決できなければ、その判断を確認してから変更する。
- 実装の都合だけで製品仕様や採用した構造を変えない。旧Architectureの維持も全面廃棄も自動で決めず、現在の採用判断と今回の依頼に従う。

## Before Implementation

大きな変更の前に、短く以下を整理する。

- 今回実装する動作と、今回触らない範囲
- 参照したHub・Notion・設計と未確認事項
- 影響するモデル・状態
- 変更予定ファイルと完成の確認方法

- 依頼された動作を実現するために必要な変更を行う。周辺画面の再設計・機能追加・保存方式変更・大規模リファクタリングを付随改善として広げない。必要なら理由・影響・範囲を示して判断を戻す。
- 既存の命名やデータフローを把握し、採用済みの設計に従う。具体的に承認されていないMVP機能や、将来の願いを今回の範囲へ追加しない。
- デモ専用データ・仮導線を完成した本物の機能と報告しない。実装済み／骨格／未実装の扱いは現在の採用設計に従い、Coming Soonを一律追加しない。

## Knowledge Updates と記録

- 実装中に資料との差分や新たな仕様判断の必要性を見つけたら、何を・なぜ変える必要があるかを示す。コードの都合で確定仕様や人間の原資料を黙って変更しない。
- AIとの相談で採用した変更をNotionへ反映する場合、 `AIOS/manuals/notion-obsidian.md` の手順・変更前履歴・全文反映・読み戻しを同じ作業で行う。単なる取り込み依頼ではNotion本文やGoogleを変更しない。
- 区切り／終了時に `AIOS/manuals/daily-note.md` に従い当日Dailyへ詳細ログをObsidian MCPで追記する。変更ファイル・機能・理由・検証・課題・次を残し、未反映なら報告する。

## Git Safety

- 作業前に現在のbranchとworking treeを確認する。mainが最新実装とは限らない。
- 既存の未コミット変更を保持し、無関係なファイルを上書き・破棄・整形しない。
- ユーザーの明示的な指示なしにbranch作成、merge、pushを行わない。
- CodexとClaude Codeが同じファイルを同時編集しない。引き継ぎ時は対象・差分・検証結果・残作業を記録し、未コミット変更を含めて読み直す。

## Xcode Tooling

- XcodeBuildMCPを使う場合、利用環境にある対応skillを呼び出し前に読む。
- `.xcodebuildmcp/config.yaml` の既存設定を優先する。既存設定のProject Romy.xcodeproj、Scheme Romy、Simulator iPhone 17 Pro Maxは実環境で確認し、勝手に変更しない。
- Build / Run / Test / Simulator / Screenshot / UI Automation / Debuggingには利用可能なXcodeツールを使う。必要に応じて通常のxcodebuildも使用できる。
- 接続名・認証・利用可能な操作を確認し、Cursorや別フォルダのXcode登録をClaude Codeで接続済みと扱わない。
- Apple APIやSDKが不確かな場合はApple公式ドキュメントを確認する。BestWay専用implementation-briefをRomyへ一律適用しない。

## Verification

- 実装後はXcodeBuildMCPまたはxcodebuildでBuildを確認する。Build errorがある状態を完了としない。
- UI変更はSwiftUI PreviewまたはSimulatorで確認する。
- 変更に関係する意味のあるTest・検証を行い、実行しなかった範囲は明記する。
- `xcbeautify` が導入済み（2026-10-06確認）。`xcodebuild` を直接使うときは `2>&1 | xcbeautify` でログを短くしてよい。XcodeBuildMCPの出力には不要。
- `swiftlint` / `swiftformat` が導入済み（2026-10-06確認）。使う場合は今回変更したファイルだけに限定し、無関係なファイルの整形をしない。設定ファイル（`.swiftlint.yml` 等）の追加やリポジトリ全体への適用は、ユーザーの承認後に行う。
- 検証でエラーが出たら内容・推定原因・影響するファイルを報告する。依頼外の修正を無断で追加せず、今回の変更が原因の修正と以前からの問題を区別する。
