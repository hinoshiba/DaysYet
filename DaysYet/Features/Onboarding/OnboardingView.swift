import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var step = 0
    @State private var birthDate = UserProfile.initial.birthDate
    @State private var healthyLifeYears = UserProfile.initial.healthyLifeYears
    @State private var customTargetName = UserProfile.initial.customTargetName
    @State private var customTargetDate = UserProfile.initial.customTargetDate

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
            customTargetName = store.profile.customTargetName
            customTargetDate = store.profile.customTargetDate
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            BrandMark()
                .frame(width: 180, height: 180)
            VStack(spacing: 12) {
                EyebrowLabel(text: "DAYSYET")
                Text(L10n.text("時間は、まだある。\n今日を選ぶ。", "There is time yet.\nChoose today."))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .tracking(-0.8)
                Text(L10n.text("今月、今年、人生の時間。\n大切な3本だけを、ホーム画面へ。", "Month, year, and life.\nKeep the three that matter on your Home Screen."))
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
                    EyebrowLabel(text: L10n.text("あなたの時間", "Your time"))
                    Text(L10n.text("基準を決める", "Set your reference points"))
                        .font(.largeTitle.bold())
                    Text(L10n.text("すべて端末内に保存されます。後からいつでも変更できます。", "Everything stays on device and can be changed anytime."))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    DatePicker(
                        L10n.text("生年月日", "Birth date"),
                        selection: $birthDate,
                        in: earliestBirthDate ... Date.now,
                        displayedComponents: .date
                    )
                    .padding(16)

                    Divider().padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.text("健康でいたい年齢", "Healthy-age goal"))
                            Spacer()
                            Text("\(Int(healthyLifeYears))")
                                .font(.headline.monospacedDigit())
                        }
                        Slider(value: $healthyLifeYears, in: 50...110, step: 1)
                    }
                    .padding(16)

                    Divider().padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        TextField(L10n.text("節目の名前", "Milestone name"), text: $customTargetName)
                        DatePicker(
                            L10n.text("日時", "Date and time"),
                            selection: $customTargetDate,
                            in: Date.now ... latestTargetDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    .padding(16)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Label(
                    L10n.text("「健康でいたい年齢」は診断や寿命予測ではなく、ご自身で決める計画上の目標です。", "The healthy-age goal is a personal planning marker, not a diagnosis or life-expectancy prediction."),
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel(text: L10n.text("準備完了", "Ready"))
                    Text(L10n.text("3つの時間を、\nひと目に。", "Three times,\none glance."))
                        .font(.largeTitle.bold())
                    Text(L10n.text("最初は「今月・今年・健康でいたい年齢」。アプリ内で自由に入れ替えられます。", "Start with month, year, and your healthy-age goal. Change them anytime in the app."))
                        .foregroundStyle(.secondary)
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
        HStack(spacing: 14) {
            if step > 0 {
                Button(L10n.text("戻る", "Back")) {
                    withAnimation(.snappy) { step -= 1 }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }

            Button {
                if step < 2 {
                    withAnimation(.snappy) { step += 1 }
                } else {
                    store.completeOnboarding(
                        birthDate: birthDate,
                        healthyLifeYears: healthyLifeYears,
                        customTargetName: customTargetName,
                        customTargetDate: customTargetDate
                    )
                }
            } label: {
                Text(step == 2 ? L10n.text("はじめる", "Get started") : L10n.text("続ける", "Continue"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
        }
        .controlSize(.large)
    }

    private var previewProfile: UserProfile {
        var profile = store.profile
        profile.birthDate = birthDate
        profile.healthyLifeYears = healthyLifeYears
        profile.customTargetName = customTargetName
        profile.customTargetDate = customTargetDate
        profile.dashboardMetrics = [.month, .year, .healthyLife]
        return profile
    }

    private var earliestBirthDate: Date {
        Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    }

    private var latestTargetDate: Date {
        Calendar.current.date(byAdding: .year, value: 100, to: .now) ?? .distantFuture
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
