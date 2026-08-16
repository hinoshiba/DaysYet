# DaysYet

**時間は、まだある。今日を選ぶ。**

今週、今月、今年、健康でいたい年齢、大切な日から3つを選び、1つのウィジェットで静かに見渡すiPhone / iPadアプリです。表示は、残り時間・割合・終了日時から選べます。

## Features

- アプリで選んだ3本を1つのウィジェットに表示
- ウィジェットごとに3本と表示形式を上書き可能
- 今週、今月、今年、本人が設定する健康年齢の目標、任意の目標日時
- 残り時間、残り割合、終了日時の切り替え
- `systemSmall` / `systemMedium`
- 日本語（primary / fallback）とEnglish
- VoiceOver、Dynamic Type、色だけに依存しない情報表示
- アカウント、広告、分析SDK、アプリからの外部送信なし
- 端末内データの全削除

「健康でいたい年齢」は利用者自身が決める計画上の目標であり、統計値、診断、健康状態や寿命の予測ではありません。

## Privacy

入力した日付とウィジェット設定は、アプリとWidget Extensionだけが共有する端末内のApp Group領域へ保存します。詳しくは[プライバシーポリシー](PRIVACY.md)と[データマップ](docs/PRIVACY_DATA_MAP.md)をご覧ください。

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
- Xcode 16以降
- XcodeGen 2.45.4

```bash
./build.sh
./build.sh test
```

`project.yml`がXcodeプロジェクト設定の正本です。生成される`DaysYet.xcodeproj`はコミットしません。署名チームは各開発者のXcode設定で指定してください。

## Repository layout

```text
Shared/                 日付計算、モデル、App Group永続化、共通翻訳
DaysYet/                SwiftUIアプリ
DaysYetWidget/          WidgetKit + AppIntent
DaysYetTests/           単体テスト
AppStore/               App Store Connect提出情報の正本
http_dist/              GitHub Pagesへ公開するWebページ
docs/                   公開可能な技術・コンプライアンス資料
Scripts/                検証、バージョン更新、スクリーンショット取得
project.yml             XcodeGenの正本
```

App Storeのprimary languageは日本語、追加localizationはEnglish (U.S.)です。提出用コピーとスクリーンショットは[`AppStore/`](AppStore/)で管理します。

## Contributing and releases

- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Dependency policy](docs/DEPENDENCY_POLICY.md)
- [Release procedure](docs/RELEASING.md)

依存、素材、フォント、SDK、データセットを追加する変更は、NOTICE、資産・データ台帳、プライバシーへの影響も同時に更新してください。

## License

ソースコードと通常ドキュメントは[Apache License 2.0](LICENSE)です。商用利用・販売・変更・再配布が可能です。ブランド名、ロゴ、App Icon、Store素材は同ライセンスの対象外です。詳細は[TRADEMARKS.md](TRADEMARKS.md)、[ASSET_LICENSES.md](ASSET_LICENSES.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)をご確認ください。

Apache-2.0 © 2026 hinoshiba.
