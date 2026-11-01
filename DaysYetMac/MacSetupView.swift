import SwiftUI

struct MacSetupView: View {
    @ObservedObject var setup: MacSetupController
    @ObservedObject var loginItem: MacLoginItemSettings
    // Also allows both translations to be reviewed without changing macOS language.
    var isJapanese = L10n.isJapanese

    private let accent = Color(red: 0.77, green: 0.35, blue: 0.16)
    private func text(_ ja: String, _ en: String) -> String { isJapanese ? ja : en }
    private var isStartup: Bool { setup.step == .startup }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(accent).accessibilityHidden(true)
                    Text("DaysYet").fontWeight(.semibold)
                    Text(text("はじめの設定", "Get started")).foregroundStyle(.secondary)
                }
                Spacer()
                Text(isStartup ? "1 / 2" : "2 / 2")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .font(.callout)

            HStack(spacing: 8) {
                stepLabel(number: "1", title: text("自動起動", "Launch at login"), active: isStartup)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                stepLabel(number: "2", title: setup.offersDirectDockDrag
                          ? text("Dockからドラッグ", "Drag from the Dock")
                          : text("自由に配置", "Make it your own"), active: !isStartup)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(isStartup ? text("ログインしたら、いつもの場所に。", "Ready when you log in.")
                     : setup.offersDirectDockDrag
                        ? text("Dockから、好きな場所へ。", "From the Dock to your favorite spot.")
                        : text("つかんで、好きな場所へ。", "Grab it. Make yourself at home."))
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.5)
                    .accessibilityAddTraits(.isHeader)
                Text(isStartup
                     ? text("Macを開いたら、残り時間がそっと目に入る。自動起動は、あとから変更できます。",
                            "Keep your time in sight whenever you open your Mac. You can change this anytime.")
                     : setup.offersDirectDockDrag
                        ? text("Dockの丸をそのままつかんで移動。画面の端に近づけると、吸い付くように広がります。",
                               "Grab a circle right in the Dock. Bring it near a screen edge and watch the group snap into place.")
                        : text("丸をつかむと、小さな1つの丸に。上下左右の端へ運んで、自分の定位置を見つけましょう。",
                               "Grab a circle to gather the group into one. Move it to any screen edge to find your favorite spot."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isStartup {
                startupContent
            } else {
                movementContent
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(width: 740, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .onAppear { setup.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            setup.refresh()
        }
    }

    private func stepLabel(number: String, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(number).font(.caption2.weight(.semibold))
                .frame(width: 19, height: 19)
                .background(active ? accent.opacity(0.15) : Color.secondary.opacity(0.08), in: Circle())
            Text(title).font(.caption.weight(active ? .semibold : .regular))
        }
        .foregroundStyle(active ? accent : .secondary)
    }

    private var startupContent: some View {
        VStack(spacing: 18) {
            MacSetupDesktopIllustration(stage: .startup)
                .frame(height: 180)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text("ログイン時にDaysYetを起動", "Launch DaysYet at login")).fontWeight(.medium)
                        Text(text("再起動したあとも、ウィジェットがいつもの場所に。",
                                  "Your widget returns to its place after a restart."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(text("ログイン時にDaysYetを起動", "Launch DaysYet at login"))
                if loginItem.requiresApproval {
                    Text(text("ログイン項目でDaysYetを有効にすると、自動起動できます。",
                              "Enable DaysYet in Login Items to finish setting this up."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(text("ログイン項目の設定を開く…", "Open Login Items Settings…")) {
                        loginItem.openSystemSettings()
                    }
                }
                if loginItem.status == .notFound {
                    Text(text("自動起動を登録できない場合は、アプリケーションフォルダからDaysYetを開き直してください。あとで設定することもできます。",
                              "If launch at login is unavailable, reopen DaysYet from Applications. You can also set it up later."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button(text("ログイン項目の設定を開く…", "Open Login Items Settings…")) {
                        loginItem.openSystemSettings()
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var movementContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                tutorialStep(stage: setup.offersDirectDockDrag ? .dock : .edge,
                             title: text("1  丸をつかむ", "1  Grab a circle"))
                tutorialStep(stage: .moving, title: text("2  ひとつになって移動", "2  Move as one"))
                tutorialStep(stage: .attached, title: text("3  端で吸着して広がる", "3  Snap to an edge"))
            }
            if setup.offersDirectDockDrag {
                Text(text("画面端の丸も同じように移動できます。Dockのある辺に置くと、Dockに入ります。",
                          "Circles at the screen edge move the same way. Drop them on the Dock’s edge to join the Dock."))
                    .font(.caption).foregroundStyle(.secondary)
                accessibilityCard
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label(text("離した場所が、新しい定位置に。", "Release to save your new spot."), systemImage: "cursorarrow.motionlines")
                        .font(.callout.weight(.medium))
                    Text(text("画面の中央で離すか、Escキーを押すと元の位置に戻ります。Dockから動かす時は、丸をクリックしてグループを開き、つかんで移動できます。",
                              "Release in the center or press Esc to return. To move out of the Dock, click a circle to open the group, then drag it to an edge."))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(text("設定はウィジェットをダブルクリック。いつでも配置や見た目を変えられます。",
                              "Double-click the widget to open settings and adjust its position or appearance."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func tutorialStep(stage: MacSetupDesktopIllustration.Stage, title: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            MacSetupDesktopIllustration(stage: stage)
                .frame(height: 120)
                .accessibilityHidden(true)
            Text(title).font(.caption.weight(.medium)).padding(.leading, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: setup.accessibilityGranted ? "checkmark.circle.fill" : "hand.point.up.left")
                    .font(.title3).foregroundStyle(setup.accessibilityGranted ? Color.green : accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(setup.accessibilityGranted
                         ? text("アクセシビリティは許可済みです", "Accessibility is enabled")
                         : text("直接ドラッグを使うための、ひとつの設定。", "One setting to drag directly."))
                        .font(.callout.weight(.semibold))
                    Text(text("Dock内のDaysYetの丸の位置を読み取るために、アクセシビリティの許可を使います。",
                              "DaysYet uses Accessibility permission to locate its circles in the Dock."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if setup.accessibilityGranted {
                Text(text("「直接ドラッグを使う」で有効になります。Dock側の端へ戻すと、再びDockの中に。Optionキーを押しながら操作すると、Dock本来の並べ替えも使えます。",
                          "Choose “Enable direct dragging” to turn it on. Return to the Dock’s edge to rejoin it. Hold Option to use the Dock’s own rearrangement."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    instruction("1", text("システム設定 → プライバシーとセキュリティ → アクセシビリティ",
                                           "System Settings → Privacy & Security → Accessibility"))
                    instruction("2", text("DaysYetをオンにして、この画面へ戻る",
                                           "Turn on DaysYet, then return here"))
                }
                if setup.hasOpenedAccessibilitySettings {
                    Text(text("まだ許可を確認できていません。DaysYetが一覧にない場合は「＋」から追加できます。オンのまま認識されない場合は、オフにしてから再度オンにしてください。",
                              "Permission hasn’t been detected yet. If DaysYet is missing, add it with +. If it is already on, switch it off and on again."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(text("許可はあとでも大丈夫。Dockの丸をクリックして開く操作は、そのまま使えます。",
                              "You can do this later. Clicking a Dock circle to open the group still works."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func instruction(_ number: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(number).font(.caption.weight(.semibold)).foregroundStyle(accent)
            Text(title).font(.callout)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Divider()
            HStack(spacing: 12) {
                if !isStartup {
                    Button(text("戻る", "Back")) { setup.go(to: .startup) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                if isStartup {
                    Button(text("次へ", "Continue")) { setup.go(to: .movement) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else if setup.offersDirectDockDrag {
                    Button(text("あとで設定", "Set up later")) { setup.finish() }
                        .buttonStyle(.bordered)
                    Button(setup.accessibilityGranted
                           ? text("直接ドラッグを使う", "Enable direct dragging")
                           : text("システム設定を開く", "Open System Settings")) {
                        if setup.accessibilityGranted { setup.finishEnablingDockDrag() }
                        else { setup.openAccessibilitySettings() }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(text("使いはじめる", "Get started")) { setup.finish() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
    }
}

/// Small, illustrative desktops. The three still frames also work with Reduce Motion.
private struct MacSetupDesktopIllustration: View {
    enum Stage { case startup, dock, edge, moving, attached }
    var stage: Stage
    private let colors: [Color] = [Color(red: 0.91, green: 0.63, blue: 0.39),
                                  Color(red: 0.63, green: 0.77, blue: 0.65),
                                  Color(red: 0.89, green: 0.79, blue: 0.44)]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.21, green: 0.27, blue: 0.29),
                                        Color(red: 0.12, green: 0.16, blue: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if stage == .startup {
                    VStack(spacing: 7) {
                        Image(systemName: "sun.max").font(.system(size: 19, weight: .light))
                        Text("9:41").font(.system(size: 44, weight: .light, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.65))
                    .position(x: width * 0.48, y: height * 0.5)
                }
                if stage == .dock {
                    HStack(spacing: 9) {
                        ForEach(0..<3) { ring($0) }
                    }
                    .padding(8)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.1)))
                    .position(x: width / 2, y: height - 28)
                    cursor.position(x: width / 2 + 13, y: height - 16)
                } else if stage == .moving {
                    Circle().fill(.black).frame(width: 32, height: 32)
                        .overlay(Circle().stroke(colors[1].opacity(0.8), lineWidth: 1).padding(7))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 5)
                        .position(x: width * 0.53, y: height * 0.5)
                    cursor.position(x: width * 0.53 + 13, y: height * 0.5 + 13)
                } else {
                    let isLeft = stage == .edge
                    VStack(spacing: 8) {
                        ForEach(0..<3) { ring($0) }
                    }
                    .frame(width: 41, height: 106)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: isLeft ? 0 : 17,
                                               bottomLeadingRadius: isLeft ? 0 : 17,
                                               bottomTrailingRadius: isLeft ? 17 : 0,
                                               topTrailingRadius: isLeft ? 17 : 0)
                            .fill(.black)
                    }
                    .position(x: isLeft ? 20.5 : width - 20.5, y: height / 2)
                    if stage != .startup {
                        cursor.position(x: isLeft ? 33 : width - 10, y: height / 2 + 12)
                    }
                }
                VStack {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.24)).frame(width: 3, height: 3) }
                        Spacer()
                        Capsule().fill(.white.opacity(0.17)).frame(width: 20, height: 3)
                    }
                    .padding(10)
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func ring(_ index: Int) -> some View {
        ZStack {
            Circle().fill(.black)
            Circle().stroke(.white.opacity(0.17), lineWidth: 1.4).padding(2)
            Circle().trim(from: [0.3, 0.47, 0.7][index], to: 1)
                .stroke(colors[index], style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(2)
            Text(["70", "53", "30"][index]).font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
        }
        .frame(width: 25, height: 25)
    }

    private var cursor: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
    }
}
