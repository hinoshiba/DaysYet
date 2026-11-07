import SwiftUI

/// Both main tabs present the same guide from their info button.
struct UsageGuideButton: View {
    let accessibilityIdentifier: String
    @State private var showsGuide = false

    var body: some View {
        Button {
            showsGuide = true
        } label: {
            Label(L10n.text("使い方", "How to use"), systemImage: "info.circle")
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .sheet(isPresented: $showsGuide) {
            UsageGuideView()
        }
    }
}

private struct UsageGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text(
                        "一覧の項目をタップして、時刻・曜日・日付を編集します。「保存」で反映し、「キャンセル」で破棄します。",
                        "Tap a timeline to edit its schedule, weekdays, or dates. Save applies your changes; Cancel discards them."
                    ))
                    Text(L10n.text(
                        "「今週」では週の始まりを選べます。項目の色は長押しから変更します。",
                        "Choose the first day of the week in This week. Touch and hold a timeline to change its color."
                    ))
                } header: {
                    Text(L10n.text("時間を編集", "Edit your times"))
                }
                .listRowBackground(DaysYetTheme.panel)

                Section {
                    Text(L10n.text(
                        "表示形式を選び、見本をタップしてテーマを選びます。項目をタップすると「時間」の一覧から差し替えられます。",
                        "Choose a layout, then tap a preview to select a theme. Tap an item to replace it with one from Times."
                    ))
                    Text(L10n.text(
                        "サークルは＋で追加し、「編集」で並べ替え・削除できます。選択・配置・表示の変更は自動で保存されます。",
                        "Use + to add circles and Edit to reorder or remove them. Choices, order, and appearance save automatically."
                    ))
                } header: {
                    Text(L10n.text("ウィジェットを整える", "Arrange your widget"))
                }
                .listRowBackground(DaysYetTheme.panel)

                Section {
                    Label(L10n.text("ホーム画面を長押し", "Touch and hold the Home Screen"), systemImage: "1.circle")
                    Label(L10n.text("編集 → ウィジェットを追加", "Choose Edit → Add Widget"), systemImage: "2.circle")
                    Label(L10n.text("DaysYetを検索してサイズを選ぶ", "Search for DaysYet and choose a size"), systemImage: "3.circle")
                    Text(L10n.text("「DaysYet」の小・中・大サイズを選びます。サークルは小サイズで先頭4つ、中・大サイズで最大8つを表示します。", "Choose DaysYet in Small, Medium, or Large. Circles show the first four in Small, or up to eight in Medium and Large."))
                } header: {
                    Text(L10n.text("ホーム画面に追加", "Add to the Home Screen"))
                } footer: {
                    Text(L10n.text(
                        "アプリで選んだ表示形式とテーマが、ホーム画面にも反映されます。プレビューのサイズは見本だけを変更します。",
                        "The layout and theme you choose in the app also apply to the Home Screen. Preview size only changes the preview."
                    ))
                }
                .listRowBackground(DaysYetTheme.panel)

                Section {
                    Label(L10n.text("ウィジェットを長押し → ウィジェットを編集", "Touch and hold the widget → Edit Widget"), systemImage: "hand.tap")
                    Text(L10n.text("通常は追加するだけで反映されます。個別設定を変更している場合は「アプリの表示に合わせる」をオンにし、表示モード・値・テーマを「アプリの設定」に戻します。", "New widgets follow the app automatically. If you changed individual settings, turn on Follow app appearance and set display mode, value, and theme to App setting."))
                    Text(L10n.text("以前の「サークル」は「サークル（固定）」として残ります。表示形式も連動させるには「DaysYet」を追加してください。", "The original Circles widget remains as Circles (fixed). Add DaysYet to follow the app's layout as well."))
                } header: {
                    Text(L10n.text("追加済みウィジェットに反映", "Apply to existing widgets"))
                } footer: {
                    Text(L10n.text("ウィジェットの選択・配置・表示は自動で保存されます。時刻・日付は「時間」タブで編集します。ウィジェットの更新時刻はiOSが調整します。", "Widget choices, order, and appearance save automatically. Edit schedules and dates in Times. Widget refresh timing is controlled by iOS."))
                }
                .listRowBackground(DaysYetTheme.panel)

                Section {
                    Text(L10n.text("横向きで充電中のスタンバイには、小サイズを追加できます。ウィジェットを長押しして編集します。", "In StandBy while charging in landscape, add a Small widget. Touch and hold it to edit."))
                } header: {
                    Text(L10n.text("スタンバイ", "StandBy"))
                }
                .listRowBackground(DaysYetTheme.panel)

                Section {
                    Label(L10n.text("ロック画面を長押し → カスタマイズ", "Touch and hold the Lock Screen → Customize"), systemImage: "1.circle")
                    Label(L10n.text("ウィジェット欄からDaysYetを追加", "Add DaysYet from the widget area"), systemImage: "2.circle")
                    Label(L10n.text("形と表示する1つの時間を選ぶ", "Choose a shape and one timeline"), systemImage: "3.circle")
                } header: {
                    Text(L10n.text("ロック画面", "Lock Screen"))
                } footer: {
                    Text(L10n.text("背景の半透明化、ロック画面の単色表示、スタンバイの夜間の色はiOSが調整します。", "iOS controls translucent backgrounds, monochrome Lock Screen widgets, and StandBy's nighttime colors."))
                }
                .listRowBackground(DaysYetTheme.panel)

            }
            .daysYetBackground()
            .navigationTitle(L10n.text("使い方", "How to use"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完了", "Done")) { dismiss() }
                        .accessibilityIdentifier("app.guide.done")
                }
            }
        }
    }
}
