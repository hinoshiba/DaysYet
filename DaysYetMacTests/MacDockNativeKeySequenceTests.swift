#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import ApplicationServices
import XCTest
@testable import DaysYetMac

final class MacDockNativeKeySequenceTests: XCTestCase {
    func testFunctionAndArrowKeysRetainTheirNativeFlags() throws {
        for key: CGKeyCode in [99, 123, 124, 125, 126] {
            let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
            let original = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true))
            let required: CGEventFlags = key == 99 ? .maskControl : .maskAlternate
            let events = try XCTUnwrap(MacDockNativeKeySequence.make(
                key: key, modifier: key == 99 ? 59 : 58, flags: required))
            XCTAssertEqual(events.count, 4)
            for event in events[1...2] {
                XCTAssertTrue(event.flags.isSuperset(of: original.flags))
                XCTAssertTrue(event.flags.contains(required))
                XCTAssertTrue(event.flags.contains(.maskSecondaryFn))
                if key != 99 { XCTAssertTrue(event.flags.contains(.maskNumericPad)) }
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(key))
            }
            XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        }
    }

    func testModifierReleaseRetainsNativeReleaseState() throws {
        for modifier: CGKeyCode in [58, 59] {
            let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
            let nativeRelease = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: false))
            let events = try XCTUnwrap(MacDockNativeKeySequence.make(
                key: 99, modifier: modifier, flags: modifier == 58 ? .maskAlternate : .maskControl))
            XCTAssertEqual(events.last?.flags, nativeRelease.flags)
            XCTAssertEqual(events.last?.getIntegerValueField(.keyboardEventKeycode), Int64(modifier))
        }
    }

    func testUnmodifiedEscapeHasNoModifierEvents() throws {
        let events = try XCTUnwrap(MacDockNativeKeySequence.make(key: 53))
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 53 })
    }
}
#endif
