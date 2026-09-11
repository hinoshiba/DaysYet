import AppKit
import SwiftUI

/// An opaque sRGB color that keeps the same value after saving and restoring.
struct MacWidgetColor: Equatable {
    private let red: UInt8
    private let green: UInt8
    private let blue: UInt8

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.utf8.count == 6,
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(digits, radix: 16) else { return nil }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB),
              rgb.redComponent.isFinite, rgb.greenComponent.isFinite, rgb.blueComponent.isFinite else { return nil }
        func component(_ value: CGFloat) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        red = component(rgb.redComponent)
        green = component(rgb.greenComponent)
        blue = component(rgb.blueComponent)
    }

    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}
