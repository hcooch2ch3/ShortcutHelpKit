import XCTest
import AppKit
@testable import ShortcutHelpKit

/// The recorder owns the decision that recording has ended. These drive each
/// notification path as the *only* teardown trigger, so a missing observer
/// cannot hide behind the responder-chain paths that still exist.
@MainActor
final class RecorderTeardownTests: XCTestCase {

  private func makeHostedRecorder() -> (NSWindow, RecorderNSView) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    // Required, not cosmetic:
    // a programmatically created NSWindow defaults to isReleasedWhenClosed == true, so
    // close() would free it out from under this test and crash with SIGSEGV.
    window.isReleasedWhenClosed = false
    let view = RecorderNSView(frame: NSRect(x: 10, y: 10, width: 120, height: 26))
    window.contentView?.addSubview(view)
    return (window, view)
  }

  func testWillCloseNotificationEndsRecording() {
    let (window, view) = makeHostedRecorder()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }

    view.startRecording()
    XCTAssertEqual(states, [true])
    XCTAssertEqual(view.activeMonitorCount, 2)
    XCTAssertEqual(view.activeObserverCount, 2)

    // Drive the real path: close() is what a window button and a programmatic dismissal
    // both reach. Posting willCloseNotification by hand would only test NotificationCenter,
    // and would stay green even if close() did not emit it, which is the one thing this
    // test exists to establish.
    window.close()

    XCTAssertEqual(states, [true, false], "the host must be told recording ended")
    XCTAssertEqual(view.activeMonitorCount, 0)
    XCTAssertEqual(view.activeObserverCount, 0, "observers must be removed symmetrically")
  }

  /// ⚠️ Wiring assertion, not coverage. Unlike `close()`, a real loss of key window
  /// is not drivable in-process: a non-activated test host never becomes key, so posting
  /// the notification by hand is the most this can do. It proves the observer is wired to
  /// the right name and object; it does NOT prove AppKit delivers it in production.
  /// That half can only be checked by hand: record into a field, switch to another
  /// application and back, then confirm the recorder is no longer capturing.
  func testDidResignKeyNotificationEndsRecording() {
    let (window, view) = makeHostedRecorder()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }

    view.startRecording()
    XCTAssertEqual(view.activeObserverCount, 2)

    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

    XCTAssertEqual(states, [true, false])
    XCTAssertEqual(view.activeMonitorCount, 0)
    XCTAssertEqual(view.activeObserverCount, 0)
  }

  /// A window-less recorder must not start: `object: nil` in NotificationCenter means
  /// "any object", so subscribing without a window would observe every window in the
  /// process and end recording when an unrelated one closes.
  func testStartRecordingIsRefusedWithoutWindow() {
    let view = RecorderNSView(frame: NSRect(x: 0, y: 0, width: 120, height: 26))
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }

    view.startRecording()

    XCTAssertEqual(states, [], "no host callback should fire")
    XCTAssertEqual(view.activeMonitorCount, 0)
    XCTAssertEqual(view.activeObserverCount, 0)
  }

  /// The field must still be clickable after a notification teardown.
  ///
  /// An invariant of "recording implies first responder" would make this structurally
  /// impossible. There is no such invariant here, so this test is the only thing between
  /// the user and a rebind field that is permanently dead: after a resign-key teardown the view stays first
  /// responder with `isRecording == false`, so re-entry depends on `mouseDown` still
  /// reaching `startRecording()`. Driven through `mouseDown` on purpose, because calling
  /// `startRecording()` directly would skip the line in question.
  func testFieldIsReClickableAfterResignKeyTeardown() throws {
    let (window, view) = makeHostedRecorder()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }

    let click = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: NSPoint(x: 15, y: 15), modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 0, clickCount: 1, pressure: 1))

    view.mouseDown(with: click)
    XCTAssertEqual(states, [true])

    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    XCTAssertEqual(states, [true, false])
    XCTAssertEqual(view.activeObserverCount, 0)

    view.mouseDown(with: click)
    XCTAssertEqual(states, [true, false, true], "field must be re-clickable after teardown")
    XCTAssertEqual(view.activeObserverCount, 2, "re-entry must reinstall the observers")
    XCTAssertEqual(view.activeMonitorCount, 2)

    view.endRecording()   // leave no monitors behind for the next test
  }

  /// Production order: closing a key window posts didResignKey and then willClose.
  /// The first teardown removes both tokens, so the second observer must never run,
  /// and the host must be told exactly once, or it would double-register its hotkey.
  func testBothNotificationsInProductionOrderTearDownOnce() {
    let (window, view) = makeHostedRecorder()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }

    view.startRecording()
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    window.close()

    XCTAssertEqual(states, [true, false], "teardown must be reported exactly once")
    XCTAssertEqual(view.activeMonitorCount, 0)
    XCTAssertEqual(view.activeObserverCount, 0)
  }

  /// Notification-driven teardown must be idempotent with the existing paths.
  func testNotificationThenResponderTeardownIsIdempotent() {
    let (window, view) = makeHostedRecorder()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }

    XCTAssertTrue(window.makeFirstResponder(view))
    view.startRecording()
    window.close()
    XCTAssertEqual(states, [true, false])

    _ = window.makeFirstResponder(nil)
    XCTAssertEqual(states, [true, false], "teardown must not fire twice")
  }
}
