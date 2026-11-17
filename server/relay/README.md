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

`PERPLEXITY_API_KEY` はGit管理外の `.dev.vars` に設定します。アプリ用の `APP_TOKEN` は公開環境のSecretで管理し、値をコミットしません。

## 検索と読み取り

宿の荷物預かりと営業時間は、PerplexityのSearch APIで抜粋を集め、Workers AI（`@cf/google/gemma-4-26b-a4b-it`、`wrangler.toml` の `AI` バインディング）が読み取ります。宿名・店名を含まない抜粋は読ませず、同じ宿かどうかと公式かどうかの最終判断はコードで行います。検索は1回0.005ドルとして日次上限に数え、読み取りはWorkers AIの無料枠（1日1万Neuron）を使います。PerplexityのAgent APIは有料クレジットが必要なため使っていません（一言の解釈の入口だけ旧来のAgent APIのまま残り、アプリは端末内で解釈するため呼びません）。

## 判定の評価

`eval/` は保存した検索結果で宿の荷物預かりの判定を採点します。正解は `eval/luggage/expected.json`（各宿の公式ページで確認）。検索結果 `eval/luggage/search/` は他社の抜粋を含むためGit管理外です。

```sh
npx wrangler dev -c eval/wrangler.toml --port 8797   # 別のターミナルで
node eval/score.mjs 3
```

## Romy Now

`POST /v1/scene` に `session`（UUID）と次のいずれかを渡します。既存の `X-Romy-Device` / `X-Romy-Token` による認証・上限を共用します。

- `operation: "interpret"`：`text`（300文字まで）から食べ物・店舗種別、徒歩上限、休憩時間、全体の時間を抽出。未対応の希望は `unhandled` に返す。
- `operation: "hours"`：`name`, `address`, `date`（現地日付）, `timeZone` で営業時間を確認。別支店・別日・出典不一致・矛盾は `unknown` に返す。

同じセッションの解釈は1回、検索は宿の荷物預かりを含めて3回までです。既存アプリとの互換性のため `/v1/check` の `session` は省略できます。新しいRomy Nowは必ず送ります。検索の端末日次上限・全体の費用上限は `wrangler.toml` の既存値を使います。セッションIDと端末IDは本人認証の代わりにはなりません。

一言は共有DBへ保存せず、内容をログにも残しません。営業時間は店舗・対象日・タイムゾーンごとに、公式確認なら1時間、未確認なら5分間キャッシュします。営業区間は現地日の0時からの分数で、翌日2時は1560です。到着・出発・ラストオーダーとの比較はアプリが行います。空席や臨時変更は保証しません。

本番反映時は `0002_scene_sessions.sql` をD1へ適用してからWorkerを反映します。既存テーブルのデータ削除やアプリの秘密値の変更は不要です。

API仕様は [Perplexity Search API](https://docs.perplexity.ai/getting-started/pricing) と [Workers AI](https://developers.cloudflare.com/workers-ai/platform/pricing/) を参照しています。
