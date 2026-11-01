import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacBottomSurfaceTests: XCTestCase {
    func testExpansionKeepsCirclesOnThePhysicalEdgeAndDetailsClearOfThem() {
        let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
        let visible = NSRect(x: -1520, y: 200, width: 1520, height: 888)
        for count in [3, 6, 8] {
            for scale in [0.8, 1, 1.5] {
                for detailScale in [1.0, 1.5] {
                    for hoverScale in [1.0, 1.55, 1.8] {
                        let closed = MacWidgetPlacement.frame(in: visible, edge: .bottom, position: 0.37,
                            expanded: false, scale: scale, screenFrame: screen, metricCount: count, detailScale: detailScale)
                        let opened = MacWidgetPlacement.frame(in: visible, edge: .bottom, position: 0.37,
                            expanded: true, scale: scale, screenFrame: screen, metricCount: count,
                            hoverScale: hoverScale, detailScale: detailScale)
                        XCTAssertEqual(closed.minY, screen.minY)
                        XCTAssertEqual(opened.minY, screen.minY)
                        XCTAssertEqual(closed.minX, opened.minX)
                        XCTAssertEqual(closed.width, opened.width)
                        for index in 0..<count {
                            let first = MacWidgetPlacement.dockRingFrame(in: closed.size, index: CGFloat(index),
                                scale: scale, metricCount: count, detailScale: detailScale)
                            let last = MacWidgetPlacement.dockRingFrame(in: opened.size, index: CGFloat(index),
                                scale: scale, metricCount: count, detailScale: detailScale)
                            XCTAssertEqual(closed.minX + first.midX, opened.minX + last.midX, accuracy: 0.001)
                            XCTAssertEqual(closed.maxY - first.midY, opened.maxY - last.midY, accuracy: 0.001)
                            XCTAssertEqual(first.minY, closed.height - first.maxY, accuracy: 0.001)
                            let enlarged = MacWidgetPlacement.dockRingFrame(in: opened.size, index: CGFloat(index),
                                scale: scale, metricCount: count, magnification: hoverScale, detailScale: detailScale)
                            let detail = MacWidgetPlacement.dockDetailFrame(in: opened.size, selectedIndex: CGFloat(index),
                                scale: scale, metricCount: count, detailScale: detailScale)
                            XCTAssertEqual(detail.midX, opened.width / 2, accuracy: 0.001)
                            XCTAssertGreaterThan(enlarged.minY - detail.maxY, 0)
                            XCTAssertEqual(enlarged.minY - detail.maxY, opened.height - enlarged.maxY, accuracy: 0.001,
                                "The selected circle needs equal space above and below, at every magnification.")
                            let surface = MacWidgetSurface.path(in: opened.size, edge: .bottom,
                                selectedIndex: CGFloat(index), scale: scale, metricCount: count,
                                hoverScale: hoverScale, detailScale: detailScale, magnifications: [index: hoverScale])
                            for x in [detail.minX, detail.maxX] {
                                for y in [detail.minY, detail.maxY] {
                                    XCTAssertTrue(surface.contains(CGPoint(x: x, y: y)),
                                        "The compact surface must keep the whole detail and progress bar visible.")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testSurfaceRemainsBroadAndConnectedThroughoutHoverExpansion() {
        for count in [3, 6, 8] {
            for detailScale in [1.0, 1.5] {
                let width = MacWidgetPlacement.dockWidth(for: count, detailScale: detailScale)
                let height = MacWidgetPlacement.dockExpandedHeight(detailScale: detailScale, hoverScale: 1.8)
                for progress in stride(from: CGFloat(0), through: 1, by: 0.1) {
                    let size = CGSize(width: width, height: height)
                    let path = MacWidgetSurface.path(in: size, edge: .bottom, selectedIndex: 0, scale: 1,
                        metricCount: count, hoverScale: 1.8, detailScale: detailScale,
                        magnifications: [0: 1 + 0.8 * progress], sideExpansion: progress)
                    let top = height - (46 + (height - 46) * progress)
                    // Details and circles share a broad surface all the way to
                    // the screen edge; no thin connector or transparent seam.
                    for y in stride(from: top + 2, through: height - 0.5, by: 2) {
                        for x in [width / 2 - 60, width / 2, width / 2 + 60] {
                            XCTAssertTrue(path.contains(CGPoint(x: x, y: y)))
                        }
                    }
                    let ring = MacWidgetPlacement.dockRingFrame(in: size, index: 0, scale: 1, metricCount: count,
                        magnification: 1 + 0.8 * progress, detailScale: detailScale)
                    XCTAssertTrue(path.contains(CGPoint(x: ring.midX, y: ring.midY)))
                    XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
                }
            }
        }
    }

    @MainActor
    func testBottomSurfaceRendersClosedAndCenteredHoverDetails() async throws {
        let suite = "com.hinoshiba.daysyet.bottom.surface.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for count in [3, 6, 8] {
            var profile = UserProfile.initial
            profile.dashboardMetrics = Array(MetricKind.allCases.prefix(count))
            let store = ProfileStore(profile: profile, saveProfile: { _ in })
            let preferences = MacWidgetPreferences(defaults: defaults)
            preferences.edge = .bottom
            preferences.magnifiesOnHover = count > 3
            preferences.hoverScale = count == 6 ? 1.55 : 1.8
            preferences.detailScale = count == 8 ? 1.5 : 1
            let controller = MacWidgetController(store: store, preferences: preferences, reducesMotion: { true })
            defer { controller.closeDetails() }
            for state in ["closed", "first", "last"] {
                if state != "closed" {
                    let metric = try XCTUnwrap(state == "first"
                        ? profile.macDashboardMetrics.first : profile.macDashboardMetrics.last)
                    controller.sideHoverChanged(inside: true, metric: metric)
                    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                    while (!controller.isExpanded || controller.selectedMetric != metric), ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    XCTAssertTrue(controller.isExpanded)
                    XCTAssertEqual(controller.selectedMetric, metric)
                }
                let frame = MacWidgetPlacement.frame(in: NSRect(x: 0, y: 0, width: 1600, height: 1000),
                    edge: .bottom, position: 0.5, expanded: controller.isExpanded,
                    metricCount: count, hoverScale: controller.hoverScaleLimit, detailScale: preferences.detailScale)
                let renderer = ImageRenderer(content: MacDesktopWidgetView(store: store, preferences: preferences,
                    controller: controller).frame(width: frame.width, height: frame.height))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                let bitmap = NSBitmapImageRep(cgImage: image)
                for index in 0..<count {
                    let ring = MacWidgetPlacement.dockRingFrame(in: frame.size, index: CGFloat(index), scale: 1,
                        metricCount: count, magnification: controller.hoverMagnifications[profile.macDashboardMetrics[index]] ?? 1,
                        detailScale: preferences.detailScale)
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(ring.midX * 2), y: Int(ring.midY * 2)))
                    XCTAssertGreaterThan(color.alphaComponent, 0.99, "Magnified rings must not cut holes in the surface.")
                }
                let preview = ImageRenderer(content: MacDesktopWidgetView(store: store, preferences: preferences,
                    controller: controller).frame(width: frame.width, height: frame.height)
                    .padding(.top, 16).padding(.horizontal, 16)
                    .background(Color(red: 0.22, green: 0.26, blue: 0.34)))
                preview.scale = 2
                let attachment = XCTAttachment(image: NSImage(cgImage: try XCTUnwrap(preview.cgImage), size: .zero))
                attachment.name = "Bottom surface - \(count) circles - \(state)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
