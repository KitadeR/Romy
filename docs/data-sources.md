# フォント・データの出典と確認記録

確認日：2026年10月29日。[出典表示の入口](../THIRD_PARTY_NOTICES.md)へ戻る。

この記録は取得元・加工方法・現物との対応を残すためのものです。確認日、元データの対象時点、取得・生成日は別々に記載し、記録がない取得日を推定で埋めていません。

## フォント

| 対象 | 配置 | 条件の原文 |
| --- | --- | --- |
| Zen Kaku Gothic New | Resources/Fonts内のRegular／Medium／Bold | [OFL-ZenKakuGothicNew.txt](../Romy/Resources/Fonts/OFL-ZenKakuGothicNew.txt) |
| Plus Jakarta Sans | Resources/Fonts/PlusJakartaSans.ttf | [OFL-PlusJakartaSans.txt](../Romy/Resources/Fonts/OFL-PlusJakartaSans.txt) |

両方とも保存済み原文はSIL OFL 1.1。著作権表示は原文のまま保持しています。[SIL公式FAQ](https://openfontlicense.org/ofl-faq/)のモバイルアプリ同梱に関する説明を確認しました。

手元の最新Debug-iphoneos／Debug-iphonesimulatorのRomy.appで、フォント4ファイルとOFL原文2ファイルが存在し、リポジトリの同名ファイルとSHA-256が一致することを確認しました。今回新たなビルドは実行していません。この結果は既存の開発用成果物の確認であり、提出するArchive／IPAの確認済みという意味ではありません。

アプリ内でフォント・データの出典をまとめて閲覧する画面は今回確認できていません。表示用文書・索引を提出版にどう同梱し、利用者から開けるようにするかは残る対応です。

## 観光地データ

### 現物と生成記録

- ファイル：[sights.json](../Romy/Resources/Data/sights.json)、2,500件。
- 生成処理：[build_sights.py](../Tools/sights/build_sights.py)、読み推定：[reading.swift](../Tools/sights/reading.swift)。
- [既存の取得元・再生成方法](../Tools/sights/README.md)。今回データの再生成・ネットワークからの全件再取得はしていません。
- 生成レポートの日付：2026年10月15日。内訳の記録はWikidataの読み984件／Wikipedia冒頭の読み1,465件／推定51件です。これは当時のレポート値であり、今回の再実行結果ではありません。

### 取得元と加工

1. WikidataのSPARQLで候補・日本語名・位置を取得し、別名や読み等を補います。対象は構造化データで、[公式条件はCC0](https://www.wikidata.org/wiki/Wikidata:Licensing)です。
2. 日本語WikipediaのMediaWiki API（prop=pageviews）から直近60日の閲覧数を取得し、候補選定に利用します。[Wikimedia Analyticsのデータ利用条件](https://doc.wikimedia.org/generated-data-platform/aqs/analytics-api/documentation/access-policy.html)も確認しています。
3. Wikidataに読みがない場合、MediaWiki API（prop=extracts）の記事冒頭から括弧内の読みを抽出します。長い本文はsights.jsonに保存せず、読みを空白等の除去・ひらがなへの正規化後に保存します。文章の再利用については[Wikimedia利用規約第7節](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content)と[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)を参照し、元ページ・加工内容・ライセンスの表示を用意します。
4. 読みが取れない名称と別名にはmacOSの読み推定を利用します。

### 元ページの索引

[2,500件の出典索引CSV](data-sources/sights-source-index.csv)は、sights.jsonのQIDと、保存済みcandidates.jsonのQID・記事名を突き合わせた対応表です。全2,500件に対応する記事名が存在することを確認しました。元のキャッシュ全体を公開するのではなく、対象データのIDと記事名だけを取り出しています。

- Wikidata：`https://www.wikidata.org/wiki/` にwikidata_idを続けたURL。
- 日本語Wikipedia：`https://ja.wikipedia.org/wiki/` にwikipedia_titleの空白をアンダースコアへ変換し、URLエンコードして続けたURL。各記事の履歴から寄稿者をたどれます。

この索引は候補・閲覧数・読みの確認に用いた記事を追うための対応表です。「2,500件すべてでWikipediaの読みを抽出した」という意味ではありません。記事の取得時点の版IDや、個々の読みがWikipedia由来か推定かの記録は出力JSONに保存されていません。

### 確認が残ること

- 現存details.jsonで読みがあるものは823件で、生成レポートの984件とは一致しません。キャッシュと最終生成時点の同一性を確認できないため、キャッシュから個々の読みの出所を確定した分類は作っていません。
- Wikipediaから抽出した個々の読みの権利範囲・記事別の追加条件、加工データを再配布する際の表示の最終確認は残っています。JSON全体を一律CC0とは宣言しません。
- 次回再生成時に、読みの取得元の種類・記事URL・取得日または版IDを別途保存すると、追跡を確実にできます。今回は生成コード・検索データは変更していません。

## 市区町村データ

- ファイル：[municipalities.json](../Romy/Resources/Data/municipalities.json)、1,794件（都道府県の項目等も含むため、市町村だけの数ではありません）。
- コードの出典コメント：[DestinationCatalog.swift](../Romy/Search/DestinationCatalog.swift)。総務省「全国地方公共団体コード」、2024年1月1日時点。
- [公式配布ページ](https://www.soumu.go.jp/denshijiti/code.html)の「都道府県コード及び市区町村コード」に2024年1月1日更新の表があることを確認しました。コード・都道府県・名称・読み・都道府県かどうか等を検索用JSONで保持しています。
- [総務省の利用条件](https://www.soumu.go.jp/menu_kyotsuu/policy/tyosaku.html)はPDL1.0に準拠した利用条件、出典と加工した旨の表示を案内しています。[PDL1.0本文](https://www.digital.go.jp/resources/open_data/public_data_license_v1.0)も参照してください。
- 正確な取得日と、元Excelとの全行照合は今回確認していません。総務省公式データそのものと誤認されないよう、Romy向け加工であることを表示します。

## 祝日データ

- ファイル：[syukujitsu.csv](../Romy/Resources/Data/syukujitsu.csv)、1,067行（見出しを除く）。最初の日付1955/1/1、最後2027/11/23。CP932で読み取れるCSVです。
- [公式配布ページ](https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html)／[配布CSV](https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv)。
- [HolidayCalendar.swift](../Romy/Domain/HolidayCalendar.swift)で読み込み、連休等の候補計算に利用。入力CSVと、Romyが算出・表示する候補を区別します。
- [内閣府の利用規約](https://www.cao.go.jp/notice/rule.html)で、個別表示がない限りPDL1.0を適用する旨を確認しました。出典表示に加え、Romyによる計算・表示であることを記載します。
- 正確な取得日は記録から確認できていません。確認日を取得日と偽って記載せず、対象ファイルのハッシュで識別します。

## 確認したファイルのSHA-256

この識別値は、今回調べたファイルと提出版の同一性を後で照合するためのものです。

| ファイル | SHA-256 |
| --- | --- |
| Romy/Resources/Data/sights.json | `bd28cc20cac5ea739b854bd0a4e8c07aaec7f5b5b521bfa432b7b9181d52539a` |
| Romy/Resources/Data/municipalities.json | `e1072cd7eb60634fadeedd09535fc8a87d1fa3ed1aac95ab21054c86adbbf6d4` |
| Romy/Resources/Data/syukujitsu.csv | `cec37a743c96995cdb9cb52b685c9003634682a9b0e1a640a6b9b96881fe964a` |
| Romy/Resources/Fonts/OFL-ZenKakuGothicNew.txt | `0fac78a235c98d640cb06332eb5362c211d86fa03c011df438c35005d22ad2c7` |
| Romy/Resources/Fonts/OFL-PlusJakartaSans.txt | `995c7199cab65954f545996326755daee7b63cc6b42b06c13da1f9502ab08a99` |
| 出典索引CSV | `33d1e9db52d39d6912ec20ce58935e8999c0434572704342f20452fd218dfbe4` |

## 確認方法の補足

2026年10月29日に公式の規約・配布元、生成スクリプト・保存キャッシュ・既存ビルド成果物を読み取り確認しました。総務省のページはブラウズ用ツールで取得できなかったため、同じ公式URLのHTMLを直接取得し、CP932で読み取り確認しています。アプリの実装・生成データ・GitHubの公開設定は変更していません。
