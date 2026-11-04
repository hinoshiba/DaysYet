#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import AppKit
import XCTest
@testable import DaysYetMac

@MainActor
final class MacDockSnapshotCaptureTests: XCTestCase {
    private typealias Geometry = MacDockSnapshotGeometry

    func testUnavailableDockLaunchDateDoesNotDisableCaptureOrPermitProcessReplacement() {
        let launch = Date(timeIntervalSince1970: 100)
        for dates in [(Optional<Date>.none, Optional<Date>.none), (nil, launch), (launch, nil), (launch, launch)] {
            XCTAssertTrue(MacDockSnapshotProcessPolicy.isSameLifetime(expectedPID: 42, currentPID: 42,
                retainedProcessTerminated: false, initialLaunchDate: dates.0, currentLaunchDate: dates.1))
            // A missing timestamp must never weaken the lifetime or PID guard,
            // including the case where the original PID has been reused.
            XCTAssertFalse(MacDockSnapshotProcessPolicy.isSameLifetime(expectedPID: 42, currentPID: 42,
                retainedProcessTerminated: true, initialLaunchDate: dates.0, currentLaunchDate: dates.1))
            XCTAssertFalse(MacDockSnapshotProcessPolicy.isSameLifetime(expectedPID: 42, currentPID: 43,
                retainedProcessTerminated: false, initialLaunchDate: dates.0, currentLaunchDate: dates.1))
        }
        XCTAssertFalse(MacDockSnapshotProcessPolicy.isSameLifetime(expectedPID: 42, currentPID: 42,
            retainedProcessTerminated: false, initialLaunchDate: launch,
            currentLaunchDate: launch.addingTimeInterval(1)))
    }

    func testDockRegionIncludesTrashAndPaddingOnEverySupportedEdge() throws {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 900)
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            let bounds = dockBounds(edge: edge, screen: screen)
            let region = try XCTUnwrap(Geometry.region(bounds: bounds,
                layoutFrames: bounds.items.filter(\.isApplication).map(\.frame), edge: edge,
                screenFrame: screen, primaryScreenMaxY: 900, scale: 2))
            XCTAssertTrue(bounds.items.allSatisfy { region.frame.contains($0.frame) })
            XCTAssertTrue(screen.contains(region.frame))
            XCTAssertEqual(CGFloat(region.pixelWidth), region.frame.width * 2)
            XCTAssertEqual(CGFloat(region.pixelHeight), region.frame.height * 2)
            XCTAssertLessThanOrEqual(region.frame.width * region.frame.height, screen.width * screen.height / 4)
            switch edge {
            case .bottom:
                XCTAssertEqual(region.frame.minY, screen.minY)
                XCTAssertEqual(region.sourceRect.maxY, screen.height)
            case .left:
                XCTAssertEqual(region.frame.minX, screen.minX)
                XCTAssertEqual(region.sourceRect.minX, 0)
            case .right:
                XCTAssertEqual(region.frame.maxX, screen.maxX)
                XCTAssertEqual(region.sourceRect.maxX, screen.width)
            case .top:
                XCTFail("Unsupported edge")
            }
        }
    }

    func testSecondaryDisplayUsesDisplayLocalTopLeftSourceCoordinates() throws {
        // Display to the left and below the primary display, with fractional
        // AX bounds: these catch both the global-origin and Y-flip mistakes.
        let screen = NSRect(x: -1440, y: -300, width: 1440, height: 900)
        let bounds = dockBounds(edge: .bottom, screen: screen, fractionalOffset: 0.25)
        let region = try XCTUnwrap(Geometry.region(bounds: bounds,
            layoutFrames: bounds.items.filter(\.isApplication).map(\.frame), edge: .bottom,
            screenFrame: screen, primaryScreenMaxY: 1000, scale: 2))
        XCTAssertGreaterThanOrEqual(region.sourceRect.minX, 0)
        XCTAssertGreaterThanOrEqual(region.sourceRect.minY, 0)
        XCTAssertEqual(region.sourceRect.minX, region.frame.minX - screen.minX)
        XCTAssertEqual(region.sourceRect.minY, screen.maxY - region.frame.maxY)
        XCTAssertEqual(region.sourceRect.maxY, screen.height)
        XCTAssertEqual(region.sourceRect.minX * 2, (region.sourceRect.minX * 2).rounded())
        XCTAssertEqual(region.sourceRect.minY * 2, (region.sourceRect.minY * 2).rounded())
        XCTAssertTrue(bounds.items.allSatisfy { region.frame.contains($0.frame) })
    }

    func testFullDisplayListBoundsNeverBecomeTheCaptureRectangle() throws {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let original = dockBounds(edge: .bottom, screen: screen)
        let bounds = Geometry.DockBounds(listFrame: screen, items: original.items)
        let region = try XCTUnwrap(Geometry.region(bounds: bounds,
            layoutFrames: bounds.items.filter(\.isApplication).map(\.frame), edge: .bottom,
            screenFrame: screen, primaryScreenMaxY: 900, scale: 2))
        XCTAssertLessThan(region.frame.height, screen.height / 4)
        XCTAssertNotEqual(region.frame, screen)
    }

    func testMissingTrashDuplicateTrashAndStaleOrPartialApplicationLayoutsAreRejected() {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let original = dockBounds(edge: .bottom, screen: screen)
        let frames = original.items.filter(\.isApplication).map(\.frame)
        func region(_ items: [Geometry.Item], _ layout: [NSRect]? = nil) -> Geometry.Region? {
            Geometry.region(bounds: .init(listFrame: nil, items: items), layoutFrames: layout ?? frames,
                edge: .bottom, screenFrame: screen, primaryScreenMaxY: 900, scale: 2)
        }
        XCTAssertNil(region(original.items.filter { !$0.isTrash }))
        XCTAssertNil(region(original.items + [original.items.last!]))
        XCTAssertNil(region(original.items, Array(frames.dropLast())))
        XCTAssertNil(region(original.items, [frames[0], frames[0], frames[2]]))
        XCTAssertNil(region(original.items, frames.map { $0.offsetBy(dx: 4, dy: 0) }))
    }

    func testWrongEdgeOffscreenNonfiniteAndOversizedDockBoundsFailClosed() {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let original = dockBounds(edge: .bottom, screen: screen)
        let frames = original.items.filter(\.isApplication).map(\.frame)
        func region(_ bounds: Geometry.DockBounds = .init(listFrame: nil, items: []),
                    edge: MacWidgetEdge = .bottom, scale: CGFloat = 2) -> Geometry.Region? {
            Geometry.region(bounds: bounds, layoutFrames: frames, edge: edge,
                screenFrame: screen, primaryScreenMaxY: 900, scale: scale)
        }
        XCTAssertNil(region(original, edge: .top))
        XCTAssertNil(region(original, edge: .right))
        XCTAssertNil(region(original, scale: 0))
        XCTAssertNil(region(original, scale: .infinity))
        for frame in [NSRect(x: 0, y: 0, width: CGFloat.nan, height: 20),
                      NSRect(x: 0, y: -2, width: 20, height: 20),
                      NSRect(x: 0, y: 0, width: 500, height: 400)] {
            let item = Geometry.Item(frame: frame, isApplication: false, isTrash: false)
            XCTAssertNil(region(.init(listFrame: nil, items: original.items + [item])))
        }
        let huge = NSRect(x: 0, y: 0, width: 16_000, height: 4000)
        let largeItems = [
            Geometry.Item(frame: NSRect(x: 20, y: 2, width: 1000, height: 800), isApplication: true, isTrash: false),
            Geometry.Item(frame: NSRect(x: 14_000, y: 2, width: 1000, height: 800), isApplication: false, isTrash: true)
        ]
        XCTAssertNil(Geometry.region(bounds: .init(listFrame: nil, items: largeItems),
            layoutFrames: [largeItems[0].frame], edge: .bottom,
            screenFrame: huge, primaryScreenMaxY: 4000, scale: 2))
    }

    func testDeniedOrOutdatedRequestDoesNotEnumerateOrCapture() async {
        var permission = false
        var current = true
        var preparations = 0
        let service = MacDockSnapshotCapture(dependencies: .init(permission: { permission }, prepare: { _, _ in
            preparations += 1
            XCTFail("No metadata/SCK enumeration is authorized")
            return nil
        }))
        let denied = await service.capture(layout: layout(), isCurrent: { current })
        XCTAssertNil(denied)
        permission = true
        current = false
        let outdated = await service.capture(layout: layout(), isCurrent: { current })
        XCTAssertNil(outdated)
        XCTAssertEqual(preparations, 0)
    }

    func testRevocationAndCancellationDuringPreparationNeverCallCapture() async throws {
        for revokePermission in [true, false] {
            var permission = true
            var current = true
            var captures = 0
            let prepared = try prepared(capture: { captures += 1; return self.image(alpha: 255) })
            let service = MacDockSnapshotCapture(dependencies: .init(permission: { permission }, prepare: { _, mayContinue in
                XCTAssertTrue(mayContinue())
                await Task.yield()
                if revokePermission { permission = false } else { current = false }
                XCTAssertFalse(mayContinue())
                return prepared
            }))
            let snapshot = await service.capture(layout: layout(), isCurrent: { current })
            XCTAssertNil(snapshot)
            XCTAssertEqual(captures, 0)
        }
    }

    func testRevocationOrChangedEnvironmentAfterCaptureDiscardsImage() async throws {
        for revokePermission in [true, false] {
            var permission = true
            var environmentCurrent = true
            let prepared = try prepared(environmentIsCurrent: { environmentCurrent }, capture: {
                await Task.yield()
                if revokePermission { permission = false } else { environmentCurrent = false }
                return self.image(alpha: 255)
            })
            let service = MacDockSnapshotCapture(dependencies: .init(permission: { permission }, prepare: { _, _ in prepared }))
            let snapshot = await service.capture(layout: layout(), isCurrent: { true })
            XCTAssertNil(snapshot)
        }
    }

    func testOpaqueImageSurvivesAndUnexpectedAlphaNeverGetsFilled() async throws {
        XCTAssertNotNil(MacDockSnapshotCapture.validatedOpaqueImage(try XCTUnwrap(image(alpha: 255))))
        XCTAssertNil(MacDockSnapshotCapture.validatedOpaqueImage(try XCTUnwrap(image(alpha: 254))))
        XCTAssertNil(MacDockSnapshotCapture.validatedOpaqueImage(try XCTUnwrap(image(alpha: 0))))
        for alpha in [UInt8(255), 128] {
            let prepared = try prepared(capture: { self.image(alpha: alpha) })
            let service = MacDockSnapshotCapture(dependencies: .init(permission: { true }, prepare: { _, _ in prepared }))
            let snapshot = await service.capture(layout: layout(), isCurrent: { true })
            XCTAssertEqual(snapshot != nil, alpha == 255)
            if let snapshot {
                XCTAssertEqual(snapshot.frame, prepared.region.frame)
                XCTAssertEqual(snapshot.screenFrame, prepared.screenFrame)
                XCTAssertEqual(snapshot.displayID, prepared.displayID)
                XCTAssertEqual(snapshot.dockPID, prepared.dockPID)
                XCTAssertEqual(snapshot.edge, .bottom)
                XCTAssertEqual(snapshot.image.alphaInfo, .noneSkipLast)
            }
        }
    }

    func testWrongImageDimensionsAndWrongDockIdentityAreRejected() async throws {
        var captures = 0
        let wrongSize = try prepared(capture: { self.image(alpha: 255, width: 3) })
        let sizeService = MacDockSnapshotCapture(dependencies: .init(permission: { true }, prepare: { _, _ in wrongSize }))
        let wrongSizeResult = await sizeService.capture(layout: layout(), isCurrent: { true })
        XCTAssertNil(wrongSizeResult)
        let wrongDock = try prepared(dockPID: 999, capture: { captures += 1; return self.image(alpha: 255) })
        let identityService = MacDockSnapshotCapture(dependencies: .init(permission: { true }, prepare: { _, _ in wrongDock }))
        let wrongIdentityResult = await identityService.capture(layout: layout(), isCurrent: { true })
        XCTAssertNil(wrongIdentityResult)
        XCTAssertEqual(captures, 0)
    }

    private func dockBounds(edge: MacWidgetEdge, screen: NSRect, fractionalOffset: CGFloat = 0) -> Geometry.DockBounds {
        let items = (0..<5).map { index -> Geometry.Item in
            let tangent = CGFloat(index) * 60 + 200 + fractionalOffset
            let frame: NSRect
            switch edge {
            case .bottom, .top:
                frame = NSRect(x: screen.minX + tangent, y: screen.minY + 4, width: 48, height: 48)
            case .left:
                frame = NSRect(x: screen.minX + 4, y: screen.maxY - tangent - 48, width: 48, height: 48)
            case .right:
                frame = NSRect(x: screen.maxX - 52, y: screen.maxY - tangent - 48, width: 48, height: 48)
            }
            return Geometry.Item(frame: frame, isApplication: index < 3, isTrash: index == 4)
        }
        return .init(listFrame: nil, items: items)
    }

    private func layout() -> MacDockNativeLayout {
        .init(dockPID: 42, edge: .bottom,
            items: [.init(metric: .week, frame: NSRect(x: 10, y: 4, width: 48, height: 48))])
    }

    private func prepared(dockPID: pid_t = 42, environmentIsCurrent: @escaping @MainActor () -> Bool = { true },
                          capture: @escaping @MainActor () async -> CGImage?) throws -> MacDockSnapshotCapture.PreparedCapture {
        .init(region: .init(frame: NSRect(x: 10, y: 0, width: 2, height: 2),
                           sourceRect: NSRect(x: 10, y: 898, width: 2, height: 2), pixelWidth: 2, pixelHeight: 2),
              displayID: 7, screenFrame: NSRect(x: 0, y: 0, width: 1200, height: 900),
              dockPID: dockPID, edge: .bottom, environmentIsCurrent: environmentIsCurrent, captureImage: capture)
    }

    private func image(alpha: UInt8, width: Int = 2) -> CGImage? {
        let bytes = Data(repeating: alpha, count: width * 2 * 4)
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: width, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
#endif
