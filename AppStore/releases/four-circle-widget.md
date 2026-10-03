# 4つのサークル / Four circles

## 更新内容

iPhone / iPadのホーム画面ウィジェットに「4つのサークル」を追加しました。小・大サイズで4つの円を2×2に表示します。色のある円弧が残り割合を表し、中央には標準で残り割合を表示します。円の配置と描画はDaysYet独自の実装で、外部のコード・画像・フォントは追加していません。

標準の時間は左上から今週・今月・今年・1日の活動です。4つの時間はウィジェットごとに選択でき、アプリの3つの時間とは別に保持します。値は残り割合・残り時間・終了日時から選べます。テーマは標準でアプリに合わせるほか、ウィジェットごとに変更できます。勤務のない日はOff、学習日を未選択の場合は日付を選ぶ案内を表示します。

1. ホーム画面を長押しし、編集 → ウィジェットを追加を選びます。
2. DaysYetを検索し、「4つのサークル」の小・大サイズを選んで追加します。
3. 追加したウィジェットを長押し → ウィジェットを編集から、左上・右上・左下・右下の時間、値、テーマを選びます。

既存の3行表示とロック画面ウィジェットも引き続き使用できます。iOS / iPadOS 17以降に対応し、保存済みプロフィールの移行は不要です。小サイズではラベルを1行に短縮し、大サイズでは最大2行に表示します。VoiceOverは各サークルの省略されていない名前、残り時間、残り割合、終了日時を読み上げます。更新時刻はiOSが調整します。既存の端末内データだけを使用し、外部送信や追加の権限はありません。

## Release notes

Added a Four circles Home Screen widget for iPhone and iPad, with Small and Large sizes showing a 2×2 grid. The colored arc represents the remaining percentage. The four independent timelines default to This week, This month, This year, and Daily activity. Edit Widget lets you select each position, choose percentage/time left/end date for the center value, and follow the app's theme or override it.

Touch and hold the Home Screen → Edit → Add Widget → search DaysYet → choose Four circles. After adding it, touch and hold the widget → Edit Widget to configure it. Existing three-row and Lock Screen widgets remain available. Requires iOS / iPadOS 17 or later; no profile migration is needed. Small labels use one line and Large labels use up to two lines. VoiceOver reads each full label and its time details. Days off display Off; an empty study plan asks you to select study days. Refresh timing is controlled by iOS. No new permission, external service, or third-party asset is used.
