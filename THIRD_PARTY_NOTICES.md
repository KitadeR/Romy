# 第三者のフォント・データに関する表示

確認日：2026年10月29日。対象はRomyに同梱しているフォントと検索・日付用データです。取得・加工の詳細と確認が残る点は[データの出典記録](docs/data-sources.md)に記載しています。

## フォント

### Zen Kaku Gothic New

Copyright 2022 The Zen Kaku Gothic Project Authors (https://github.com/googlefonts/zen-kakugothic)

- ライセンス：SIL Open Font License 1.1
- [同梱している著作権表示・ライセンス全文](Romy/Resources/Fonts/OFL-ZenKakuGothicNew.txt)
- 対象：Regular／Medium／Boldの3ファイル

### Plus Jakarta Sans

Copyright 2020 The Plus Jakarta Sans Project Authors (https://github.com/tokotype/PlusJakartaSans)

- ライセンス：SIL Open Font License 1.1
- [同梱している著作権表示・ライセンス全文](Romy/Resources/Fonts/OFL-PlusJakartaSans.txt)
- 対象：PlusJakartaSans.ttf

フォントの著作権表示・ライセンス原文は元のファイルを保持しています。[OFL公式本文](https://openfontlicense.org/open-font-license-official-text/)／[モバイルアプリへの同梱に関する公式FAQ](https://openfontlicense.org/ofl-faq/)。

## 観光地検索用データ

- 場所の名称・別名・読み等の基礎情報：Wikidataの構造化データ。CC0 1.0。[公式ライセンス説明](https://www.wikidata.org/wiki/Wikidata:Licensing)
- 候補の順位付けに利用した閲覧数：Wikimediaのページ閲覧統計。Wikimedia Analyticsのデータ提供条件はCC0 1.0。[公式利用条件](https://doc.wikimedia.org/generated-data-platform/aqs/analytics-api/documentation/access-policy.html)
- 読みの一部：日本語版Wikipedia各記事の冒頭から抽出し、空白等の除去・ひらがなへの正規化を行っています。Credit: Wikipedia contributors。文章の標準的な再利用条件は[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)です。[Wikimedia利用規約第7節](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content)に従い、元記事と加工内容を示します。
- 取得対象記事：[観光地2,500件のWikidata ID・Wikipedia記事名の索引](docs/data-sources/sights-source-index.csv)。元ページへのリンクの作り方と索引の範囲は[出典記録](docs/data-sources.md#観光地データ)を参照してください。
- 読みが見つからない場合と別名の読み：macOSの日本語処理を使った推定を含みます。実際の読みを保証するものではありません。

Wikipediaの読みの個別の権利範囲・追加条件と、加工データの再配布表示の最終確認は残っています。複数の取得元を含むsights.json全体を、一括してCC0とは表示していません。

## 市区町村データ

出典：総務省「全国地方公共団体コード」の「都道府県コード及び市区町村コード」（2024年1月1日更新）をもとに、北出琉和が検索用JSONへ加工して作成。

- [配布元](https://www.soumu.go.jp/denshijiti/code.html)
- [総務省の利用条件](https://www.soumu.go.jp/menu_kyotsuu/policy/tyosaku.html)
- [公共データ利用規約1.0](https://www.digital.go.jp/resources/open_data/public_data_license_v1.0)

元のExcelそのものではなく、Romy用に整形したデータです。元ファイルとの全行照合と取得日の復元は未実施です。

## 祝日データ

出典：内閣府「国民の祝日」について掲載の祝日・休日CSV。Romyは同梱CSVを読み込み、「次の3連休」等の日付候補を計算しています。計算結果・画面表示はRomyによるものです。

- [配布元](https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html)
- [内閣府の利用規約](https://www.cao.go.jp/notice/rule.html)
- [公共データ利用規約1.0](https://www.digital.go.jp/resources/open_data/public_data_license_v1.0)

## この表示の範囲

取得元ごとの条件を区別して記載しています。この文書でRomyのソースコード全体のライセンスを新たに指定したものではありません。アプリ内の出典閲覧導線と、提出版へのこれらの表示の同梱は、最終版で確認します。

## アプリへの組み込み用ファイル（統合前）

- [出典表示・フォントの著作権表示・OFL原文全文](Romy/Resources/Acknowledgements/RomyAttributions.txt)
- [元記事とWikidataへの直接URL付き索引](Romy/Resources/Acknowledgements/RomySourceArticles.csv)
- [組み込み・同梱・画面表示の確認手順](docs/attribution-integration.md)

これらは文書ブランチ上に準備したファイルです。提出するアプリへ統合し、閲覧できる状態にする作業と最終確認はこれからです。
