#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import DaysYet

/// Native rendering evidence for the shared layout, not a WidgetKit host screenshot.
/// Attachments deliberately stay in the test result rather than the app's storage.
@MainActor
final class CircleWidgetRenderingTests: XCTestCase {
    func testPercentageGlyphsFitWithoutPerValueShrinking() {
        for diameter in stride(from: 56.0, through: 180.0, by: 1) {
            for scale in [1.0, 2.0, 3.0] {
                let layout = CircleWidgetTextLayout(
                    diameter: diameter, labelSize: 11 * scale, valueSize: 28 * scale,
                    valueLineLimit: 1, isPercentage: true
                )
                let digits = UIFont.monospacedDigitSystemFont(ofSize: layout.valueSize, weight: .bold)
                let roundedDigits = UIFont(descriptor: digits.fontDescriptor.withDesign(.rounded)!, size: layout.valueSize)
                let symbol = UIFont.systemFont(ofSize: layout.symbolSize, weight: .semibold)
                let roundedSymbol = UIFont(descriptor: symbol.fontDescriptor.withDesign(.rounded)!, size: layout.symbolSize)
                for number in ["0", "9", "99", "100", "<1"] {
                    let actualWidth = (number as NSString).size(withAttributes: [.font: roundedDigits]).width
                        + ("%" as NSString).size(withAttributes: [.font: roundedSymbol]).width
                    XCTAssertLessThanOrEqual(actualWidth, layout.contentWidth, "\(number)% at diameter \(diameter)")
                }
                XCTAssertLessThanOrEqual(roundedDigits.lineHeight, layout.valueHeight + 0.1)
            }
        }
    }

    func testCompactDateGlyphsFitAtSmallestSupportedRenderSize() {
        for scale in [1.0, 2.0, 3.0] {
            let layout = CircleWidgetTextLayout(
                diameter: 59, labelSize: 11 * scale, valueSize: 11,
                valueLineLimit: 1, isPercentage: false
            )
            let font = UIFont.systemFont(ofSize: layout.valueSize * 0.85, weight: .semibold, width: .condensed)
            for value in ["12/30/28", "28/12/30", "12/31/99", "99/12/31", "23:59"] {
                let width = (value as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width, layout.contentWidth, value)
            }
        }
    }

    func testJapaneseCompact158PercentageBoundaries() throws {
        try attachRendering(
            name: "Shared circle layout — Japanese — 158pt — 0, 9, 99, 100 percent",
            size: 158,
            compact: true,
            snapshots: zip(["今週", "今月", "今年", "活動"], [0.0, 0.09, 0.99, 1.0])
                .enumerated().map { index, pair in
                    snapshot(kind: defaultKinds[index], title: pair.0, remaining: pair.1)
                }
        )
    }

    func testEnglishCompact170PercentageBoundaries() throws {
        try attachRendering(
            name: "Shared circle layout — English — 170pt — less than 1, 9, 99, 100 percent",
            size: 170,
            compact: true,
            snapshots: zip(["Week", "Month", "Year", "Activity"], [0.005, 0.09, 0.99, 1.0])
                .enumerated().map { index, pair in
                    snapshot(kind: defaultKinds[index], title: pair.0, remaining: pair.1)
                },
            locale: Locale(identifier: "en_US")
        )
    }

    func testCompact186LongCustomTitles() throws {
        try attachRendering(
            name: "Shared circle layout — custom CJK, Latin, emoji — 186pt",
            size: 186,
            compact: true,
            snapshots: [
                snapshot(kind: .customLife, title: "家族みんなで楽しみにしている大切な記念日", remaining: 1),
                snapshot(kind: .workday, title: "InternationalResearchAndDevelopmentMilestone", remaining: 0.99),
                snapshot(kind: .study, title: "📚 日本語とEnglishを毎日学ぶ 🌱", remaining: 0.09),
                snapshot(kind: .healthyLife, title: "健康でいたい年齢", remaining: 0.005)
            ],
            theme: .quietForest
        )
    }

    func testJapaneseCompact158OffAndNoScheduledTime() throws {
        try attachRendering(
            name: "Shared circle layout — Japanese states — 158pt",
            size: 158,
            compact: true,
            snapshots: [
                snapshot(kind: .workday, title: "勤務", remaining: 0, terminal: "Off", isOff: true),
                snapshot(
                    kind: .study, title: "学習日", remaining: 0,
                    terminal: "学習日の予定なし", hasScheduledTime: false
                ),
                snapshot(kind: .activity, title: "活動", remaining: 1, terminal: "開始前"),
                snapshot(kind: .customLife, title: "大切な日", remaining: 0, terminal: "到達")
            ],
            theme: .softDawn
        )
    }

    func testEnglishCompact170RemainingValues() throws {
        try attachRendering(
            name: "Shared circle layout — English remaining values — 170pt",
            size: 170,
            compact: true,
            snapshots: [
                snapshot(
                    kind: .week, title: "Week", remaining: 0.5,
                    components: [.init(value: 3, unit: "d"), .init(value: 12, unit: "h")]
                ),
                snapshot(
                    kind: .healthyLife, title: "Health goal", remaining: 0.7,
                    components: [.init(value: 36, unit: "y"), .init(value: 10, unit: "mo")]
                ),
                snapshot(kind: .activity, title: "Activity", remaining: 1, terminal: "Not started"),
                snapshot(
                    kind: .study, title: "Study", remaining: 0,
                    terminal: "No study days", hasScheduledTime: false
                )
            ],
            valueStyle: .remaining,
            theme: .calmSea,
            locale: Locale(identifier: "en_US")
        )
    }

    func testJapaneseCompact158RemainingQuantities() throws {
        try attachRendering(
            name: "Shared circle layout — Japanese leading remaining unit — 158pt",
            size: 158,
            compact: true,
            snapshots: [
                snapshot(kind: .week, title: "今週", remaining: 0.5,
                         components: [.init(value: 3, unit: "日"), .init(value: 12, unit: "時間")]),
                snapshot(kind: .healthyLife, title: "健康目標", remaining: 0.5,
                         components: [.init(value: 36, unit: "年"), .init(value: 10, unit: "か月")]),
                snapshot(kind: .activity, title: "活動", remaining: 0.5,
                         components: [.init(value: 0, unit: "日"), .init(value: 12, unit: "時間")]),
                snapshot(kind: .customLife, title: "大切な日", remaining: 0.5,
                         components: [.init(value: 0, unit: "年"), .init(value: 10, unit: "か月")])
            ],
            valueStyle: .remaining
        )
    }

    func testCompact158TargetDates() throws {
        let endOfYear = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2099, month: 12, day: 31, hour: 23, minute: 59
        )))
        for identifier in ["ja_JP", "en_US"] {
            try attachRendering(
                name: "Shared circle layout — compact dates \(identifier) — 158pt AX5",
                size: 158, compact: true,
                snapshots: [
                    snapshot(kind: .week, title: "今週", remaining: 0.5, targetDate: endOfYear),
                    snapshot(kind: .customLife, title: "大切な日", remaining: 0.5, targetDate: endOfYear),
                    snapshot(kind: .activity, title: "活動", remaining: 0.5, targetDate: endOfYear),
                    snapshot(kind: .study, title: "学習日", remaining: 0.5, targetDate: endOfYear)
                ],
                valueStyle: .targetDate,
                dynamicTypeSize: .accessibility5,
                locale: Locale(identifier: identifier)
            )
        }
    }

    func testJapaneseLarge338DefaultTitles() throws {
        try attachRendering(
            name: "Shared circle layout — Japanese full default titles — large 338pt",
            size: 338,
            compact: false,
            snapshots: [
                snapshot(kind: .week, title: "今週", remaining: 1),
                snapshot(kind: .month, title: "今月", remaining: 0.99),
                snapshot(kind: .healthyLife, title: "健康でいたい年齢", remaining: 0.09),
                snapshot(kind: .activity, title: "1日の活動", remaining: 0.005)
            ]
        )
    }

    func testLarge338TargetDatesAndLongTitles() throws {
        try attachRendering(
            name: "Shared circle layout — target dates and long titles — large 338pt",
            size: 338,
            compact: false,
            snapshots: [
                snapshot(kind: .healthyLife, title: "健康でいたい年齢", remaining: 0.5),
                snapshot(kind: .customLife, title: "家族みんなの大切な記念日", remaining: 0.9),
                snapshot(kind: .workday, title: "International research", remaining: 0.3),
                snapshot(kind: .study, title: "📚 日本語とEnglishの学習", remaining: 1)
            ],
            valueStyle: .targetDate,
            theme: .softDawn
        )
    }

    func testCompact158AccessibilityFiveLongTitles() throws {
        try attachRendering(
            name: "Shared circle layout — AX5 long titles — compact 158pt",
            size: 158,
            compact: true,
            snapshots: [
                snapshot(kind: .healthyLife, title: "健康目標", remaining: 1),
                snapshot(kind: .customLife, title: "ずっと楽しみにしていた記念日", remaining: 0.99),
                snapshot(kind: .workday, title: "InternationalResearch", remaining: 0.09),
                snapshot(kind: .study, title: "📚 日本語とEnglish 🌱", remaining: 0.005)
            ],
            dynamicTypeSize: .accessibility5
        )
    }

    private var defaultKinds: [MetricKind] { [.week, .month, .year, .activity] }

    private func snapshot(
        kind: MetricKind,
        title: String,
        remaining: Double,
        components: [CountdownComponent] = [.init(value: 12, unit: "日"), .init(value: 3, unit: "時間")],
        terminal: String? = nil,
        isOff: Bool = false,
        hasScheduledTime: Bool = true,
        targetDate: Date = Date(timeIntervalSince1970: 1_793_491_200)
    ) -> MetricSnapshot {
        MetricSnapshot(
            kind: kind,
            title: title,
            context: "Rendering fixture",
            countdown: CountdownPresentation(
                prefix: "", components: components, suffix: "", terminalText: terminal
            ),
            elapsedFraction: 1 - remaining,
            targetDate: targetDate,
            isOff: isOff,
            hasScheduledTime: hasScheduledTime
        )
    }

    private func attachRendering(
        name: String,
        size: CGFloat,
        compact: Bool,
        snapshots: [MetricSnapshot],
        valueStyle: MetricValueStyle = .percentage,
        theme: WidgetTheme = .vividNight,
        dynamicTypeSize: DynamicTypeSize = .large,
        locale: Locale = Locale(identifier: "ja_JP")
    ) throws {
        // Explicit fixture titles avoid dependence on the test host's bundle
        // language. Date/value prose still uses the app's normal localization.
        let content = CircleWidgetGrid(
            snapshots: snapshots,
            valueStyle: valueStyle,
            theme: theme,
            compact: compact,
            showsContainerBackground: true
        )
        .padding(16)
        .frame(width: size, height: size)
        .background(theme.palette.background, in: RoundedRectangle(cornerRadius: compact ? 22 : 28))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, locale)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "The shared SwiftUI layout must render.")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let png = try XCTUnwrap(image.pngData(), "Rendering evidence must encode as PNG.")
        XCTAssertFalse(png.isEmpty)

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
