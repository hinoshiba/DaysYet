import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile

    init(profile: UserProfile = ProfileRepository.load()) {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
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
            screenshotProfile.customTargetDate = calendar.date(
                byAdding: .year,
                value: 5,
                to: .now
            ) ?? screenshotProfile.customTargetDate
            screenshotProfile.dashboardMetrics = [.month, .year, .customLife]
            screenshotProfile.dashboardValueStyle = arguments.contains("--screenshot-target-date")
                ? .targetDate
                : arguments.contains("--screenshot-percentage") ? .percentage : .remaining
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
        self.profile = profile
#endif
    }

    func update(_ mutation: (inout UserProfile) -> Void) {
        var updated = profile
        mutation(&updated)
        updated.dashboardMetrics = updated.normalizedDashboardMetrics
        profile = updated
        persist()
    }

    func setDashboardMetric(_ metric: MetricKind, at index: Int) {
        guard profile.normalizedDashboardMetrics.indices.contains(index) else { return }
        var metrics = profile.normalizedDashboardMetrics
        if let duplicateIndex = metrics.firstIndex(of: metric), duplicateIndex != index {
            metrics.swapAt(index, duplicateIndex)
        } else {
            metrics[index] = metric
        }
        update { $0.dashboardMetrics = metrics }
    }

    func completeOnboarding(
        birthDate: Date,
        healthyLifeYears: Double,
        customTargetName: String,
        customTargetDate: Date
    ) {
        update {
            $0.birthDate = birthDate
            $0.healthyLifeYears = healthyLifeYears
            $0.customTargetName = customTargetName
            $0.customTargetDate = customTargetDate
            $0.dashboardMetrics = [.month, .year, .healthyLife]
            $0.isConfigured = true
        }
    }

    func reset() {
        ProfileRepository.reset()
        profile = .initial
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persist() {
        ProfileRepository.save(profile)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
