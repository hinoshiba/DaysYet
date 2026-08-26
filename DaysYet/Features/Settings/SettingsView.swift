import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ProfileEditorView()
                } label: {
                    Label(L10n.text("人生の基準", "Life reference points"), systemImage: "calendar.badge.clock")
                }
            } header: {
                Text(L10n.text("表示", "Display"))
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("この端末だけ", "On device only"))
                            .font(.body.weight(.semibold))
                        Text(L10n.text("入力した日付を送信せず、分析SDKや広告も使いません。", "Entered dates are never sent; no analytics SDKs or ads."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.green)
                }

                NavigationLink(L10n.text("プライバシーについて", "Privacy")) {
                    PrivacyView()
                }

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label(L10n.text("すべてのデータを消去", "Delete all data"), systemImage: "trash")
                }
            } header: {
                Text(L10n.text("プライバシー", "Privacy"))
            }

            Section {
                Link(destination: ProjectLinks.sourceCode) {
                    LabeledContent {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(L10n.text("ソースコード", "Source code"), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                NavigationLink(L10n.text("ライセンス", "License")) {
                    LicenseView()
                }

                LabeledContent(L10n.text("バージョン", "Version"), value: appVersion)
            } header: {
                Text(L10n.text("このアプリについて", "About"))
            } footer: {
                Text(L10n.text("時間を、積み重ねる。今日を選ぶ。", "Every day adds up. Choose today."))
            }
        }
        .navigationTitle(L10n.text("設定", "Settings"))
        .confirmationDialog(
            L10n.text("端末内の設定をすべて消去しますか？", "Delete all on-device settings?"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("消去", "Delete"), role: .destructive) { store.reset() }
            Button(L10n.text("キャンセル", "Cancel"), role: .cancel) {}
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text(L10n.text(
                    "本アプリは、生年月日・目標年齢・大切な日の起算日と目標日時・表示設定を、アプリとウィジェットの共有領域に保存します。データを外部へ送信せず、追跡・分析・広告を行いません。設定画面からいつでも全データを消去できます。",
                    "This app stores your birth date, target age, milestone start and target dates, and display choices in the private area shared by the app and its widget. It sends nothing off device and performs no tracking, analytics, or advertising. You can delete all data from Settings at any time."
                ))
            }

            Section {
                Text(L10n.text(
                    "「健康でいたい年齢」は、ご自身で入力する計画上の目標です。医療行為、診断、健康状態や寿命の予測ではありません。",
                    "The healthy-age goal is a personal planning marker you enter. It is not medical advice, diagnosis, or a prediction of health or lifespan."
                ))
            } header: {
                Text(L10n.text("健康に関する免責", "Health disclaimer"))
            }

            Link(L10n.text("公開プライバシーポリシー", "Public privacy policy"), destination: ProjectLinks.privacyPolicy)
            Link(L10n.text("サポート", "Support"), destination: ProjectLinks.support)
        }
        .navigationTitle(L10n.text("プライバシー", "Privacy"))
    }
}

private enum ProjectLinks {
    static let sourceCode = URL(string: "https://github.com/hinoshiba/DaysYet")!
    static let privacyPolicy = localizedPageURL(fragment: "privacy")
    static let support = localizedPageURL(fragment: "support")

    private static func localizedPageURL(fragment: String) -> URL {
        let languagePath = L10n.isJapanese ? "" : "en/"
        return URL(string: "https://daysyet.hinoshiba.com/\(languagePath)#\(fragment)")!
    }
}

private struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Apache License 2.0")
                    .font(.title2.bold())
                Text(L10n.text(
                    "本プロジェクトのソースコードはApache License 2.0で公開されています。商用利用、変更、再配布が可能です。著作権表示、ライセンス文、変更の明示など、ライセンスの条件を守る必要があります。",
                    "This project’s source code is available under the Apache License 2.0. Commercial use, modification, and redistribution are permitted subject to its notice, license, and change-disclosure conditions."
                ))
                Text(L10n.text(
                    "配布バイナリに第三者のランタイムライブラリ、フォント、画像素材は含まれません。UIはAppleのシステムフレームワーク、システムフォント、SF SymbolsをAppleプラットフォーム上で使用します。アプリアイコンは本プロジェクトのオリジナル素材です。",
                    "The distributed binary contains no third-party runtime libraries, fonts, or stock imagery. The UI uses Apple system frameworks, fonts, and SF Symbols on Apple platforms. The app icon is original project artwork."
                ))
                    .foregroundStyle(.secondary)

                Divider()

                documentLink(L10n.text("Apache License 2.0 全文", "Full Apache License 2.0"), resource: "LICENSE", fileExtension: nil)
                documentLink(L10n.text("NOTICE", "NOTICE"), resource: "NOTICE", fileExtension: nil)
                documentLink(L10n.text("第三者ライセンス台帳", "Third-party notices"), resource: "THIRD_PARTY_NOTICES", fileExtension: "md")
                documentLink(L10n.text("素材の権利台帳", "Asset license register"), resource: "ASSET_LICENSES", fileExtension: "md")
                documentLink(L10n.text("データ出典台帳", "Data source register"), resource: "DATA_SOURCES", fileExtension: "md")
            }
            .padding(20)
        }
        .navigationTitle(L10n.text("ライセンス", "License"))
    }

    private func documentLink(_ title: String, resource: String, fileExtension: String?) -> some View {
        NavigationLink {
            BundledTextView(title: title, resource: resource, fileExtension: fileExtension)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct BundledTextView: View {
    let title: String
    let resource: String
    let fileExtension: String?

    var body: some View {
        ScrollView {
            Text(contents)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var contents: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("文書を読み込めませんでした。", "The document could not be loaded.")
        }
        return text
    }
}
