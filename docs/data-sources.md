# フォント・データの出典と加工方法

記録日：2026年10月30日。[出典表示の入口](../THIRD_PARTY_NOTICES.md)へ戻る。

## フォント

| フォント | 同梱ファイル | 利用条件の原文 |
| --- | --- | --- |
| Zen Kaku Gothic New | Regular／Medium／Bold | [OFL-ZenKakuGothicNew.txt](../Romy/Resources/Fonts/OFL-ZenKakuGothicNew.txt) |
| Plus Jakarta Sans | PlusJakartaSans.ttf | [OFL-PlusJakartaSans.txt](../Romy/Resources/Fonts/OFL-PlusJakartaSans.txt) |

両フォントの著作権表示とSIL OFL 1.1の原文を保持しています。フォント4ファイル・OFL原文2ファイルと、[出典表示TXT](../Romy/Resources/Acknowledgements/RomyAttributions.txt)をアプリに同梱しています。「出典・ライセンス」画面から、フォントの著作権表示とライセンス全文を閲覧できます。

## 観光地データ

### データと生成処理

- データ：[sights.json](../Romy/Resources/Data/sights.json)、2,500件。
- 生成処理：[build_sights.py](../Tools/sights/build_sights.py)。読みの推定：[reading.swift](../Tools/sights/reading.swift)。
- 再生成方法：[Tools/sights/README.md](../Tools/sights/README.md)。
- 名称・別名・読み・位置情報等を、旅行作成時の行き先検索に利用しています。通常の予定を追加するMapKitの場所検索とは、利用範囲を分けています。

### 取得元と加工内容

1. WikidataのSPARQLで候補・日本語名・位置を取得し、読みや別名を補います。[Wikidataの構造化データはCC0](https://www.wikidata.org/wiki/Wikidata:Licensing)です。
2. 日本語WikipediaのMediaWiki API（prop=pageviews）から直近60日の閲覧数を取得し、候補の順位付けに利用します。[閲覧統計の利用条件](https://doc.wikimedia.org/generated-data-platform/aqs/analytics-api/documentation/access-policy.html)を参照してください。
3. 読みが不足する場合、MediaWiki API（prop=extracts）で取得した日本語Wikipedia記事の冒頭から括弧内の読みを抽出します。長い本文は同梱せず、空白等を除去してひらがなへ正規化した読みを保存しています。
4. 読みが取得できない名称と別名には、macOSによる読みの推定を含みます。

Wikipedia由来の読みには、元記事の寄稿者・出典URL・加工内容・[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)へのリンクを出典表示に収録しています。[Wikimedia利用規約第7節](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content)も参照してください。複数の取得元を含むJSON全体を一括してCC0とは表記していません。

### 元記事と読みの照合

[元記事索引CSV](data-sources/sights-source-index.csv)には、2,500件のWikidata IDと対応するWikipedia記事名を収録しています。アプリ用の[直接URL付き索引CSV](../Romy/Resources/Acknowledgements/RomySourceArticles.csv)では、記事名・IDで検索して元サイトを開けます。記事の履歴から寄稿者を確認できます。

2026年10月15日の生成レポートには、Wikidataの読み984件、Wikipediaから補った読み1,465件、推定51件が記録されています。保存済みデータとの追加照合では、Wikidataの読みプロパティ823件と、かなだけの別名161件の合計984件を確認しました。これらは正規化後の出力JSONと一致しています。[照合結果JSON](data-sources/reading-origin-audit.json)を同梱しています。

残る1,516件の個々の読みについて、Wikipedia抽出と推定の区分・記事の取得時点の版IDは保存されていません。索引は、全件でWikipediaから読みを抽出したという意味ではありません。取得日や分類を推定で補ってはいません。

## 市区町村データ

- データ：[municipalities.json](../Romy/Resources/Data/municipalities.json)、1,794件。都道府県の項目を含み、市町村だけの数ではありません。
- 出典：総務省「全国地方公共団体コード」の「都道府県コード及び市区町村コード」、2024年1月1日時点。
- [公式配布ページ](https://www.soumu.go.jp/denshijiti/code.html)／[総務省の利用条件](https://www.soumu.go.jp/menu_kyotsuu/policy/tyosaku.html)／[公共データ利用規約1.0](https://www.digital.go.jp/resources/open_data/public_data_license_v1.0)。

北出琉和が、コード・都道府県・名称・読み等をRomyの検索用JSONへ加工しています。元のExcelそのものではありません。正確な取得日は記録していません。

## 祝日データ

- データ：[syukujitsu.csv](../Romy/Resources/Data/syukujitsu.csv)、1,067行（見出しを除く）、1955/1/1〜2027/11/23。
- 出典：内閣府「国民の祝日」についての祝日・休日CSV。
- [公式配布ページ](https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html)／[配布CSV](https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv)／[内閣府の利用規約](https://www.cao.go.jp/notice/rule.html)／[公共データ利用規約1.0](https://www.digital.go.jp/resources/open_data/public_data_license_v1.0)。

[HolidayCalendar.swift](../Romy/Domain/HolidayCalendar.swift)で読み込み、連休等の日付候補を計算します。計算結果と画面表示はRomyによるものです。正確な取得日は記録していません。

## 同梱ファイルの識別値

| ファイル | SHA-256 |
| --- | --- |
| Romy/Resources/Data/sights.json | `bd28cc20cac5ea739b854bd0a4e8c07aaec7f5b5b521bfa432b7b9181d52539a` |
| Romy/Resources/Data/municipalities.json | `e1072cd7eb60634fadeedd09535fc8a87d1fa3ed1aac95ab21054c86adbbf6d4` |
| Romy/Resources/Data/syukujitsu.csv | `cec37a743c96995cdb9cb52b685c9003634682a9b0e1a640a6b9b96881fe964a` |
| OFL-ZenKakuGothicNew.txt | `0fac78a235c98d640cb06332eb5362c211d86fa03c011df438c35005d22ad2c7` |
| OFL-PlusJakartaSans.txt | `995c7199cab65954f545996326755daee7b63cc6b42b06c13da1f9502ab08a99` |

この記録は同梱ファイルと取得元・加工方法の照合結果です。2026年10月30日の照合では、データの再生成・全件再取得は行っていません。
