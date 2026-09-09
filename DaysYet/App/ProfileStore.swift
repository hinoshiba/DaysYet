import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile
    private let saveProfile: (UserProfile) -> Void

    init(
        profile: UserProfile = ProfileRepository.load(),
        saveProfile: @escaping (UserProfile) -> Void = {
            ProfileRepository.save($0)
            WidgetCenter.shared.reloadAllTimelines()
        }
    ) {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // Synthetic UI-review data must never replace a person’s saved profile.
        self.saveProfile = arguments.contains("--screenshot-mode") ? { _ in } : saveProfile
        if arguments.contains("--screenshot-onboarding") {
            var screenshotProfile = UserProfile.initial
            screenshotProfile.isConfigured = false
            self.profile = screenshotProfile
        } else if arguments.contains("--screenshot-mode") {
            var screenshotProfile = UserProfile.initial
            let calendar = Calendar(identifier: .gregorian)
            screenshotProfile.birthDate = calendar.date(
                from: DateComponents(year: 1992, month: 4, day: 12)
            ) ?? screenshotProfile.birthDate
            screenshotProfile.healthyLifeYears = 82
            screenshotProfile.customTargetName = L10n.text("大切な節目", "A milestone")
            screenshotProfile.customTargetStartDate = calendar.date(
                byAdding: .year,
                value: -1,
                to: .now
            ) ?? screenshotProfile.customTargetStartDate
            screenshotProfile.customTargetDate = calendar.date(
                byAdding: .year,
                value: 5,
                to: .now
            ) ?? screenshotProfile.customTargetDate
            screenshotProfile.dashboardMetrics = [.month, .year, .customLife]
            screenshotProfile.dashboardValueStyle = arguments.contains("--screenshot-target-date")
                ? .targetDate
                : arguments.contains("--screenshot-percentage") ? .percentage : .remaining
            screenshotProfile.widgetDisplayMode = arguments.contains("--screenshot-time-and-percentage")
                ? .countdownWithPercentage
                : arguments.contains("--screenshot-countdown") ? .countdown : .progressBars
            screenshotProfile.widgetTheme = arguments.contains("--screenshot-quiet-forest")
                ? .quietForest
                : arguments.contains("--screenshot-soft-dawn")
                    ? .softDawn
                    : arguments.contains("--screenshot-calm-sea") ? .calmSea : .vividNight
            if arguments.contains("--screenshot-study-days") || arguments.contains("--screenshot-study-widget") {
                let start = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
                let end = calendar.date(byAdding: .day, value: 27, to: start) ?? start
                screenshotProfile.studySchedule = StudySchedule(
                    name: L10n.text("資格試験の準備", "Exam preparation"),
                    startDate: start, endDate: end, activeWeekdays: [2, 4, 6]
                )
                if let extra = calendar.date(byAdding: .day, value: 11, to: start) {
                    screenshotProfile.studySchedule.toggleDate(extra, calendar: calendar)
                }
                screenshotProfile.weekStartDay = .monday
                screenshotProfile.dashboardMetrics = [.study, .week, .month]
            }
            screenshotProfile.isConfigured = true
            self.profile = screenshotProfile
        } else if arguments.contains("--skip-onboarding") {
            var previewProfile = profile
            previewProfile.isConfigured = true
            self.profile = previewProfile
        } else {
            self.profile = profile
        }
#else
        self.saveProfile = saveProfile
        self.profile = profile
#endif
    }

    func update(_ mutation: (inout UserProfile) -> Void) {
        var updated = profile
        mutation(&updated)
#if os(macOS)
        updated.dashboardMetrics = updated.macDashboardMetrics
#else
        updated.dashboardMetrics = updated.normalizedDashboardMetrics
#endif
        updated.dailyActivity = updated.dailyActivity.normalized
        updated.workActivity = updated.workActivity.normalized
        updated.studySchedule = updated.studySchedule.normalized
        // The UI intentionally exposes a start date, not a hidden start time.
        updated.customTargetStartDate = Calendar.autoupdatingCurrent.startOfDay(
            for: updated.customTargetStartDate
        )
        let minimumTarget = updated.customTargetStartDate.addingTimeInterval(60)
        if updated.customTargetDate < minimumTarget {
            updated.customTargetDate = minimumTarget
        }
        profile = updated
        persist()
    }

    func setDashboardMetric(_ metric: MetricKind, at index: Int) {
#if os(macOS)
        var metrics = profile.macDashboardMetrics
#else
        var metrics = profile.normalizedDashboardMetrics
#endif
        guard metrics.indices.contains(index) else { return }
        if let duplicateIndex = metrics.firstIndex(of: metric), duplicateIndex != index {
            metrics.swapAt(index, duplicateIndex)
        } else {
            metrics[index] = metric
        }
        update { $0.dashboardMetrics = metrics }
    }

#if os(macOS)
    func addMacDashboardMetric() {
        var metrics = profile.macDashboardMetrics
        guard let next = MetricKind.allCases.first(where: { !metrics.contains($0) }) else { return }
        metrics.append(next)
        update { $0.dashboardMetrics = metrics }
    }

    func removeMacDashboardMetric(at index: Int) {
        var metrics = profile.macDashboardMetrics
        guard metrics.count > 3, metrics.indices.contains(index) else { return }
        metrics.remove(at: index)
        update { $0.dashboardMetrics = metrics }
    }
#endif

    func completeOnboarding(
        birthDate: Date,
        healthyLifeYears: Double,
        customTargetName: String,
        customTargetStartDate: Date,
        customTargetDate: Date
    ) {
        update {
            $0.birthDate = birthDate
            $0.healthyLifeYears = healthyLifeYears
            $0.customTargetName = customTargetName
            $0.customTargetStartDate = customTargetStartDate
            $0.customTargetDate = customTargetDate
            $0.dashboardMetrics = [.month, .year, .healthyLife]
            $0.isConfigured = true
        }
    }

    func reset() {
#if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            ProfileRepository.reset()
        }
#else
        ProfileRepository.reset()
#endif
        profile = .initial
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persist() {
        saveProfile(profile)
    }
}
