import AppKit
import XCTest
@testable import DaysYetMac

final class MacWidgetPlacementTests: XCTestCase {
    private let desktop = NSRect(x: 80, y: 40, width: 1440, height: 900)

    func testNotchClampsTopAndBottomPositions() {
        for expanded in [false, true] {
            for scale in [0.8, 1.0, 1.5] {
                let top = MacWidgetPlacement.frame(in: desktop, edge: .right, position: -1, expanded: expanded, scale: scale)
                let bottom = MacWidgetPlacement.frame(in: desktop, edge: .right, position: 2, expanded: expanded, scale: scale)

                XCTAssertEqual(top.maxY, desktop.maxY)
                XCTAssertEqual(bottom.minY, desktop.minY)
                XCTAssertTrue(desktop.contains(top))
                XCTAssertTrue(desktop.contains(bottom))
            }
        }
    }

    func testNonfinitePositionFallsBackToCenter() {
        for expanded in [false, true] {
            for position in [Double.nan, .infinity, -.infinity] {
                let notch = MacWidgetPlacement.frame(in: desktop, edge: .left, position: position, expanded: expanded)

                XCTAssertEqual(notch.midY, desktop.midY)
                XCTAssertTrue(desktop.contains(notch))
            }
        }
    }

    func testExpansionKeepsAttachedEdgeAndVerticalCenterAtEveryScale() {
        for edge in [MacWidgetEdge.left, .right] {
            for scale in [0.8, 1.0, 1.5] {
                for position in [0.0, 0.5, 1.0] {
                    let collapsed = MacWidgetPlacement.frame(in: desktop, edge: edge, position: position, expanded: false, scale: scale)
                    let expanded = MacWidgetPlacement.frame(in: desktop, edge: edge, position: position, expanded: true, scale: scale)

                    if edge == .left {
                        XCTAssertEqual(collapsed.minX, desktop.minX)
                        XCTAssertEqual(expanded.minX, collapsed.minX)
                    } else {
                        XCTAssertEqual(collapsed.maxX, desktop.maxX)
                        XCTAssertEqual(expanded.maxX, collapsed.maxX)
                    }
                    XCTAssertEqual(expanded.midY, collapsed.midY)
                    XCTAssertEqual(expanded.height, collapsed.height)
                    XCTAssertGreaterThan(expanded.width, collapsed.width)
                    XCTAssertTrue(expanded.contains(collapsed))
                    XCTAssertTrue(desktop.contains(expanded))
                }
            }
        }
    }

    func testBothStatesStayWithinSecondaryDisplayWithNegativeCoordinates() {
        let secondaryDisplay = NSRect(x: -1728, y: -260, width: 1728, height: 990)

        for edge in [MacWidgetEdge.left, .right] {
            for expanded in [false, true] {
                for position in [0.0, 0.5, 1.0] {
                    let notch = MacWidgetPlacement.frame(in: secondaryDisplay, edge: edge, position: position, expanded: expanded, scale: 1.5)

                    XCTAssertTrue(secondaryDisplay.contains(notch))
                    XCTAssertLessThanOrEqual(notch.maxX, 0)
                }
            }
        }
    }

    func testInvalidScaleUsesSafeSize() {
        let cases: [(input: Double, expected: Double)] = [
            (-3, 0.8), (0, 0.8), (4, 1.5), (.nan, 1), (.infinity, 1), (-.infinity, 1)
        ]
        for scale in cases {
            let notch = MacWidgetPlacement.frame(in: desktop, edge: .right, position: 0.5, expanded: true, scale: scale.input)

            XCTAssertEqual(MacWidgetPlacement.clampedScale(scale.input), scale.expected)
            XCTAssertEqual(notch.width, 204 * scale.expected, accuracy: 0.001)
            XCTAssertEqual(notch.height, 212 * scale.expected, accuracy: 0.001)
            XCTAssertEqual(notch.midY, desktop.midY)
            XCTAssertEqual(notch.maxX, desktop.maxX)
        }
    }

    func testTinyDisplayContainsBothStatesAtLargestScale() {
        let tinyDisplay = NSRect(x: -100, y: 35, width: 40, height: 120)

        for edge in [MacWidgetEdge.left, .right] {
            for expanded in [false, true] {
                let notch = MacWidgetPlacement.frame(in: tinyDisplay, edge: edge, position: 0.8, expanded: expanded, scale: 1.5)

                XCTAssertEqual(notch, tinyDisplay)
            }
        }
    }

    func testTopUsesPhysicalScreenEdgeAboveTheMenuBar() {
        let physical = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 48, width: 1512, height: 896)
        let info = MacTopNotchInfo(cameraInset: 38, notchWidth: 180, centerX: 756)

        for scale in [0.8, 1.0, 1.5] {
            let idle = MacWidgetPlacement.frame(in: visible, edge: .top, position: 0, expanded: false,
                                                scale: scale, screenFrame: physical, topInfo: info)
            let open = MacWidgetPlacement.frame(in: visible, edge: .top, position: 1, expanded: true,
                                                scale: scale, screenFrame: physical, topInfo: info)

            XCTAssertEqual(idle.maxY, physical.maxY)
            XCTAssertGreaterThan(idle.maxY, visible.maxY)
            XCTAssertEqual(open.maxY, idle.maxY)
            XCTAssertEqual(idle.midX, info.centerX)
            XCTAssertEqual(open.midX, idle.midX)
            XCTAssertEqual(idle.height - 8 * scale, 38, accuracy: 0.001)
            XCTAssertEqual(open.height - 74 * scale, 38, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(idle.width, info.notchWidth + 24 * scale)
            XCTAssertTrue(physical.contains(open))
        }
    }

    func testTopWithoutCameraUsesCenteredFallback() {
        let physical = NSRect(x: -1920, y: -180, width: 1920, height: 1080)
        let visible = NSRect(x: -1920, y: -132, width: 1920, height: 1008)
        let info = MacTopNotchInfo.resolve(screenFrame: physical, topInset: 0, leftArea: .zero, rightArea: .zero)
        let idle = MacWidgetPlacement.frame(in: visible, edge: .top, position: 0.3, expanded: false,
                                            screenFrame: physical, topInfo: info)

        XCTAssertEqual(info.cameraInset, 0)
        XCTAssertEqual(info.notchWidth, 0)
        XCTAssertEqual(idle.midX, physical.midX)
        XCTAssertEqual(idle.maxY, physical.maxY)
        XCTAssertEqual(idle.size, NSSize(width: 174, height: 8))
    }

    func testCameraCenterComesFromAsymmetricUnobscuredAreas() {
        let physical = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
        let left = NSRect(x: -1600, y: 1082, width: 640, height: 38)
        let right = NSRect(x: -780, y: 1082, width: 780, height: 38)
        let info = MacTopNotchInfo.resolve(screenFrame: physical, topInset: 38, leftArea: left, rightArea: right)

        XCTAssertEqual(info.notchWidth, 180)
        XCTAssertEqual(info.centerX, -870)
        XCTAssertNotEqual(info.centerX, physical.midX)
        for expanded in [false, true] {
            let frame = MacWidgetPlacement.frame(in: physical.insetBy(dx: 0, dy: 38), edge: .top,
                                                  position: 0.5, expanded: expanded, screenFrame: physical, topInfo: info)
            XCTAssertEqual(frame.midX, -870)
            XCTAssertEqual(frame.maxY, 1120)
            XCTAssertTrue(physical.contains(frame))
        }
    }

    func testUnknownCameraGeometryUsesSafeCenteredInset() {
        let physical = NSRect(x: 200, y: 300, width: 1200, height: 800)
        let info = MacTopNotchInfo.resolve(screenFrame: physical, topInset: 32, leftArea: .zero, rightArea: .zero)

        XCTAssertEqual(info.cameraInset, 32)
        XCTAssertEqual(info.centerX, physical.midX)
        XCTAssertEqual(info.notchWidth, 0)
    }

    func testTopClampsInsideSmallOrOffsetDisplay() {
        let physical = NSRect(x: -120, y: -60, width: 120, height: 90)
        let info = MacTopNotchInfo(cameraInset: 38, notchWidth: 180, centerX: -110)
        let frame = MacWidgetPlacement.frame(in: physical, edge: .top, position: 1, expanded: true,
                                              scale: 1.5, screenFrame: physical, topInfo: info)
        XCTAssertEqual(frame, physical)
    }

    func testSideSurfaceIncludesPeekTextAndExcludesTransparentMargins() {
        for edge in [MacWidgetEdge.left, .right] {
            for index in [CGFloat(0), 0.25, 0.5, 1, 1.5, 1.75, 2] {
                for scale in [0.8, 1.0, 1.1, 1.5] {
                    let size = CGSize(width: 204 * scale, height: 212 * scale)
                    let detail = MacWidgetPlacement.sideDetailFrame(in: size, edge: edge,
                        selectedIndex: index, scale: scale)
                    let path = MacWidgetSurface.path(in: size, edge: edge, selectedIndex: index, scale: scale)
                    for x in stride(from: detail.minX, through: detail.maxX, by: 2 * scale) {
                        XCTAssertTrue(path.contains(CGPoint(x: x, y: detail.minY)))
                        XCTAssertTrue(path.contains(CGPoint(x: x, y: detail.maxY)))
                    }
                    for y in stride(from: detail.minY, through: detail.maxY, by: 2 * scale) {
                        XCTAssertTrue(path.contains(CGPoint(x: detail.minX, y: y)))
                        XCTAssertTrue(path.contains(CGPoint(x: detail.maxX, y: y)))
                    }
                    let center = 56 + 50 * index
                    for point in [CGPoint(x: 2, y: center - 38), CGPoint(x: 2, y: center + 38),
                                  CGPoint(x: 80, y: center - 50), CGPoint(x: 80, y: center + 50)] {
                        let x = edge == .right ? point.x : 204 - point.x
                        XCTAssertFalse(path.contains(CGPoint(x: x * scale, y: point.y * scale)))
                    }
                }
            }
        }
    }

    func testTopCameraClickRegionExcludesSurroundingMenus() {
        let size = CGSize(width: 280, height: 112)
        XCTAssertTrue(MacWidgetSurface.contains(CGPoint(x: 140, y: 20), in: size, edge: .top,
                                                  selectedIndex: 0, scale: 1, topCameraInset: 38))
        XCTAssertFalse(MacWidgetSurface.contains(CGPoint(x: 15, y: 20), in: size, edge: .top,
                                                  selectedIndex: 0, scale: 1, topCameraInset: 38))
        XCTAssertTrue(MacWidgetSurface.contains(CGPoint(x: 140, y: 60), in: size, edge: .top,
                                                 selectedIndex: 0, scale: 1, topCameraInset: 38))
        XCTAssertFalse(MacWidgetSurface.contains(CGPoint(x: 2, y: 100), in: size, edge: .top,
                                                  selectedIndex: 0, scale: 1, topCameraInset: 38))
    }

    func testTopExpansionWidensOnlyBelowTheCameraBand() {
        for scale in [0.8, 1.0, 1.5] {
            let inset: CGFloat = 32
            let notchWidth: CGFloat = 185
            let size = CGSize(width: 280 * scale, height: inset + 74 * scale)
            let capWidth = max(174 * scale, notchWidth + 24 * scale)
            let capLeft = (size.width - capWidth) / 2
            let path = MacWidgetSurface.path(in: size, edge: .top, selectedIndex: 0, scale: scale,
                                              topCameraInset: inset, topNotchWidth: notchWidth)

            XCTAssertFalse(path.contains(CGPoint(x: capLeft - 1, y: inset / 2)))
            XCTAssertFalse(path.contains(CGPoint(x: size.width - capLeft + 1, y: inset / 2)))
            XCTAssertTrue(path.contains(CGPoint(x: size.width / 2, y: inset / 2)))
            XCTAssertTrue(MacWidgetSurface.contains(CGPoint(x: 20 * scale, y: inset + 45 * scale),
                in: size, edge: .top, selectedIndex: 0, scale: scale,
                topCameraInset: inset, topNotchWidth: notchWidth))
        }
    }

    func testSideDetailAndSurfaceFollowSelectedRowContinuously() {
        for edge in [MacWidgetEdge.left, .right] {
            for scale in [0.8, 1.0, 1.5] {
                let size = CGSize(width: 204 * scale, height: 212 * scale)
                for index in [CGFloat(0), 0.25, 0.5, 1, 1.5, 1.75, 2] {
                    let detail = MacWidgetPlacement.sideDetailFrame(in: size, edge: edge,
                        selectedIndex: index, scale: scale)
                    XCTAssertEqual(detail.midY, (56 + 50 * index) * scale, accuracy: 0.0001)
                    XCTAssertEqual(detail.width, 124 * scale, accuracy: 0.0001)
                    XCTAssertEqual(detail.height, 52 * scale, accuracy: 0.0001)
                    XCTAssertEqual(detail.minX, (edge == .right ? 20 : 60) * scale, accuracy: 0.0001)
                    let path = MacWidgetSurface.path(in: size, edge: edge, selectedIndex: index, scale: scale)
                    let outerX = (edge == .right ? 2 : 202) * scale
                    XCTAssertTrue(path.contains(CGPoint(x: outerX, y: detail.midY)))
                    XCTAssertFalse(path.contains(CGPoint(x: outerX, y: detail.midY - 42 * scale)))
                    XCTAssertFalse(path.contains(CGPoint(x: outerX, y: detail.midY + 42 * scale)))
                }
            }
        }
    }

    func testSideOpeningGrowsWithoutMovingTheRailOrExceedingTheWindow() {
        for edge in [MacWidgetEdge.left, .right] {
            for scale in [0.8, 1.0, 1.5] {
                for index in [CGFloat(0), 0.5, 1, 1.5, 2] {
                    for width in [46.0, 46.001, 47, 86, 125, 164, 204] {
                        let size = CGSize(width: width * scale, height: 212 * scale)
                        let path = MacWidgetSurface.path(in: size, edge: edge, selectedIndex: index, scale: scale)
                        XCTAssertGreaterThanOrEqual(path.boundingBoxOfPath.minX, -0.0001)
                        XCTAssertLessThanOrEqual(path.boundingBoxOfPath.maxX, size.width + 0.0001)
                        XCTAssertGreaterThanOrEqual(path.boundingBoxOfPath.minY, -0.0001)
                        XCTAssertLessThanOrEqual(path.boundingBoxOfPath.maxY, size.height + 0.0001)
                        var previousY: CGFloat = 0
                        path.applyWithBlock { elementPointer in
                            let element = elementPointer.pointee
                            let count: Int
                            switch element.type {
                            case .moveToPoint, .addLineToPoint: count = 1
                            case .addQuadCurveToPoint: count = 2
                            case .addCurveToPoint: count = 3
                            case .closeSubpath: count = 0
                            @unknown default: count = 0
                            }
                            for offset in 0..<count {
                                let y = element.points[offset].y
                                XCTAssertGreaterThanOrEqual(y + 0.0001, previousY)
                                previousY = y
                            }
                        }
                        for center in MacWidgetPlacement.ringCenters {
                            for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 8) {
                                // Include the 32-point ring and its outer stroke.
                                let depth = 23 + 16.75 * cos(angle)
                                let x = edge == .right ? width - depth : depth
                                XCTAssertTrue(path.contains(CGPoint(x: x * scale,
                                    y: (center + 16.75 * sin(angle)) * scale)))
                            }
                        }
                    }
                }
            }
        }
    }

    func testClosedTopThicknessScalesWhileCameraHeightStaysPhysical() {
        for inset in [CGFloat(1), 8, 16, 24, 32, 38, 64] {
            let info = MacTopNotchInfo(cameraInset: inset, notchWidth: 185, centerX: desktop.midX)
            var previousHeight = inset
            for scale in [0.8, 1.0, 1.5] {
                let frame = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: false,
                    scale: scale, screenFrame: desktop, topInfo: info)
                XCTAssertEqual(frame.height, MacWidgetPlacement.topClosedHeight(cameraInset: inset, scale: scale), accuracy: 0.0001)
                XCTAssertEqual(frame.height - 8 * scale, inset, accuracy: 0.0001)
                XCTAssertGreaterThan(frame.height, previousHeight)
                XCTAssertEqual(frame.maxY, desktop.maxY)
                previousHeight = frame.height
            }
        }
        XCTAssertEqual(MacWidgetPlacement.topClosedHeight(cameraInset: 32), 40)
        for scale in [0.8, 1.0, 1.5] {
            let frame = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: false, scale: scale)
            XCTAssertEqual(frame.height, 8 * scale)
            XCTAssertEqual(MacWidgetPlacement.topExpandedHeight(cameraInset: 32, scale: scale), 32 + 74 * scale)
        }
        for inset in [CGFloat(-1), .nan, .infinity] {
            XCTAssertEqual(MacWidgetPlacement.topClosedHeight(cameraInset: inset), 8)
        }
        for (scale, expected) in [(Double.nan, 8.0), (.infinity, 8), (-1, 6.4), (3, 12)] {
            XCTAssertEqual(MacWidgetPlacement.topClosedHeight(cameraInset: 32, scale: scale) - 32,
                           expected, accuracy: 0.0001)
        }
    }

    func testTopProgressLineStaysFixedWhileDetailsExpand() {
        for inset in [CGFloat(0), 16, 32] {
            for scale in [0.8, 1.0, 1.5] {
                let notchWidth: CGFloat = inset == 0 ? 0 : 185
                let info = MacTopNotchInfo(cameraInset: inset, notchWidth: notchWidth, centerX: desktop.midX)
                let idle = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: false,
                    scale: scale, screenFrame: desktop, topInfo: info)
                let open = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: true,
                    scale: scale, screenFrame: desktop, topInfo: info)
                let idleLine = MacWidgetSurface.topProgressFrame(in: idle.size, scale: scale,
                    topCameraInset: inset, topNotchWidth: notchWidth)
                let openLine = MacWidgetSurface.topProgressFrame(in: open.size, scale: scale,
                    topCameraInset: inset, topNotchWidth: notchWidth)

                XCTAssertEqual(idleLine.size, openLine.size)
                XCTAssertEqual(idle.minX + idleLine.minX, open.minX + openLine.minX, accuracy: 0.0001)
                XCTAssertEqual(idleLine.minY, inset)
                XCTAssertEqual(idleLine.height, 8 * scale, accuracy: 0.0001)
                XCTAssertEqual(openLine.minY, idleLine.minY)
                XCTAssertLessThanOrEqual(idleLine.maxY, idle.height)
                for index in 0..<3 {
                    let point = CGPoint(x: idleLine.minX + idleLine.width * (CGFloat(index) + 0.5) / 3,
                                        y: idleLine.midY)
                    XCTAssertTrue(MacWidgetSurface.contains(point, in: idle.size, edge: .top,
                        selectedIndex: CGFloat(index), scale: scale, topCameraInset: inset, topNotchWidth: notchWidth))
                }
            }
        }
    }

    func testTopDetailRectangleStaysInsideShouldersAndRoundedBottom() {
        for scale in [0.8, 1.0, 1.1, 1.5] {
            for inset in [CGFloat(0), 32, 38] {
                for notchWidth in [CGFloat(0), 185] {
                    let info = MacTopNotchInfo(cameraInset: inset, notchWidth: notchWidth, centerX: desktop.midX)
                    let frame = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: true,
                        scale: scale, screenFrame: desktop, topInfo: info)
                    let detail = MacWidgetPlacement.topDetailFrame(in: frame.size, cameraInset: inset, scale: scale)
                    let surface = MacWidgetSurface.path(in: frame.size, edge: .top, selectedIndex: 0,
                        scale: scale, topCameraInset: inset, topNotchWidth: notchWidth)
                    let condition = "scale=\(scale), camera=\(inset), notch=\(notchWidth)"

                    XCTAssertEqual(detail.width, 240 * scale, accuracy: 0.0001, condition)
                    XCTAssertEqual(detail.height, 52 * scale, accuracy: 0.0001, condition)
                    XCTAssertEqual(detail.midX, frame.width / 2, accuracy: 0.0001, condition)
                    XCTAssertGreaterThan(detail.minY, inset, condition)
                    XCTAssertLessThan(detail.maxY, frame.height, condition)

                    // Sample all four edges, including every corner, at half
                    // a logical point. A wide percentage header previously
                    // crossed the shoulders even though its center was inside.
                    for step in 0...480 {
                        let x = detail.minX + detail.width * CGFloat(step) / 480
                        for y in [detail.minY, detail.maxY] {
                            XCTAssertTrue(surface.contains(CGPoint(x: x, y: y)), condition)
                        }
                    }
                    for step in 0...104 {
                        let y = detail.minY + detail.height * CGFloat(step) / 104
                        for x in [detail.minX, detail.maxX] {
                            XCTAssertTrue(surface.contains(CGPoint(x: x, y: y)), condition)
                        }
                    }
                }
            }
        }
    }

    func testTopProximityMapsSegmentsWithoutAcceptingTransparentClicks() {
        for inset in [CGFloat(0), 32] {
            for scale in [0.8, 1.0, 1.5] {
                let notchWidth: CGFloat = inset == 0 ? 0 : 185
                let info = MacTopNotchInfo(cameraInset: inset, notchWidth: notchWidth, centerX: desktop.midX)
                let frame = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: false,
                    scale: scale, screenFrame: desktop, topInfo: info)
                let line = MacWidgetSurface.topProgressFrame(in: frame.size, scale: scale,
                    topCameraInset: inset, topNotchWidth: notchWidth)
                for index in 0..<3 {
                    let x = line.minX + line.width * (CGFloat(index) + 0.5) / 3
                    let near = CGPoint(x: x, y: frame.height + 6)
                    let direct = CGPoint(x: x, y: line.midY)
                    XCTAssertEqual(MacWidgetSurface.topHoverIndex(at: near, in: frame.size, scale: scale,
                        topCameraInset: inset, topNotchWidth: notchWidth, proximity: true), index)
                    XCTAssertNil(MacWidgetSurface.topHoverIndex(at: near, in: frame.size, scale: scale,
                        topCameraInset: inset, topNotchWidth: notchWidth, proximity: false))
                    XCTAssertFalse(MacWidgetSurface.contains(near, in: frame.size, edge: .top,
                        selectedIndex: CGFloat(index), scale: scale, topCameraInset: inset, topNotchWidth: notchWidth))
                    XCTAssertEqual(MacWidgetSurface.topHoverIndex(at: direct, in: frame.size, scale: scale,
                        topCameraInset: inset, topNotchWidth: notchWidth, proximity: false), index)
                }
                for point in [CGPoint(x: line.minX - 1, y: frame.height + 2),
                              CGPoint(x: line.midX, y: frame.height + 8.01),
                              CGPoint(x: line.midX, y: max(0, line.minY - 16) - 0.01)] {
                    XCTAssertNil(MacWidgetSurface.topHoverIndex(at: point, in: frame.size, scale: scale,
                        topCameraInset: inset, topNotchWidth: notchWidth, proximity: true))
                }
            }
        }
    }

    func testTopSegmentsCanBeSelectedAboveTheBarsBeforeAndAfterExpansion() {
        for inset in [CGFloat(0), 8, 32, 38] {
            for scale in [0.8, 1.0, 1.5] {
                for expanded in [false, true] {
                    let notchWidth: CGFloat = inset == 0 ? 0 : 185
                    let info = MacTopNotchInfo(cameraInset: inset, notchWidth: notchWidth, centerX: desktop.midX)
                    let frame = MacWidgetPlacement.frame(in: desktop, edge: .top, position: 0, expanded: expanded,
                        scale: scale, screenFrame: desktop, topInfo: info)
                    let line = MacWidgetSurface.topProgressFrame(in: frame.size, scale: scale,
                        topCameraInset: inset, topNotchWidth: notchWidth)
                    let upperY = max(0, inset - 16)
                    for index in 0..<3 {
                        let x = line.minX + line.width * (CGFloat(index) + 0.5) / 3
                        for y in [upperY, (upperY + inset) / 2, inset] {
                            XCTAssertEqual(MacWidgetSurface.topHoverIndex(at: CGPoint(x: x, y: y),
                                in: frame.size, scale: scale, topCameraInset: inset,
                                topNotchWidth: notchWidth, proximity: !expanded), index)
                        }
                    }
                    for point in [CGPoint(x: line.minX - 0.01, y: upperY),
                                  CGPoint(x: line.maxX + 0.01, y: upperY),
                                  CGPoint(x: line.midX, y: upperY - 0.01)] {
                        XCTAssertNil(MacWidgetSurface.topHoverIndex(at: point, in: frame.size, scale: scale,
                            topCameraInset: inset, topNotchWidth: notchWidth, proximity: !expanded))
                    }
                }
            }
        }
    }

    func testCameraHoverKeepsItsExtentAndSelectsSegmentsOnlyNearTheBars() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let info = MacTopNotchInfo(cameraInset: 32, notchWidth: 185, centerX: 755.5)
        for scale in [0.8, 1.0, 1.5] {
            for expanded in [false, true] {
                let frame = MacWidgetPlacement.frame(in: screen, edge: .top, position: 0, expanded: expanded,
                    scale: scale, screenFrame: screen, topInfo: info)
                let region = MacWidgetSurface.topCameraHoverFrame(in: frame.size, scale: scale,
                    topCameraInset: info.cameraInset, topNotchWidth: info.notchWidth)
                XCTAssertEqual(region.size, CGSize(width: 185, height: 32))
                XCTAssertEqual(frame.minX + region.minX, 663, accuracy: 0.0001)
                XCTAssertEqual(frame.minX + region.maxX, 848, accuracy: 0.0001)
                for x in [region.minX + 0.1, region.midX, region.maxX - 0.1] {
                    for y in [CGFloat(0.1), 16, 31.9] {
                        let point = CGPoint(x: x, y: y)
                        XCTAssertTrue(region.contains(point))
                        let expectedIndex: Int? = x == region.midX && y >= 16 ? 1 : nil
                        XCTAssertEqual(MacWidgetSurface.topHoverIndex(at: point, in: frame.size, scale: scale,
                            topCameraInset: info.cameraInset, topNotchWidth: info.notchWidth, proximity: !expanded), expectedIndex)
                        XCTAssertTrue(MacWidgetSurface.contains(point, in: frame.size, edge: .top,
                            selectedIndex: 0, scale: scale, topCameraInset: info.cameraInset, topNotchWidth: info.notchWidth))
                    }
                }
                for point in [CGPoint(x: region.minX - 0.1, y: 16), CGPoint(x: region.maxX + 0.1, y: 16),
                              CGPoint(x: region.midX, y: -0.1), CGPoint(x: region.midX, y: 32.1)] {
                    XCTAssertFalse(region.contains(point))
                }
            }
        }
    }

    func testUnknownCameraHoverUsesOnlySafeStemAndNoCameraCreatesNoRegion() {
        for scale in [0.8, 1.0, 1.5] {
            let size = CGSize(width: 280 * scale, height: 32 + 74 * scale)
            let region = MacWidgetSurface.topCameraHoverFrame(in: size, scale: scale,
                topCameraInset: 32, topNotchWidth: 0)
            XCTAssertEqual(region.width, 150 * scale, accuracy: 0.0001)
            XCTAssertEqual(region.midX, size.width / 2)
            XCTAssertEqual(region.height, 32)
            XCTAssertFalse(region.contains(CGPoint(x: 1, y: 16)))
            XCTAssertFalse(region.contains(CGPoint(x: size.width - 1, y: 16)))
            for inset in [CGFloat(0), -1, .nan, .infinity] {
                XCTAssertTrue(MacWidgetSurface.topCameraHoverFrame(in: size, scale: scale,
                    topCameraInset: inset, topNotchWidth: 185).isNull)
            }
        }
        let tiny = MacWidgetSurface.topCameraHoverFrame(in: CGSize(width: 40, height: 20), scale: 1,
            topCameraInset: 32, topNotchWidth: 0)
        XCTAssertEqual(tiny, CGRect(x: 8, y: 0, width: 24, height: 20))
    }

    func testPointerCanMoveFromCameraIntoExpandedDetailsWithoutLeavingHoverSurface() {
        for scale in [0.8, 1.0, 1.5] {
            let size = CGSize(width: 280 * scale, height: 32 + 74 * scale)
            let camera = MacWidgetSurface.topCameraHoverFrame(in: size, scale: scale,
                topCameraInset: 32, topNotchWidth: 185)
            for y in stride(from: 0.5, through: 32 + 40 * scale, by: 0.5) {
                let point = CGPoint(x: size.width / 2, y: y)
                let inDetailSurface = MacWidgetSurface.contains(point, in: size, edge: .top,
                    selectedIndex: 0, scale: scale, topCameraInset: 32, topNotchWidth: 185)
                XCTAssertTrue(camera.contains(point) || inDetailSurface)
            }
        }
    }

    func testSideExpansionPreservesAttachmentShoulders() {
        for edge in [MacWidgetEdge.left, .right] {
            for scale in [0.8, 1.0, 1.5] {
                let collapsed = CGSize(width: 46 * scale, height: 212 * scale)
                let expanded = CGSize(width: 204 * scale, height: 212 * scale)
                for y in [CGFloat(0.5), 4, 10, 16, 196, 202, 208, 211.5] {
                    for depth in [CGFloat(2), 8, 16, 28, 40] {
                        let idleX = edge == .right ? 46 - depth : depth
                        let openX = edge == .right ? 204 - depth : depth
                        let idleInside = MacWidgetSurface.contains(CGPoint(x: idleX * scale, y: y * scale),
                            in: collapsed, edge: edge, selectedIndex: 0, scale: scale)
                        for row in [CGFloat(0), 0.5, 1, 1.5, 2] {
                            let otherIdleInside = MacWidgetSurface.contains(CGPoint(x: idleX * scale, y: y * scale),
                                in: collapsed, edge: edge, selectedIndex: row, scale: scale)
                            XCTAssertEqual(otherIdleInside, idleInside)
                            let center = 56 + 50 * row
                            if y < center - 54 || y > center + 54 {
                                let openInside = MacWidgetSurface.contains(CGPoint(x: openX * scale, y: y * scale),
                                    in: expanded, edge: edge, selectedIndex: row, scale: scale)
                                XCTAssertEqual(openInside, idleInside)
                            }
                        }
                    }
                }
            }
        }
    }
}

final class MacWidgetPreferencesTests: XCTestCase {
    @MainActor
    func testPreferencesRestoreAfterRelaunch() throws {
        try withDefaults { defaults in
            let preferences = MacWidgetPreferences(defaults: defaults)
            preferences.isVisible = false
            preferences.edge = .top
            preferences.verticalPosition = 0.8
            preferences.displayID = "secondary-display"
            preferences.keepDetailsOpen = true
            preferences.scale = 1.35

            let restored = MacWidgetPreferences(defaults: defaults)

            XCTAssertFalse(restored.isVisible)
            XCTAssertEqual(restored.edge, .top)
            XCTAssertEqual(restored.verticalPosition, 0.8)
            XCTAssertEqual(restored.displayID, "secondary-display")
            XCTAssertTrue(restored.keepDetailsOpen)
            XCTAssertEqual(restored.scale, 1.35)
        }
    }

    @MainActor
    func testStoredScaleUsesDefaultAndBounds() throws {
        try withDefaults { defaults in
            XCTAssertEqual(MacWidgetPreferences(defaults: defaults).scale, 1)
            let cases: [(input: Double, expected: Double)] = [
                (-1, 0.8), (2, 1.5), (.nan, 1), (.infinity, 1)
            ]
            for scale in cases {
                defaults.set(scale.input, forKey: "mac-widget-scale")
                XCTAssertEqual(MacWidgetPreferences(defaults: defaults).scale, scale.expected)
            }
        }
    }

    @MainActor
    func testInvalidStoredPositionAndEdgeUseSafeValues() throws {
        try withDefaults { defaults in
            defaults.set("unknown", forKey: "mac-widget-edge")
            defaults.set(-5, forKey: "mac-widget-position")
            let negativePosition = MacWidgetPreferences(defaults: defaults)

            XCTAssertEqual(negativePosition.edge, .right)
            XCTAssertEqual(negativePosition.verticalPosition, 0)

            defaults.set(5, forKey: "mac-widget-position")
            XCTAssertEqual(MacWidgetPreferences(defaults: defaults).verticalPosition, 1)

            defaults.set(Double.nan, forKey: "mac-widget-position")
            XCTAssertEqual(MacWidgetPreferences(defaults: defaults).verticalPosition, 0.5)
        }
    }

    @MainActor
    func testResetRestoresDefaultsWithoutErasingOtherAppSettings() throws {
        try withDefaults { defaults in
            defaults.set("preserve", forKey: "unrelated-setting")
            let preferences = MacWidgetPreferences(defaults: defaults)
            preferences.isVisible = false
            preferences.edge = .left
            preferences.verticalPosition = 1
            preferences.displayID = "secondary-display"
            preferences.keepDetailsOpen = true
            preferences.scale = 1.5

            preferences.reset()
            let restored = MacWidgetPreferences(defaults: defaults)

            for result in [preferences, restored] {
                XCTAssertTrue(result.isVisible)
                XCTAssertEqual(result.edge, .right)
                XCTAssertEqual(result.verticalPosition, 0.5)
                XCTAssertEqual(result.displayID, "")
                XCTAssertFalse(result.keepDetailsOpen)
                XCTAssertEqual(result.scale, 1)
            }
            XCTAssertNil(defaults.object(forKey: "mac-widget-position"))
            XCTAssertNil(defaults.object(forKey: "mac-widget-scale"))
            XCTAssertEqual(defaults.string(forKey: "unrelated-setting"), "preserve")
        }
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "com.hinoshiba.daysyet.mac.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
