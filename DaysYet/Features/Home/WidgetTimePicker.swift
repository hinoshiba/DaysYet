import SwiftUI

enum WidgetTimeDestination {
    case newCircle, circle(Int), row(Int)

    var isAdding: Bool {
        if case .newCircle = self { return true }
        return false
    }

    var title: String {
        isAdding ? L10n.text("時間から追加", "Add from Times") : L10n.text("表示する時間を選ぶ", "Choose a time")
    }

    static func rowTitle(at index: Int) -> String {
        [L10n.text("上", "Top"), L10n.text("中央", "Middle"), L10n.text("下", "Bottom")][index]
    }

    func selectedMetric(in profile: UserProfile) -> MetricKind? {
        switch self {
        case .newCircle: nil
        case .circle(let index): profile.circleWidgetSettings.normalizedMetrics[index]
        case .row(let index): profile.normalizedDashboardMetrics[index]
        }
    }

    func placementNote(for metric: MetricKind, in profile: UserProfile) -> String? {
        switch self {
        case .row(let index):
            guard let other = profile.normalizedDashboardMetrics.firstIndex(of: metric), other != index else { return nil }
            return L10n.text("\(Self.rowTitle(at: other))の行と入れ替え", "Swaps with the \(Self.rowTitle(at: other).lowercased()) row")
        case .newCircle, .circle:
            return profile.circleWidgetSettings.normalizedMetrics.contains(metric)
                ? L10n.text("サークルに表示中", "Already in Circles") : nil
        }
    }
}

struct WidgetTimeRequest: Identifiable {
    let id = UUID()
    let destination: WidgetTimeDestination
}

/// Select an existing time; this screen never edits its schedule or dates.
struct WidgetTimePicker: View {
    @Environment(\.dismiss) private var dismiss
    let profile: UserProfile
    let destination: WidgetTimeDestination
    let onSelect: (MetricKind) -> Void
    let onOpenTimeLibrary: () -> Void

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List {
                    Section {
                        ForEach(MetricKind.allCases) { metric in
                            let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: profile, now: context.date)
                            let isSelected = destination.selectedMetric(in: profile) == metric
                            Button {
                                if !isSelected { onSelect(metric) }
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: metric.symbolName)
                                        .font(.title3)
                                        .foregroundStyle(profile.widgetTheme.palette.colors(for: metric, customColors: profile.widgetCustomColors).first ?? .accentColor)
                                        .frame(width: 28)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(snapshot.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(snapshot.remainingText)
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        if let note = destination.placementNote(for: metric, in: profile), !isSelected {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    if isSelected || destination.isAdding {
                                        Image(systemName: isSelected ? "checkmark" : "plus")
                                            .foregroundStyle(.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("widget.time.\(metric.rawValue)")
                            .accessibilityValue(isSelected ? L10n.text("選択中", "Selected") : "")
                            .accessibilityHint(destination.isAdding
                                ? L10n.text("サークルに追加", "Add to Circles")
                                : L10n.text("この時間を表示", "Display this time"))
                        }
                    } header: {
                        Text(L10n.text("時間の一覧", "Time library"))
                    } footer: {
                        Text(L10n.text("時刻・日付など、時間の内容は「時間」タブで編集できます。", "Edit schedules, dates, and other details in the Times tab."))
                    }
                    .listRowBackground(DaysYetTheme.panel)

                    Section {
                        Button {
                            onOpenTimeLibrary()
                            dismiss()
                        } label: {
                            Label(L10n.text("「時間」タブを開く", "Open Times"), systemImage: "circle.dotted")
                        }
                        .accessibilityIdentifier("widget.time.openLibrary")
                    }
                    .listRowBackground(DaysYetTheme.panel)
                }
            }
            .daysYetBackground()
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("キャンセル", "Cancel")) { dismiss() }
                        .accessibilityIdentifier("widget.time.cancel")
                }
            }
        }
    }
}

struct WidgetMetricSettingRow: View {
    let metric: MetricKind
    let profile: UserProfile
    let index: Int
    var isCircle = true
    var showsSelectionAction = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: profile, now: context.date)
            let theme = profile.widgetTheme
            HStack(spacing: 16) {
                if isCircle {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 4)
                        Circle()
                            .trim(from: 1 - snapshot.remainingFraction, to: 1)
                            .stroke(AngularGradient(colors: theme.palette.colors(for: metric, customColors: profile.resolvedCircleWidgetCustomColors), center: .center),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                } else {
                    Text(positionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40)
                        .accessibilityHidden(true)
                }

                MetricTitleValueLabel(title: snapshot.title, value: snapshot.remainingText)
                if showsSelectionAction {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(positionTitle + ", " + snapshot.accessibilitySummary)
            .accessibilityHint(showsSelectionAction ? L10n.text("時間の一覧から差し替えます", "Replace with a time from your library") : "")
        }
    }

    private var positionTitle: String {
        if isCircle { return L10n.text("サークル\(index + 1)", "Circle \(index + 1)") }
        return WidgetTimeDestination.rowTitle(at: index)
    }
}
