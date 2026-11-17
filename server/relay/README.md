# Romyの中継API

APIキーをアプリに含めず、公開情報の確認・一言の解釈と費用制限を担当します。

## 開発・検証

```sh
npm ci
npm test
npm run typecheck
npm run db:local
npm run dev
```

`PERPLEXITY_API_KEY` はGit管理外の `.dev.vars` に設定します。Agent APIには有料APIクレジットが必要です。アプリ用の `APP_TOKEN` は公開環境のSecretで管理し、値をコミットしません。

## Romy Now

`POST /v1/scene` に `session`（UUID）と次のいずれかを渡します。既存の `X-Romy-Device` / `X-Romy-Token` による認証・上限を共用します。

- `operation: "interpret"`：`text`（300文字まで）から食べ物・店舗種別、徒歩上限、休憩時間、全体の時間を抽出。未対応の希望は `unhandled` に返す。
- `operation: "hours"`：`name`, `address`, `date`（現地日付）, `timeZone` で営業時間を確認。別支店・別日・出典不一致・矛盾は `unknown` に返す。

同じセッションの解釈は1回、検索は宿の荷物預かりを含めて3回までです。既存アプリとの互換性のため `/v1/check` の `session` は省略できます。新しいRomy Nowは必ず送ります。検索の端末日次上限・全体の費用上限は `wrangler.toml` の既存値を使います。セッションIDと端末IDは本人認証の代わりにはなりません。

一言は共有DBへ保存せず、内容をログにも残しません。営業時間は店舗・対象日・タイムゾーンごとに、公式確認なら1時間、未確認なら5分間キャッシュします。営業区間は現地日の0時からの分数で、翌日2時は1560です。到着・出発・ラストオーダーとの比較はアプリが行います。空席や臨時変更は保証しません。

本番反映時は `0002_scene_sessions.sql` をD1へ適用してからWorkerを反映します。既存テーブルのデータ削除やアプリの秘密値の変更は不要です。

API仕様は [Perplexity Agent API](https://docs.perplexity.ai/docs/agent-api/models) と [Output Control](https://docs.perplexity.ai/docs/agent-api/output-control) を参照しています。
