# 4つのサークル / Four circles

## 更新内容

iPhone / iPadのホーム画面ウィジェットに「4つのサークル」を追加しました。小・大サイズで4つの円を2×2に表示します。色のある円弧が残り割合を表し、中央には標準で残り割合を表示します。円の配置と描画はDaysYet独自の実装で、外部のコード・画像・フォントは追加していません。

標準の時間は左上から今週・今月・今年・1日の活動です。アプリ内の「ウィジェット」または「設定」→「4つのサークル」で4枠の時間、中央の値、専用テーマを設定できます。3行表示とは別に保存し、プレビューへすぐ反映します。値は残り割合・残り時間・終了日時から選べます。テーマは3行表示と同じ配色、または専用の配色を選べます。勤務のない日はOff、学習日を未選択の場合は日付を選ぶ案内を表示します。

1. ホーム画面を長押しし、編集 → ウィジェットを追加を選びます。
2. DaysYetを検索し、「4つのサークル」の小・大サイズを選んで追加します。
3. 追加したウィジェットを長押し → ウィジェットを編集から、左上・右上・左下・右下の時間、値、テーマを選びます。

新しく追加するサークルウィジェットは標準でアプリの専用設定を使います。以前に個別設定した項目をアプリに合わせる場合は、ホーム画面の「ウィジェットを編集」で各項目を「アプリの設定」に変更します。各ウィジェットで個別の時間・値・テーマを選ぶこともできます。以前のプロフィールは4枠の標準設定で読み込み、3行表示の設定は維持します。サークルの値を「アプリの設定」にしていた場合も、今後はサークル専用の値設定（初期値は残り割合）を参照します。

スタンバイでは小サイズのウィジェットを使用します。背景をiOSが取り除いた場合は文字とトラックをシステム色に切り替え、フルカラーが利用できるときはサークルの色を維持します。背景の半透明化、ロック画面の単色化、スタンバイの夜間の赤色表示はiOSが制御します。アプリからロック画面を任意のフルカラーにする設定はありません。[Appleの背景表示仕様](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background)、[表示コンテキストの仕様](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)。

既存の3行表示とロック画面ウィジェットも引き続き使用できます。iOS / iPadOS 17以降に対応し、保存済みプロフィールの移行は不要です。小サイズではラベルを1行に短縮し、大サイズでは最大2行に表示します。VoiceOverは各サークルの省略されていない名前、残り時間、残り割合、終了日時を読み上げます。更新時刻はiOSが調整します。既存の端末内データだけを使用し、外部送信や追加の権限はありません。

## Release notes

Added a Four circles Home Screen widget for iPhone and iPad, with Small and Large sizes showing a 2×2 grid. The colored arc represents the remaining percentage. The four independent timelines default to This week, This month, This year, and Daily activity. Edit Widget lets you select each position, choose percentage/time left/end date for the center value, and follow the app's theme or override it.

Touch and hold the Home Screen → Edit → Add Widget → search DaysYet → choose Four circles. After adding it, touch and hold the widget → Edit Widget to configure it. Existing three-row and Lock Screen widgets remain available. Requires iOS / iPadOS 17 or later; no profile migration is needed. Small labels use one line and Large labels use up to two lines. VoiceOver reads each full label and its time details. Days off display Off; an empty study plan asks you to select study days. Refresh timing is controlled by iOS. No new permission, external service, or third-party asset is used.

Open Four circles from the app’s Widget or Settings tab to edit all four timelines, the center value, and a dedicated theme with an immediate preview. These settings are saved separately from Three rows. New widgets follow them by default; previously customized fields can be changed to App setting through Edit Widget. Individual overrides remain available. Existing profiles receive the circle defaults without changing their three-row settings. A circle widget whose value already used App setting now follows the dedicated circle value setting, initially Remaining percentage.

Small widgets also support StandBy. When iOS removes the background, text and tracks use system colors while rings retain their theme when full-color rendering is available. iOS controls translucent backgrounds, monochrome Lock Screen rendering, and red StandBy Night Mode; the app cannot force arbitrary full color on the iPhone Lock Screen.
