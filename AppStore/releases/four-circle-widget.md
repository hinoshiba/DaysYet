# 4つのサークル / Four circles

## 更新内容

iPhone / iPadのホーム画面ウィジェットに「4つのサークル」を追加しました。小・大サイズで4つの円を2×2に表示します。色のある円弧が残り割合を表し、中央には標準で残り割合を表示します。時間の名前は円の内側に、値より小さく、その上に配置します。名前と値はそれぞれ幅・高さを固定した領域に収め、長い名前は縮小と末尾の省略で円からはみ出さないようにし、VoiceOverでは全文を読み上げます。円の配置と描画はDaysYet独自の実装で、外部のコード・画像・フォントは追加していません。

「ウィジェット」タブの「編集するウィジェット」で「3つの行」「4つのサークル」を切り替えます。どちらも同じ位置にプレビューを表示し、「表示する時間」で各位置の時間を選び、「表示」で表示方法・値を編集し、「カラー」から配色を調整する順に統一しました。「設定」には「ウィジェットの設定」ボタンを1つ置き、このタブへ移動します。重複する案内を整理し、追加・反映の手順は共通のツールバー項目「追加・反映方法」にまとめました。

サークルの標準の時間は左上から今週・今月・今年・1日の活動です。4枠の時間、中央の値、専用テーマは3行表示とは別に保存し、プレビューへすぐ反映します。値は残り割合・残り時間・終了日時から選べます。テーマは3行表示と同じ配色、または専用の配色を選べます。勤務のない日はOff、学習日を未選択の場合は日付を選ぶ案内を表示します。

「カラー」には現在のプレビュー、4つの配色テンプレート、表示する時間ごとの色選択をまとめています。iOS標準のカラーピッカーで好きな不透明色を選び、変更済みの色を個別またはまとめて戻せます。テンプレートを選ぶと、その表示形式の個別色を非表示の時間も含めて解除します。3行とサークルの個別色は別に保存し、サークルが3行の配色を引き継ぐ場合も、その一部だけを独自の色に変更できます。同じ時間を複数のサークルに選ぶと同じ色になり、色選択は1項目にまとめます。

1. ホーム画面を長押しし、編集 → ウィジェットを追加を選びます。
2. DaysYetを検索し、「4つのサークル」の小・大サイズを選んで追加します。
3. 追加したウィジェットを長押し → ウィジェットを編集から、左上・右上・左下・右下の時間、値、テーマを選びます。

新しく追加するサークルウィジェットは標準でアプリの専用設定を使います。以前に個別設定した項目をアプリに合わせる場合は、ホーム画面の「ウィジェットを編集」で各項目を「アプリの設定」に変更します。各ウィジェットで個別の時間・値・テーマを選ぶこともできます。以前のプロフィールは4枠の標準設定で読み込み、3行表示の設定は維持します。サークルの値を「アプリの設定」にしていた場合も、今後はサークル専用の値設定（初期値は残り割合）を参照します。

テーマが「アプリの設定」のウィジェットにはアプリ内の個別色も反映します。ウィジェットで特定のテーマを指定した場合は、アプリの個別色を適用せず、そのテンプレートを使用します。

スタンバイでは小サイズのウィジェットを使用します。背景をiOSが取り除いた場合は文字とトラックをシステム色に切り替え、フルカラーが利用できるときはサークルの色を維持します。背景の半透明化、ロック画面の単色化、スタンバイの夜間の赤色表示はiOSが制御します。アプリからロック画面を任意のフルカラーにする設定はありません。[Appleの背景表示仕様](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background)、[表示コンテキストの仕様](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)。

既存の3行表示とロック画面ウィジェットも引き続き使用できます。iOS / iPadOS 17以降に対応し、保存済みプロフィールの移行は不要です。小サイズではラベルを1行に短縮し、大サイズでは最大2行に表示します。VoiceOverは各サークルの省略されていない名前、残り時間、残り割合、終了日時を読み上げます。更新時刻はiOSが調整します。既存の端末内データだけを使用し、外部送信や追加の権限はありません。

## Release notes

Added a Four circles Home Screen widget for iPhone and iPad, with Small and Large sizes showing a 2×2 grid. The colored arc represents the remaining percentage. Each timeline name sits inside its ring, in smaller text above the value. Names and values occupy separate fixed-width, fixed-height areas; long names shrink and truncate at the end to stay within the ring, while VoiceOver reads the full text. The four independent timelines default to This week, This month, This year, and Daily activity. Edit Widget lets you select each position, choose percentage/time left/end date for the center value, and follow the app's theme or override it.

Touch and hold the Home Screen → Edit → Add Widget → search DaysYet → choose Four circles. After adding it, touch and hold the widget → Edit Widget to configure it. Existing three-row and Lock Screen widgets remain available. Requires iOS / iPadOS 17 or later; no profile migration is needed. Small labels use one line and Large labels use up to two lines. VoiceOver reads each full label and its time details. Days off display Off; an empty study plan asks you to select study days. Refresh timing is controlled by iOS. No new permission, external service, or third-party asset is used.

In the Widget tab, switch between Three rows and Four circles. Both editors use the same layout: preview, timeline pickers for each position, then display mode, value, and one Colors entry. The Widget settings button in Settings opens this tab. Repeated instructions have been removed; shared help for adding widgets and applying changes is available in the toolbar.

Colors brings together the current preview, four palette templates, and native iOS color pickers for visible timelines. Choose arbitrary opaque colors and reset customized entries individually or together. Selecting a template clears that design's custom colors, including hidden timelines. Row and circle colors are stored separately; circles can follow row colors and override individual ones. Repeated selections of the same timeline share a color and one color control.

The four circle timelines, center value, and dedicated theme are saved separately from Three rows and update the preview immediately. New widgets follow them by default; previously customized fields can be changed to App setting through Edit Widget. Individual overrides remain available. Existing profiles receive the circle defaults without changing their three-row settings. A circle widget whose value already used App setting now follows the dedicated circle value setting, initially Remaining percentage.

A widget using App setting for Theme includes the app's custom colors. An explicit widget theme uses its unmodified template without the app's custom colors.

Small widgets also support StandBy. When iOS removes the background, text and tracks use system colors while rings retain their theme when full-color rendering is available. iOS controls translucent backgrounds, monochrome Lock Screen rendering, and red StandBy Night Mode; the app cannot force arbitrary full color on the iPhone Lock Screen.
