import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// An opaque sRGB color that keeps the same value after saving and restoring.
struct WidgetColor: Codable, Equatable, Sendable {
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
        let components: (CGFloat, CGFloat, CGFloat)
#if canImport(AppKit)
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        components = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
#elseif canImport(UIKit)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = UIColor(color).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let values = rgb.components, values.count >= 3 else { return nil }
        components = (values[0], values[1], values[2])
#endif
        guard components.0.isFinite, components.1.isFinite, components.2.isFinite else { return nil }
        func component(_ value: CGFloat) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        red = component(components.0)
        green = component(components.1)
        blue = component(components.2)
    }

    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let color = Self(hex: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a six-digit RGB color.")
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// A malformed or future entry must not discard other saved timeline colors.
struct WidgetColorMap: Codable {
    let colors: [MetricKind: WidgetColor]

    init(_ colors: [MetricKind: WidgetColor]) {
        self.colors = colors
    }

    private struct MetricKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: MetricKey.self) else {
            colors = [:]
            return
        }
        colors = container.allKeys.reduce(into: [:]) { result, key in
            guard let kind = MetricKind(rawValue: key.stringValue),
                  let color = try? container.decode(WidgetColor.self, forKey: key) else { return }
            result[kind] = color
        }
    }

    func encode(to encoder: Encoder) throws {
        let values = Dictionary(uniqueKeysWithValues: colors.map { ($0.key.rawValue, $0.value.hex) })
        try values.encode(to: encoder)
    }
}
