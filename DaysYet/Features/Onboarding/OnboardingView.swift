import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step = 0
    @State private var birthDate = UserProfile.initial.birthDate
    @State private var healthyLifeYears = UserProfile.initial.healthyLifeYears
    @State private var defersHealthyLifeSetup = false

    var body: some View {
        ZStack {
            DaysYetBackground()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? DaysYetTheme.coral : .primary.opacity(0.12))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: profile
                    default: preview
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
                    .padding(24)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            birthDate = store.profile.birthDate
            healthyLifeYears = store.profile.healthyLifeYears
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            BrandMark()
                .frame(width: 180, height: 180)
            VStack(spacing: 12) {
                EyebrowLabel(text: "DAYSYET")
                Text(L10n.text("人生のTokenを、\n大切なことへ。", "Life’s tokens.\nMake them count."))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .tracking(-0.8)
                Text(L10n.text("活動時間から、今月・今年・人生まで。\n大切な時間を、ホーム画面へ。", "From activity hours to months, years, and life.\nKeep the times that matter on your Home Screen."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .padding(24)
    }

    private var profile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("健康でいたい年齢まで", "Until your healthy-age goal"))
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text(
                        "生年月日から、目標年齢までの残り時間を表示します。",
                        "Your birth date lets us show the time remaining until your target age."
                    ))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.birthDateReason")
                }

                MetricWidgetPreview(profile: healthyLifePreviewProfile, metric: .healthyLife)
                    .accessibilityIdentifier("onboarding.healthyLifePreview")

                VStack(spacing: 0) {
                    birthDateInput
                        .padding(16)

                    Divider().padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.text("目標年齢", "Target age"))
                            Spacer()
                            Text("\(Int(healthyLifeYears))")
                                .font(.headline.monospacedDigit())
                        }
                        Slider(value: $healthyLifeYears, in: 50...110, step: 1)
                            .accessibilityLabel(L10n.text("目標年齢", "Target age"))
                            .accessibilityIdentifier("onboarding.healthyLifeYears")
                    }
                    .padding(16)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("自分で決める目標です。寿命の予測ではありません。", "A goal you choose, not a lifespan prediction."))
                    Text(L10n.text("端末内に保存・あとから変更できます", "Saved on this device. Change it anytime."))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var birthDateInput: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("生年月日", "Birth date"))
                birthDatePicker
                    .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            birthDatePicker
        }
    }

    private var birthDatePicker: some View {
        DatePicker(
            L10n.text("生年月日", "Birth date"),
            selection: $birthDate,
            in: earliestBirthDate ... Date.now,
            displayedComponents: .date
        )
        .accessibilityIdentifier("onboarding.birthDate")
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel(text: L10n.text("準備完了", "Ready"))
                    Text(L10n.text("大切な時間を、\nひと目に。", "Your time,\none glance."))
                        .font(.largeTitle.bold())
                    Text(defersHealthyLifeSetup
                         ? L10n.text("健康目標は、あとから「時間」で設定できます。", "Set your healthy-age goal later in Times.")
                         : L10n.text("あとから「時間」で変更できます。", "Change your times anytime in Times."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.previewDescription")
                }

                WidgetPreview(profile: previewProfile)
                    .aspectRatio(2.05, contentMode: .fit)

                Label(
                    L10n.text("アカウント不要・広告なし・外部送信なし", "No account, no ads, no data sent off device"),
                    systemImage: "hand.raised.fill"
                )
                .font(.subheadline.weight(.semibold))
            }
            .padding(24)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                if step > 0 {
                    Button {
                        withAnimation(.snappy) { step -= 1 }
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "chevron.backward")
                                .accessibilityLabel(L10n.text("戻る", "Back"))
                        } else {
                            Text(L10n.text("戻る", "Back"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .accessibilityIdentifier("onboarding.back")
                }

                Button {
                    if step < 2 {
                        if step == 1 { defersHealthyLifeSetup = false }
                        withAnimation(.snappy) { step += 1 }
                    } else {
                        store.completeOnboarding(
                            birthDate: defersHealthyLifeSetup ? nil : birthDate,
                            healthyLifeYears: healthyLifeYears
                        )
                    }
                } label: {
                    Text(step == 2 ? L10n.text("はじめる", "Get started") : L10n.text("続ける", "Continue"))
                        .foregroundStyle(DaysYetTheme.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .accessibilityIdentifier("onboarding.continue")
            }

            if step == 1 {
                Button(L10n.text("あとで設定", "Set up later")) {
                    defersHealthyLifeSetup = true
                    withAnimation(.snappy) { step = 2 }
                }
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .controlSize(.large)
    }

    private var healthyLifePreviewProfile: UserProfile {
        var profile = store.profile
        profile.birthDate = birthDate
        profile.healthyLifeYears = healthyLifeYears
        profile.isHealthyLifeConfigured = true
        return profile
    }

    private var previewProfile: UserProfile {
        var profile = defersHealthyLifeSetup ? store.profile : healthyLifePreviewProfile
        profile.isHealthyLifeConfigured = !defersHealthyLifeSetup
        profile.dashboardMetrics = defersHealthyLifeSetup ? [.week, .month, .year] : [.month, .year, .healthyLife]
        return profile
    }

    private var earliestBirthDate: Date {
        Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    }
}

private struct BrandMark: View {
    var body: some View {
        VStack(spacing: 18) {
            BrandLine(fraction: 0.52, color: DaysYetTheme.coral)
            BrandLine(fraction: 0.67, color: DaysYetTheme.amber)
            BrandLine(fraction: 0.82, color: DaysYetTheme.lime)
        }
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(DaysYetTheme.ink)
                .shadow(color: DaysYetTheme.coral.opacity(0.22), radius: 24, y: 10)
        }
    }
}

private struct BrandLine: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geometry.size.width * fraction)
                    .shadow(color: color.opacity(0.5), radius: 5)
            }
        }
        .frame(height: 13)
    }
}
