# DaysYet

**時間を、積み重ねる。今日を選ぶ。**

今週、今月、今年、活動時間、健康でいたい年齢、大切な日から選び、時間の残りと進み具合を静かに見渡すiPhone / iPad / Macアプリです。iPhone / iPadではホーム画面に3つ、ロック画面に1つを表示。Macでは画面端に常駐する3つの時間から、必要な詳細を開けます。3つの表示モードと4つのカラーテーマを選べます。

iPhone / iPad版は[App Store](https://apps.apple.com/jp/app/id6802000765)で提供しています。Mac版はこのリポジトリからビルドできます。Mac版のストア配布・署名済みダウンロードはまだ提供していません。

## Features

- アプリで選んだ3本を1つのホーム画面ウィジェットに表示
- ホーム画面ウィジェットごとに3本、表示形式、テーマを上書き可能
- ロック画面ウィジェットには選んだ1本を表示
- 今週、今月、今年、2種類の活動時間、本人が設定する健康年齢の目標、起算日を指定できる任意の目標日時
- 週の始まりは端末のカレンダー設定に従うか、日曜〜土曜のいずれかを指定可能
- 2種類の活動時間に、それぞれ任意のラベル名、開始・終了時刻、有効な曜日を設定。曜日ごとのOffと日をまたぐ活動にも対応
- カウントダウン／時間＋経過割合＋バー／プログレスバーの切り替え
- プログレスバーは経過時間を左から積み重ね、右側の値を残り時間・経過割合・終了日時から切り替え
- 夜の彩り、静かな森、やわらかな朝、凪の海の4テーマ
- ホーム画面の`systemSmall` / `systemMedium`と、ロック画面の`accessoryInline` / `accessoryCircular` / `accessoryRectangular`
- Macの画面端に常駐する、細い黒いパネル。左右には中央に経過割合を表示する3つの円形メーター
- Macでは小さな詳細表示が広がり、カウントダウン／時間＋経過割合＋バー／プログレスバーから表示モードを選択。プログレスバー表示では値を残り時間・経過割合・終了日時から選べる。左右では選んだサークルの高さに合わせて、詳細と黒いパネルの膨らみが上下に移動する。本体をダブルクリックして設定を表示。詳細はポインタを合わせると開き、外すと閉じる。「詳細を開いたままにする」を選んだ場合は、設定でオフにして閉じる
- Macの表示先ディスプレイ、左右・上端の配置、上下位置、表示・非表示を設定。左右では本体を上下にドラッグして移動でき、位置は再起動後も保持
- 上端ではMacのカメラ下に3本の細いプログレスバーを表示し、詳細を開くときだけ下へ拡張。バーとその直上16ポイントにポインタを合わせて項目を切り替え。それより上のカメラ部分では現在の項目を開く。上端のバーの帯は標準で8ポイント、線の太さは2ポイントで、どちらもサイズ設定に合わせて拡大・縮小。カメラ部分の実寸は変えない。カメラのないディスプレイでは上端中央に配置
- Macのサイズは80〜150%（標準100%）で調整でき、サークルと文字も一緒に拡大・縮小。上端のバーの帯と線の太さも連動
- 日本語（primary / fallback）とEnglish
- VoiceOver、Dynamic Type、色だけに依存しない情報表示
- アカウント、広告、分析SDK、アプリからの外部送信なし
- 端末内データの全削除

「健康でいたい年齢」は利用者自身が決める計画上の目標であり、統計値、診断、健康状態や寿命の予測ではありません。

「活動時間」は2種類を個別に設定し、表示する項目から任意で選べます。新規利用時の初期値は、私用を含めた「1日の活動」（毎日7:00〜23:00）と「勤務時間」（月曜〜金曜9:00〜18:00、土日はOff）です。どちらもラベル名、開始・終了時刻、有効な曜日を自由に変更できます。従来の「勤務時間」を設定済みの場合は、時刻と表示する項目の選択を引き継ぎ、曜日は従来どおり毎日有効になります。

活動時間は端末の現地時刻で計算し、有効な日は開始前に「開始前」、活動中に残り時間、終了後に「活動終了」を表示します。無効な曜日は「Off」を表示します。22:00〜翌6:00のように日をまたぐ活動は開始日の曜日に従い、翌日がOffでも終了時刻まで続きます。開始と終了を同じ時刻にすると、有効な開始日から24時間として扱います。活動時間のラベル、時刻、曜日は各端末に保存され、他の端末には同期されません。

「週の始まり」はMacの「設定 → 時間」、iPhone / iPadの時間の編集画面で変更できます。初期状態では端末のカレンダー設定に従い、現在使われる曜日を画面で確認できます。曜日を指定すると、現地時刻のその曜日0:00から翌週の同じ曜日0:00までを「今週」として計算し、アプリ・Macの常駐表示・ホーム画面・ロック画面の残り時間、経過割合、終了日時へ反映します。

## Privacy

入力した日付と設定は端末内へ保存します。iPhone / iPadではアプリとWidget Extensionだけが共有するApp Group領域、MacではMacアプリ専用のサンドボックス内に保存します。端末間の同期はありません。詳しくは[プライバシーポリシー](PRIVACY.md)と[データマップ](docs/PRIVACY_DATA_MAP.md)をご覧ください。

公開サイトは日本語とEnglishの各1ページです。各案内へページ内リンクで直接移動できます。

- [日本語 Product](https://daysyet.hinoshiba.com/) / [English Product](https://daysyet.hinoshiba.com/en/)
- [Privacy](https://daysyet.hinoshiba.com/#privacy) / [English](https://daysyet.hinoshiba.com/en/#privacy)
- [Terms](https://daysyet.hinoshiba.com/#terms) / [English](https://daysyet.hinoshiba.com/en/#terms)
- [Support](https://daysyet.hinoshiba.com/#support) / [English](https://daysyet.hinoshiba.com/en/#support)
- [Accessibility](https://daysyet.hinoshiba.com/#accessibility) / [English](https://daysyet.hinoshiba.com/en/#accessibility)
- Contact: [support@hinoshiba.com](mailto:support@hinoshiba.com)

## Build

必要環境:

- iOS / iPadOS 17以降
- macOS 14以降（Mac版）
- Xcode 16以降
- XcodeGen 2.45.4

```bash
./build.sh project
./build.sh
./build.sh test
./build.sh mac
./build.sh test-mac
```

`project.yml`がXcodeプロジェクト設定の正本です。生成される`DaysYet.xcodeproj`と共有schemeもコミットし、CIで生成結果の一致を確認します。設定を変更したら`./build.sh project`を実行し、両方を同じ変更に含めてください。上記のビルド・テストは署名を必要としません。署名情報はGit管理外の`Config/Signing.local.xcconfig`で設定し、App Store向けのArchive・検証・アップロードは、このMacのXcodeとOrganizerで明示的に行います。準備と手順は[ローカルXcodeリリース手順](docs/RELEASING.md)をご覧ください。

Mac版は`DaysYetMac` schemeでビルドします。Xcodeで`DaysYet.xcodeproj`を開き、`DaysYetMac`と「My Mac」を選んで実行してください。初回起動では画面の右端に今週・今月・今年を表示します。ウィジェット本体をダブルクリックして設定を開き、表示する時間、詳細の表示モード、プログレスバー表示時の値（残り時間・経過割合・終了日時）、テーマ、ディスプレイ、左右・上端の配置、左右配置時の上下位置、サイズ（80〜150%、標準100%）を変更できます。サイズに合わせてサークルと文字も変わります。設定画面を閉じても常駐表示は続きます。表示・非表示と終了は設定から操作できます。非表示にした場合は、DaysYetをもう一度起動すると設定が開き、表示を戻せます。Mac版はネイティブの常駐アプリで、macOSのウィジェットギャラリーから追加するWidgetKit拡張ではありません。

## Repository layout

```text
Shared/                 日付計算、モデル、端末内永続化、共通翻訳
DaysYet/                iPhone / iPadのSwiftUIアプリ
DaysYetWidget/          iPhone / iPadのWidgetKit + AppIntent
DaysYetMac/             macOSネイティブアプリと常駐パネル
DaysYetTests/           共通ロジックの単体テスト
AppStore/               App Store Connect提出情報の正本
http_dist/              GitHub Pagesへ公開するWebページ
docs/                   公開可能な技術・コンプライアンス資料
Scripts/                検証、バージョン更新、スクリーンショット取得
project.yml             XcodeGenの正本
```

iPhone / iPad版App Storeのprimary languageは日本語、追加localizationはEnglish (U.S.)です。Mac版は既存のDaysYet掲載にmacOSプラットフォームを追加する構成で、両アプリのBundle IDは`com.hinoshiba.daysyet`を使います。設定データは引き続き各端末のサンドボックスに保存し、端末間では同期しません。提出用資料は[`AppStore/`](AppStore/)で管理します。Mac版の公開には、Mac向けのメタデータ・スクリーンショット・署名・動作確認が別途必要です。

## Contributing and releases

- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Dependency policy](docs/DEPENDENCY_POLICY.md)
- [Local Xcode release procedure](docs/RELEASING.md)
- [0.1.4 次回リリース準備](AppStore/releases/0.1.4.md)
- [0.1.4 次回リリース準備](AppStore/releases/0.1.4.md)

依存、素材、フォント、SDK、データセットを追加する変更は、NOTICE、資産・データ台帳、プライバシーへの影響も同時に更新してください。

## License

ソースコードと通常ドキュメントは[Apache License 2.0](LICENSE)です。商用利用・販売・変更・再配布が可能です。ブランド名、ロゴ、App Icon、Store素材は同ライセンスの対象外です。詳細は[TRADEMARKS.md](TRADEMARKS.md)、[ASSET_LICENSES.md](ASSET_LICENSES.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)をご確認ください。

Apache-2.0 © 2026 hinoshiba.
