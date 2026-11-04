#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import AppKit
import XCTest
@testable import DaysYetMac

final class MacDockSnapshotShieldTests: XCTestCase {
    private let screen = NSRect(x: -1200, y: 100, width: 1200, height: 900)

    func testOnlyBoundedNativeScaleDockRegionsAreAccepted() {
        for (edge, frame) in [
            (MacWidgetEdge.bottom, NSRect(x: -1100, y: 100, width: 900, height: 100)),
            (.left, NSRect(x: -1200, y: 200, width: 100, height: 700)),
            (.right, NSRect(x: -100, y: 200, width: 100, height: 700))
        ] {
            XCTAssertTrue(MacDockSnapshotShieldPolicy.valid(frame: frame, screen: screen, edge: edge,
                pixelWidth: Int(frame.width * 2), pixelHeight: Int(frame.height * 2), scale: 2))
        }
        let bottom = NSRect(x: -1100, y: 100, width: 900, height: 100)
        for invalid in [screen, bottom.offsetBy(dx: -200, dy: 0), bottom.offsetBy(dx: 0, dy: 400),
                        NSRect(x: -1100, y: 100, width: CGFloat.nan, height: 100), .zero] {
            XCTAssertFalse(MacDockSnapshotShieldPolicy.valid(frame: invalid, screen: screen, edge: .bottom,
                pixelWidth: 1800, pixelHeight: 200, scale: 2))
        }
        XCTAssertFalse(MacDockSnapshotShieldPolicy.valid(frame: bottom, screen: screen, edge: .top,
            pixelWidth: 1800, pixelHeight: 200, scale: 2))
        XCTAssertFalse(MacDockSnapshotShieldPolicy.valid(frame: bottom, screen: screen, edge: .bottom,
            pixelWidth: 900, pixelHeight: 100, scale: 2))
        XCTAssertFalse(MacDockSnapshotShieldPolicy.valid(frame: bottom, screen: screen, edge: .bottom,
            pixelWidth: Int.max, pixelHeight: Int.max, scale: 2))
        XCTAssertFalse(MacDockSnapshotShieldPolicy.valid(frame: bottom, screen: screen, edge: .bottom,
            pixelWidth: 1800, pixelHeight: 200, scale: .infinity))
    }

    func testCapturedImageHasAnEightSecondDeadlineAndRevealIsBounded() {
        var lifetime = MacDockSnapshotShieldLifetime()
        lifetime.begin(now: 10)
        XCTAssertFalse(lifetime.expired(now: 17.999))
        XCTAssertTrue(lifetime.expired(now: 18))
        XCTAssertTrue(lifetime.expired(now: 9))
        XCTAssertTrue(lifetime.expired(now: .nan))
        XCTAssertEqual(MacDockSnapshotShieldPolicy.revealDuration(0.12), 0.12)
        XCTAssertEqual(MacDockSnapshotShieldPolicy.revealDuration(30), 0.25)
        for invalid in [-1, TimeInterval.infinity, .nan] {
            XCTAssertEqual(MacDockSnapshotShieldPolicy.revealDuration(invalid), 0)
        }
    }

    func testOldRevealCannotDismissAReplacementOrAButtonDrain() throws {
        var lifetime = MacDockSnapshotShieldLifetime()
        lifetime.begin(now: 1)
        let old = try XCTUnwrap(lifetime.beginReveal())
        XCTAssertTrue(lifetime.canReveal(old))
        lifetime.begin(now: 2)
        XCTAssertFalse(lifetime.canReveal(old))
        let current = try XCTUnwrap(lifetime.beginReveal())
        lifetime.press(0)
        XCTAssertFalse(lifetime.dismiss(hardwareButtons: 1, pointerInside: true))
        XCTAssertFalse(lifetime.canReveal(current))
        XCTAssertFalse(lifetime.hasImage)
        XCTAssertEqual(lifetime.phase, .draining)
    }

    func testCancelReleasesPixelsButConsumesTheWholeOwnedMouseSequence() {
        var lifetime = MacDockSnapshotShieldLifetime()
        lifetime.begin(now: 1)
        lifetime.press(0)
        lifetime.press(2)
        XCTAssertTrue(lifetime.cancelOnce())
        XCTAssertFalse(lifetime.cancelOnce())
        XCTAssertFalse(lifetime.dismiss(hardwareButtons: 5, pointerInside: true))
        XCTAssertFalse(lifetime.hasImage)
        XCTAssertFalse(lifetime.release(0))
        XCTAssertEqual(lifetime.phase, .draining)
        XCTAssertTrue(lifetime.release(2))
        XCTAssertEqual(lifetime.phase, .hidden)
    }

    func testLocalMonitorDismissalBeforePanelMouseDownStillProtectsItsMouseUp() {
        var lifetime = MacDockSnapshotShieldLifetime()
        lifetime.begin(now: 1)
        // The application's monitor may run before the panel sees this press.
        XCTAssertFalse(lifetime.dismiss(hardwareButtons: 2, pointerInside: true))
        XCTAssertEqual(lifetime.pressedButtons, [1])
        XCTAssertTrue(lifetime.release(1))
        lifetime.begin(now: 2)
        XCTAssertTrue(lifetime.dismiss(hardwareButtons: 2, pointerInside: false),
            "An outside click must not leave a new input shield behind.")
    }

    func testHardwareReleaseDrainsASequenceWhoseFinalEventWasNotDelivered() {
        var lifetime = MacDockSnapshotShieldLifetime()
        lifetime.begin(now: 1)
        lifetime.press(0)
        XCTAssertFalse(lifetime.dismiss(hardwareButtons: 1, pointerInside: false))
        XCTAssertFalse(lifetime.pollRelease(hardwareButtons: 1))
        XCTAssertTrue(lifetime.pollRelease(hardwareButtons: 0))
        XCTAssertEqual(lifetime.phase, .hidden)
        XCTAssertFalse(lifetime.hasImage)
    }

    func testNativeScaleDrawingCoversEveryPixelAndClearingReleasesTheBackingImage() throws {
        let image = try opaqueBlueImage(width: 8, height: 6)
        let context = try bitmapContext(width: 8, height: 6)
        context.scaleBy(x: 2, y: 2)
        let bounds = CGRect(x: 0, y: 0, width: 4, height: 3)
        MacDockSnapshotShieldRendering.draw(image, in: bounds, context: context, opacity: 1)
        let covered = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        for y in 0..<covered.pixelsHigh {
            for x in 0..<covered.pixelsWide {
                let color = try XCTUnwrap(covered.colorAt(x: x, y: y))
                XCTAssertEqual(color.alphaComponent, 1)
                XCTAssertGreaterThan(color.blueComponent, 0.99)
            }
        }
        MacDockSnapshotShieldRendering.draw(nil, in: bounds, context: context, opacity: 0)
        let cleared = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        for y in 0..<cleared.pixelsHigh {
            for x in 0..<cleared.pixelsWide {
                XCTAssertEqual(try XCTUnwrap(cleared.colorAt(x: x, y: y)).alphaComponent, 0)
            }
        }
    }

    func testDrawingIsLimitedToItsRegionAndCanRevealWithoutChangingWindowAlpha() throws {
        let image = try opaqueBlueImage(width: 4, height: 4)
        let context = try bitmapContext(width: 8, height: 8)
        let bounds = CGRect(x: 2, y: 2, width: 4, height: 4)
        MacDockSnapshotShieldRendering.draw(image, in: bounds, context: context, opacity: 0.5)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        for y in 0..<8 {
            for x in 0..<8 {
                let alpha = try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
                if (2..<6).contains(x), (2..<6).contains(y) {
                    XCTAssertEqual(alpha, 0.5, accuracy: 1 / 255)
                } else {
                    XCTAssertEqual(alpha, 0, "Pixels outside the captured rectangle must not be covered.")
                }
            }
        }
    }

    private func bitmapContext(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func opaqueBlueImage(width: Int, height: Int) throws -> CGImage {
        let context = try bitmapContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
#endif
