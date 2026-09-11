# DaysYetの日英検索・SNS導線

調査・採用値の確認日: 2026-09-06

この文書は2026-09-06時点の調査・保存確認の記録。説明文・プロモーション文はその後のリリースで更新されている。以降の提出状況は[App Storeリリース記録](../README.md)を参照し、投稿前に公開バージョンと機能を再確認する。

日本語は「人生時計」「カウントダウン」、英語は「Life Countdown」「Time Countdown」を名称の入口とする。副題でウィジェットと用途を伝え、キーワード欄では残り日数、目標、進捗、勤務時間など実際の機能を補う。英語の `memento mori` は人生の時間を意識する文脈への入口として採用する。

この判断は、実際の製品掲載・開発元の一次資料とDaysYetの機能の一致に基づく。検索volume、Apple AdsのSearch Popularity、ハッシュタグ投稿量、直近のバズの規模は測定していない。「最も人気」「検索上位になる」「バズる」といった保証をするものではない。

## 採用メタデータ

名称・副題の正本は `AppStore/metadata/<locale>/`、キーワードの正本は各プラットフォームの `keywords.txt`。名称・副題は共通の製品情報として扱う。以下は末尾改行を除いて各ファイルから読み、文字数とUTF-8のbyte数を測定した値。

| 言語 | フィールド | 採用値 | 文字数 |
| --- | --- | --- | ---: |
| 日本語 | 名称 | `DaysYet - 人生時計とカウントダウン` | 22 |
| 日本語 | 副題 | `残り時間を見える化するウィジェット` | 17 |
| English (U.S.) | 名称 | `DaysYet: Life & Time Countdown` | 30 |
| English (U.S.) | 副題 | `Widgets for goals & milestones` | 30 |

| 言語・プラットフォーム | キーワード | UTF-8 bytes |
| --- | --- | ---: |
| 日本語・iOS / iPadOS | `残り日数,目標日,勤務時間,ロック画面,ホーム画面,時間管理,進捗率,記念日` | 100 |
| 日本語・macOS | `残り日数,目標日,勤務時間,時間管理,デスクトップ,進捗率,記念日,締め切り` | 100 |
| English (U.S.)・iOS / iPadOS | `memento mori,progress,clock,week,month,year,deadline,work,hours,remaining,left,lock,home,screen` | 95 |
| English (U.S.)・macOS | `memento mori,progress,clock,week,month,year,deadline,work,hours,remaining,left,desktop,display` | 94 |

英語では `clock` がLife Clock、`left` がTime Leftの検索意図を補う。`lock,home,screen` として `screen` の重複を避ける。MacにはHome Screen / Lock Screenを入れず、常駐パネルの用途を `desktop,display` で表す。Mac版はmacOSのウィジェットギャラリーから追加するWidgetKit拡張ではない。

Appleは名称・副題・キーワード・カテゴリとの関連性などを検索に使用し、重複語、競合製品名、無関係語、不要な記号を避けるよう案内している。SNS用の `#` はストアのキーワード欄には入れない。プロモーション文は機能の紹介とダウンロード判断を助ける欄で、検索順位には影響しない。[Apple: App Store search](https://developer.apple.com/app-store/search/)

キーワードの上限はAppleのフィールド仕様に合わせて100 bytesで検証する。日本語は文字数とbyte数が異なるため、追記や置換のたびにUTF-8で再測定する。[Apple: Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)

## 用語を選んだ理由

| 用語 | 判断 | 根拠・期待される意味 |
| --- | --- | --- |
| 人生時計 | 日本語名称に採用 | 生年月日や本人が決めた人生の目標をもとに、残り時間・経過を可視化する用例がある。DaysYetでは健康でいたい年齢を本人が設定し、残りと進捗を表示する。24時間の時計に換算する画面を備えるという説明はしない。 |
| カウントダウン・残り日数・時間管理 | 機能語として採用 | 年月週、目標日、勤務終了までの時間という利用目的を具体的に表せる。 |
| Life Countdown / Time Countdown | 英語名称に採用 | 英語App Storeで人生の時間・節目・ウィジェットの文脈に実例があり、日常の時間も含むDaysYetの用途を伝えられる。 |
| Memento Mori | 英語キーワード・内容に合う英語SNS投稿で採用 | 有限の時間を意識して日々を選ぶ文化的な文脈がある。名言配信・ストア派哲学の学習機能を提供するという意味では使用しない。 |
| メメントモリ | 日本語キーワード・日本語ハッシュタグでは不採用 | 日本では同名のRPGが存在し、ゲームを探す検索意図との衝突がある。一般概念を英語で使う判断と、日本語の検索語として採る判断を分ける。 |
| 人生トークン / Life’s tokens | 既存サイトのブランド上の比喩として維持 | 時間を何に使うかを伝える表現。日本語の「人生トークン」が広く検索されることを示す一次資料は未確認。英語のLife Tokenは暗号資産の名称とも衝突するため、ストアの主検索語や固定ハッシュタグにはしない。 |
| Life Calendar / Life in Weeks / 4,000 weeks | ストアの主メタデータには不採用 | 英語圏では人生を週のマス目で示す文脈があるが、DaysYetに週グリッド画面はない。紹介記事で考え方に触れる場合も、その機能を提供していると誤認させない。 |
| 寿命予測 / Death Clock / lifespan / longevity | 主メタデータには不採用 | 寿命推定・健康評価を求める意図が混ざる。DaysYetの健康年齢は本人が決める計画上の目標であり、寿命や健康状態を予測しない。 |
| Pomodoro / 勤怠管理 / ADHD | 採用しない | ポモドーロの作業・休憩セッション、出退勤記録、特定の症状への支援効果を提供・実証していない。 |

日本語の「人生時計」は、GMOの公式発表にも、設定した生年月日・寿命をもとに残り日数や経過率を表示する用例がある。これは用語の実在を示す資料で、検索量の証拠ではない。[GMO公式発表（2021-04-05）](https://www.gmo.jp/pdf/news/gmo_news_7165.pdf)。現在の製品掲載にも同語が使われている。[LifetimeClock — 人生時計](https://apps.apple.com/jp/app/id6789389747)、[人生時計 BucketPal](https://apps.apple.com/jp/app/id6752753272)

英語のLife CountdownとMemento Moriは現在の米国App Store掲載で併用されている。開発元がMemento Moriをウィジェットの設計思想として説明する例もある。[Life Countdown Ticker](https://apps.apple.com/us/app/life-countdown-ticker/id6755521611)、[Mementime公式](https://www.mementime.app/)。日本語ではゲーム名の衝突を考慮する。[メメントモリ公式](https://mememori-game.com/)

Life in Weeksの週グリッドと、限られた時間を受け入れて意味あることを選ぶ考え方には、英語圏の明確な参照先がある。既存作品のタイトル・著者名をDaysYetの検索キーワードには流用しない。[Tim Urban: Your Life in Weeks](https://waitbutwhy.com/2014/05/life-weeks.html)、[Oliver Burkeman: Four Thousand Weeks](https://www.oliverburkeman.com/fourthousandweeks)

Life Tokenが暗号資産の名称で使われる例と、Death Clockが寿命推定・健康サービスを提供する例も確認した。[LIFE Protocol公式](https://blog.lifeprotocol.io/life-token-details/)、[Death Clock公式](https://www.deathclock.ai/)。既存サイトの比喩は維持し、ストアでは実際の機能を分かる言葉で説明する。[DaysYet日本語サイト](https://daysyet.hinoshiba.com/)、[DaysYet English](https://daysyet.hinoshiba.com/en/)

## SNSからダウンロードまで

Xは `#DaysYet` を共通のブランドタグとし、その投稿の内容を表すタグを1個加える。X公式も1投稿2個以下を推奨している。無関係な流行タグは使わない。[X: How to use hashtags](https://help.x.com/en/using-x/how-to-use-hashtags)

プロフィールのリンクは、日本語アカウント・日本語中心のプロフィールなら [日本語サイト](https://daysyet.hinoshiba.com/)、英語中心なら [Englishサイト](https://daysyet.hinoshiba.com/en/) を指定する。両言語を扱う場合は、プロフィールに日英のリンクを併記するか、サイトの言語切り替えで移動できるよう案内する。プロフィール案は「人生時計とカウントダウン。残り時間を見える化するDaysYet。」／「Life countdowns and everyday time progress. Make time visible with DaysYet.」。

機能を見せる投稿にはその言語・端末の実画面を添え、投稿内は下記のキャンペーンリンクでApp Storeへ直接案内する。リンクは名称変更の影響を受けないアプリIDを使う。App Storeは利用者の地域に応じたストアへ案内する。[Apple: Campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)

| 内容 | 日本語タグ | 英語タグ | 画像・説明の焦点 |
| --- | --- | --- | --- |
| 人生の時間・目標 | `#DaysYet #人生時計` | `#DaysYet #MementoMori` | 本人が設定した目標と残り時間。寿命予測と表現しない。 |
| ホーム画面の使い方 | `#DaysYet #ウィジェット` | `#DaysYet #iOSWidgets` | 1個のホーム画面ウィジェットに3本表示できる実画面。 |
| 勤務終了までの時間 | `#DaysYet #時間管理` | `#DaysYet #TimeManagement` | 勤務時間の設定と残り時間。出退勤記録とは説明しない。 |
| Macの常駐表示 | `#DaysYet #Macアプリ` | `#DaysYet #MacApps` | 画面端のパネル、展開した詳細。WidgetKitの追加手順は案内しない。 |

2026-09-06にApp Store Connectのキャンペーン作成画面から以下の8リンクを生成し、それぞれの `ct` が指定したキャンペーン名と一致することを確認した。これらは公開用の配布リンクであり、投稿やダウンロードの発生を意味しない。

| 内容 | 日本語の投稿リンク | 英語の投稿リンク |
| --- | --- | --- |
| 人生の時間・目標 | [ja_x_lifeclock](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_lifeclock&mt=8) | [en_x_mementomori](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_mementomori&mt=8) |
| ホーム画面の使い方 | [ja_x_widgets](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_widgets&mt=8) | [en_x_widgets](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_widgets&mt=8) |
| 勤務終了までの時間（iOS 0.1.3公開後） | [ja_x_workday](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_workday&mt=8) | [en_x_workday](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_workday&mt=8) |
| Macの常駐表示（Mac版公開後） | [ja_x_mac](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_mac&mt=8) | [en_x_mac](https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_mac&mt=8) |

英語の `#IntentionalLiving` は、日々何を大切にするかに焦点を置いた投稿で `#MementoMori` と入れ替える候補。日本語の `#人生トークン`、英語の `#LifeTokens` は、既存の検索需要を取り込める根拠がないため標準セットには含めない。タグの数を増やすより、投稿ごとに用途と画像を一致させる。

## 投稿案と公開条件

以下は2026-09-06時点の機能に合わせた投稿用の下書きであり、投稿・プロフィール変更を実施した記録ではない。掲載時にはApp Storeの公開バージョン、機能、リンク先を再確認する。

2026-09-06の作業前のリリース記録では、公開済みiOSは0.1.2 (4)、勤務時間を含むiOS 0.1.3 (5)と初回macOS 0.1.2 (3)は審査待ち。勤務時間の投稿はiOS 0.1.3の公開後、Macの投稿はMac版が実際にダウンロード可能になってから使う。審査で承認されたことと、ストアで公開されたことは分けて確認する。[リリース記録](../README.md)

### 人生の時間・目標

```text
人生の時間を、今日の選択へ。DaysYetで、自分で決めた健康年齢の目標や大切な日までの残り時間を見える化。寿命の予測ではなく、目標を見渡すための人生時計です。
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_lifeclock&mt=8
#DaysYet #人生時計
```

```text
Make time visible. DaysYet keeps three countdowns on your Home Screen—from this week to a personal age goal you choose. A quiet reminder to make room for what matters.
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_mementomori&mt=8
#DaysYet #MementoMori
```

### ホーム画面の使い方

```text
今週、今年、大切な日まで。DaysYetなら、3つの残り時間と進み具合をホーム画面にひとまとめ。ウィジェットごとに、表示する時間やテーマを選べます。
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_widgets&mt=8
#DaysYet #ウィジェット
```

```text
Your week. Your year. Your next milestone. See time left and progress together in one Home Screen widget. Choose the three timelines that matter to you.
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_widgets&mt=8
#DaysYet #iOSWidgets
```

### 勤務終了までの時間（iOS 0.1.3公開後）

```text
仕事が終わるまで、あとどれくらい？ DaysYetに勤務の開始・終了時刻を設定して、残り時間をウィジェットに。夜勤など日をまたぐ時間にも対応しています。
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_workday&mt=8
#DaysYet #時間管理
```

```text
Keep the end of your workday in view. Set your work hours in DaysYet and see the time left in a widget. Overnight shifts work too.
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_workday&mt=8
#DaysYet #TimeManagement
```

### Macの常駐表示（Mac版公開後）

```text
今週、今月、今年の進み具合を、Macの画面端に。DaysYetは3つの時間を小さく表示し、ポインタを合わせると詳細が開きます。左右と上端から置き場所を選べます。
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=ja_x_mac&mt=8
#DaysYet #Macアプリ
```

```text
Keep your week, month, and year in view at the edge of your Mac display. DaysYet shows three timelines and opens the details when you hover. Choose the left, right, or top edge.
https://apps.apple.com/app/apple-store/id6802000765?pt=129139420&ct=en_x_mac&mt=8
#DaysYet #MacApps
```

## 計測と見直し

投稿の実施時に、日付、言語、テーマ、タグ2個、画像、リンク、対象バージョンを記録する。通常のApp Store検索による発見とSNS流入を分け、ストアの商品ページ閲覧数・初回ダウンロード数・取得可能なコンバージョン指標を同じ期間で比較する。投稿文と画像も同時に変わるため、結果をハッシュタグ単独の効果とは断定しない。

上記の8リンクはApp Store Connectが生成した `pt` と `ct` を保持している。`pt` はApple提供の公開用provider tokenで、認証用の秘密情報ではない。投稿テーマとリンクを対応させ、キャンペーン名が意図せず変わらないようにする。2026-09-06の確認時点ではキャンペーンレポートに十分な集計データはなく、投稿もまだ実施していない。

Appleのキャンペーン集計には最低件数の条件があり、少数の導入では数値が表示されない。表示されない結果をゼロ件や失敗と同一視しない。反応が蓄積したら、機能と検索意図が合う候補の範囲内で語句・説明・画像を見直す。[Apple: Campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)

## AppleのApp Tagsとの区別

AppleのApp Tagsは、メタデータ等からAppleが生成・審査するアプリの特徴を示すタグで、開発者がSNSのように任意のハッシュタグを入力する欄ではない。表示されるタグを管理できる場合の手順はAppleの案内に従う。[Apple: Manage app tags](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-tags)

2026-09-06に確認したDaysYetのApp Store Connect「アプリ情報」画面には、App Tagsのセクションは表示されていない。このSNS案をApp Tagsに登録したとは扱わない。

## 反映記録

2026-09-06 19:17 JSTまでに、App Store Connectへ日英の名称・副題4項目と、iOS / macOSそれぞれの日英の説明文・プロモーション文・キーワード12項目を保存した。ページから離れた後に再読み込みし、合計16項目すべてが当時のローカルの正本と一致することを確認した。

この保存確認時点では、iOS 0.1.3 (5)とmacOS 0.1.2 (3)はいずれも「審査待ち」だった。この記録はApp Store Connectでの保存確認であり、その時点でのAppleによる承認、ストアでの公開、検索結果への反映を確認したものではない。この作業ではSNS投稿・プロフィール変更は実施していない。後日の2026-09-08には両バージョンの「配信準備完了」が記録されている。[0.1.4リリース記録](../releases/0.1.4.md)

ローカルでは `./Scripts/check-compliance.sh` が成功し、Macメタデータの各制限も個別に実測した。投稿案8件はタグ2個で、URLをXの短縮リンク相当の23文字として数えた本文の長さが280文字の枠内に収まることを確認した。
