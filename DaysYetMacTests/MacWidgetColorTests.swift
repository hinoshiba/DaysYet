import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacWidgetColorTests: XCTestCase {
    func testHexAcceptsSixDigitsWithOptionalHashAndNormalizesCase() throws {
        for input in ["#01aBfE", "01abfe", "#01ABFE"] {
            XCTAssertEqual(try XCTUnwrap(MacWidgetColor(hex: input)).hex, "#01ABFE")
        }
        XCTAssertEqual(MacWidgetColor(hex: "000000")?.hex, "#000000")
        XCTAssertEqual(MacWidgetColor(hex: "ffffff")?.hex, "#FFFFFF")
    }

    func testInvalidHexIsRejected() {
        for input in ["", "#", "FFF", "#12345", "1234567", "#12345678", "##123456", "+12345",
                      "#GG1122", " 123456", "123456\n", "＃123456", "１２３４５６"] {
            XCTAssertNil(MacWidgetColor(hex: input), input)
        }
    }

    func testSwiftUIColorConversionRoundsToEightBitsAndRemovesOpacity() throws {
        let color = try XCTUnwrap(MacWidgetColor(color: Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.2)))
        XCTAssertEqual(color.hex, "#FF8000")
        let restored = try XCTUnwrap(NSColor(color.color).usingColorSpace(.sRGB))
        XCTAssertEqual(restored.alphaComponent, 1)
        XCTAssertEqual(restored.redComponent, 1)
        XCTAssertEqual(restored.greenComponent, CGFloat(128) / 255, accuracy: 0.0001)
        XCTAssertEqual(restored.blueComponent, 0)
    }

    func testSwiftUIColorRoundTripPreservesStoredValues() throws {
        for hex in ["#000000", "#FFFFFF", "#0180FE", "#A47C23"] {
            let stored = try XCTUnwrap(MacWidgetColor(hex: hex))
            XCTAssertEqual(MacWidgetColor(color: stored.color), stored)
        }
    }

    @MainActor
    func testCustomColorsPersistByMetricAndCanBeRemovedIndependently() throws {
        try withDefaults { defaults in
            let weekColor = try XCTUnwrap(MacWidgetColor(hex: "#1278FE"))
            let monthColor = try XCTUnwrap(MacWidgetColor(hex: "#AABBCC"))
            let preferences = MacWidgetPreferences(defaults: defaults)
            preferences.setCustomColor(weekColor, for: .week)
            preferences.setCustomColor(monthColor, for: .month)

            let restored = MacWidgetPreferences(defaults: defaults)
            XCTAssertEqual(restored.customColors, [.week: weekColor, .month: monthColor])
            XCTAssertEqual(restored.customColor(for: .week), weekColor)
            XCTAssertNil(restored.customColor(for: .year))
            XCTAssertEqual(defaults.dictionary(forKey: "mac-widget-custom-colors") as? [String: String],
                           ["week": "#1278FE", "month": "#AABBCC"])

            restored.setCustomColor(nil, for: .week)
            XCTAssertEqual(MacWidgetPreferences(defaults: defaults).customColors, [.month: monthColor])
            restored.setCustomColor(nil, for: .month)
            XCTAssertTrue(MacWidgetPreferences(defaults: defaults).customColors.isEmpty)
            XCTAssertNil(defaults.object(forKey: "mac-widget-custom-colors"))
        }
    }

    @MainActor
    func testRestoreIgnoresInvalidEntriesWithoutDiscardingValidColors() throws {
        try withDefaults { defaults in
            let stored: [String: Any] = ["week": "#12abEF", "month": "invalid", "year": 123,
                                         "unknownFutureMetric": "#445566", "workday": "445566"]
            defaults.set(stored, forKey: "mac-widget-custom-colors")
            let preferences = MacWidgetPreferences(defaults: defaults)
            XCTAssertEqual(preferences.customColors, [.week: try XCTUnwrap(MacWidgetColor(hex: "#12ABEF")),
                                                     .workday: try XCTUnwrap(MacWidgetColor(hex: "#445566"))])
            XCTAssertNil(preferences.customColor(for: .month))
            XCTAssertNil(preferences.customColor(for: .year))

            for malformed in ["#123456", ["#123456"], 123] as [Any] {
                defaults.set(malformed, forKey: "mac-widget-custom-colors")
                XCTAssertTrue(MacWidgetPreferences(defaults: defaults).customColors.isEmpty)
            }
        }
    }

    @MainActor
    func testColorResetPreservesPlacementAndOtherAppSettings() throws {
        try withDefaults { defaults in
            defaults.set("preserve", forKey: "unrelated-setting")
            let preferences = MacWidgetPreferences(defaults: defaults)
            preferences.edge = .left
            preferences.scale = 1.3
            preferences.setCustomColor(try XCTUnwrap(MacWidgetColor(hex: "#112233")), for: .week)

            preferences.resetCustomColors()
            let restored = MacWidgetPreferences(defaults: defaults)
            for result in [preferences, restored] {
                XCTAssertTrue(result.customColors.isEmpty)
                XCTAssertEqual(result.edge, .left)
                XCTAssertEqual(result.scale, 1.3)
            }
            XCTAssertNil(defaults.object(forKey: "mac-widget-custom-colors"))
            XCTAssertEqual(defaults.string(forKey: "unrelated-setting"), "preserve")
        }
    }

    @MainActor
    func testFullResetAlsoRemovesCustomColorsWithoutErasingOtherAppSettings() throws {
        try withDefaults { defaults in
            defaults.set("preserve", forKey: "unrelated-setting")
            let preferences = MacWidgetPreferences(defaults: defaults)
            preferences.setCustomColor(try XCTUnwrap(MacWidgetColor(hex: "#445566")), for: .year)

            preferences.reset()

            XCTAssertTrue(preferences.customColors.isEmpty)
            XCTAssertTrue(MacWidgetPreferences(defaults: defaults).customColors.isEmpty)
            XCTAssertNil(defaults.object(forKey: "mac-widget-custom-colors"))
            XCTAssertEqual(defaults.string(forKey: "unrelated-setting"), "preserve")
        }
    }

    func testCustomColorOverridesEveryTemplateOnlyForItsMetric() throws {
        let custom = try XCTUnwrap(MacWidgetColor(hex: "#12ABEF"))
        for theme in WidgetTheme.allCases {
            XCTAssertEqual(MacWidgetStyle.accent(for: .week, theme: theme, customColors: [.week: custom]), custom.color)
            for kind in MetricKind.allCases where kind != .week {
                XCTAssertEqual(MacWidgetStyle.accent(for: kind, theme: theme, customColors: [.week: custom]),
                               MacWidgetStyle.accent(for: kind, theme: theme))
            }
        }
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "com.hinoshiba.daysyet.mac.color.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
