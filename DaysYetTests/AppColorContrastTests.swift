#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import DaysYet

final class AppColorContrastTests: XCTestCase {
    func testActionTextIsReadableOnAppSurfacesInEveryAppearance() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    UITraitCollection(accessibilityContrast: contrast)
                ])
                let accent = try color("AccentColor", traits: traits)
                let surfaces = [
                    try color("PanelColor", traits: traits),
                    UIColor(style == .dark ? DaysYetTheme.ink : DaysYetTheme.paper),
                    UIColor(style == .dark ? DaysYetTheme.inkShade : DaysYetTheme.paperShade)
                ]
                for surface in surfaces {
                    XCTAssertGreaterThanOrEqual(try contrastRatio(accent, surface), 4.5,
                                               "Action text must remain readable: \(traits)")
                }
            }
        }
    }

    func testSelectedDatesAndPrimaryButtonsHaveReadableText() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    UITraitCollection(accessibilityContrast: contrast)
                ])
                let fill = try color("AccentColor", traits: traits)
                let foreground = try color("OnAccentColor", traits: traits)
                XCTAssertGreaterThanOrEqual(try contrastRatio(foreground, fill), 4.5,
                                           "Filled selections must remain readable: \(traits)")
            }
        }
    }

    private func color(_ name: String, traits: UITraitCollection) throws -> UIColor {
        let color = try XCTUnwrap(UIColor(named: name, in: Bundle(for: ProfileStore.self), compatibleWith: traits))
        return color.resolvedColor(with: traits)
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) throws -> CGFloat {
        let a = try luminance(first)
        let b = try luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: UIColor) throws -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 1)
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
#endif
