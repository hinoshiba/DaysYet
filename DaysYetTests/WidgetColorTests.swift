import SwiftUI
import XCTest
#if os(macOS)
import AppKit
@testable import DaysYetMac
#else
import UIKit
@testable import DaysYet
#endif

final class WidgetColorTests: XCTestCase {
    func testHexAndCodableNormalizeSixDigitRGBWithoutAddingAlpha() throws {
        for input in ["#01aBfE", "01abfe", "#01ABFE"] {
            let color = try XCTUnwrap(WidgetColor(hex: input))
            XCTAssertEqual(color.hex, "#01ABFE")
            let data = try JSONEncoder().encode(color)
            XCTAssertEqual(String(data: data, encoding: .utf8), "\"#01ABFE\"")
            XCTAssertEqual(try JSONDecoder().decode(WidgetColor.self, from: data), color)
        }
        XCTAssertEqual(WidgetColor(hex: "000000")?.hex, "#000000")
        XCTAssertEqual(WidgetColor(hex: "ffffff")?.hex, "#FFFFFF")
    }

    func testMalformedHexAndNonStringEncodedColorsAreRejected() throws {
        for input in ["", "#", "FFF", "#12345", "1234567", "#12345678", "##123456", "+12345",
                      "#GG1122", " 123456", "123456\n", "＃123456", "１２３４５６"] {
            XCTAssertNil(WidgetColor(hex: input), input)
            XCTAssertThrowsError(try JSONDecoder().decode(WidgetColor.self, from: JSONEncoder().encode(input)), input)
        }
        for json in ["null", "123456", "[]", "{}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(WidgetColor.self, from: Data(json.utf8)), json)
        }
    }

    func testColorConversionRoundsToEightBitsAndRestoresOpaqueSRGB() throws {
        let color = try XCTUnwrap(WidgetColor(color: Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.2)))
        XCTAssertEqual(color.hex, "#FF8000")
#if os(macOS)
        let restored = try XCTUnwrap(NSColor(color.color).usingColorSpace(.sRGB))
        XCTAssertEqual(restored.alphaComponent, 1)
        XCTAssertEqual(restored.redComponent, 1)
        XCTAssertEqual(restored.greenComponent, CGFloat(128) / 255, accuracy: 0.0001)
        XCTAssertEqual(restored.blueComponent, 0)
#else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color.color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 1)
        XCTAssertEqual(red, 1)
        XCTAssertEqual(green, CGFloat(128) / 255, accuracy: 0.0001)
        XCTAssertEqual(blue, 0)
#endif
    }

    func testColorPickerRoundTripDoesNotDriftStoredRGBValues() throws {
        for hex in ["#000000", "#FFFFFF", "#0180FE", "#A47C23", "#FF8000"] {
            let color = try XCTUnwrap(WidgetColor(hex: hex))
            XCTAssertEqual(WidgetColor(color: color.color), color)
        }
    }
}
