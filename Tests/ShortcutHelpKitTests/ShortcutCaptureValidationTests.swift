import XCTest
import AppKit
@testable import ShortcutHelpKit

final class ShortcutCaptureValidationTests: XCTestCase {
  // The modifier rule: a bare letter is not a shortcut.
  func testBareLetterRejected() {
    XCTAssertFalse(ShortcutCaptureValidation.validate(keyCode: 17, modifiers: [], blocksOptionOnly: true))
  }
  // ⇧ alone is not enough either.
  func testShiftOnlyRejected() {
    XCTAssertFalse(ShortcutCaptureValidation.validate(keyCode: 17, modifiers: [.shift], blocksOptionOnly: true))
  }
  // ⌘ with a letter is accepted.
  func testCommandLetterAccepted() {
    XCTAssertTrue(ShortcutCaptureValidation.validate(keyCode: 17, modifiers: [.command], blocksOptionOnly: true))
  }
  // Function keys stand alone; F1 is keyCode 122.
  func testFunctionKeyStandaloneAccepted() {
    XCTAssertTrue(ShortcutCaptureValidation.validate(keyCode: 122, modifiers: [], blocksOptionOnly: true))
  }
  // ⌥ alone is gated by the flag: rejected when it is on, accepted when it is off.
  func testOptionOnlyGatedByFlag() {
    XCTAssertFalse(ShortcutCaptureValidation.validate(keyCode: 17, modifiers: [.option], blocksOptionOnly: true))
    XCTAssertTrue(ShortcutCaptureValidation.validate(keyCode: 17, modifiers: [.option], blocksOptionOnly: false))
  }
  // Modifier glyphs always read in the order ⌃⌥⇧⌘, whatever order they arrive in.
  func testModifierGlyphOrder() {
    let mods: KeyModifiers = [.command, .shift, .option, .control]
    XCTAssertEqual(ShortcutGlyphs.modifierString(mods), "⌃⌥⇧⌘")
  }
  // Special keys come from a static table. The system reports Return as an empty string,
  // so there is nothing to derive the glyph from at runtime.
  func testSpecialKeyGlyph() {
    XCTAssertEqual(ShortcutGlyphs.displayCharacter(forKeyCode: 36), "↩")  // Return
    XCTAssertEqual(ShortcutGlyphs.displayCharacter(forKeyCode: 49), "␣")  // Space
  }

  // Every function key keyCode, F1 through F20, is accepted standalone. The list is hand
  // written, and the tail of it is the part that silently drifts.
  func testAllFunctionKeysAcceptedStandalone() {
    let fkeys: [UInt16] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
    for kc in fkeys {
      XCTAssertTrue(ShortcutCaptureValidation.validate(keyCode: kc, modifiers: [], blocksOptionOnly: true),
                    "F-key \(kc) should be accepted standalone")
    }
  }

  /// Teardown through the responder chain: resignFirstResponder ends recording and reports
  /// false. This is not the window-close or key-loss path. The recorder observes those two
  /// itself and `RecorderTeardownTests` drives them with a real close(). What is left here
  /// is the hand-off when focus moves to another field.
  @MainActor
  func testResignFirstResponderEndsRecording() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let view = RecorderNSView()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }
    window.contentView = view
    XCTAssertTrue(window.makeFirstResponder(view))
    view.startRecording()
    XCTAssertEqual(states, [true])                 // recording starts, the engine pauses
    XCTAssertTrue(window.makeFirstResponder(nil))  // focus leaves for another field
    XCTAssertEqual(states, [true, false])          // teardown resumes: hotkeys back, monitors gone
  }

  // MARK: Click-away cancels

  @MainActor
  private func makeHostedRecorder() -> (NSWindow, RecorderNSView) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let view = RecorderNSView(frame: NSRect(x: 10, y: 10, width: 120, height: 26))
    window.contentView?.addSubview(view)
    return (window, view)
  }

  @MainActor
  private func click(at p: NSPoint, windowNumber: Int) -> NSEvent? {
    NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [],
                       timestamp: 0, windowNumber: windowNumber, context: nil,
                       eventNumber: 0, clickCount: 1, pressure: 1)
  }

  // All three branches: inside, the same window's margin, and a different window.
  // The last one is the reason isClickOutside exists at all.
  @MainActor
  func testClickOutsideDetection() throws {
    let (window, view) = makeHostedRecorder()
    let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                         styleMask: [.titled], backing: .buffered, defer: false)

    let inside = try XCTUnwrap(click(at: NSPoint(x: 15, y: 15), windowNumber: window.windowNumber))
    XCTAssertFalse(view.isClickOutside(inside))                       // inside the field

    let outside = try XCTUnwrap(click(at: NSPoint(x: 300, y: 200), windowNumber: window.windowNumber))
    XCTAssertTrue(view.isClickOutside(outside))                       // same window, margin

    let elsewhere = try XCTUnwrap(click(at: NSPoint(x: 15, y: 15), windowNumber: other.windowNumber))
    XCTAssertTrue(view.isClickOutside(elsewhere))                     // another window counts as outside
  }

  // Drive the click-away path for real: a click inside keeps recording, a click outside
  // ends it and takes both monitors back.
  @MainActor
  func testClickAwayEndsRecordingOnlyWhenOutside() throws {
    let (window, view) = makeHostedRecorder()
    var states: [Bool] = []
    view.onRecordingChange = { states.append($0) }
    let inside = try XCTUnwrap(click(at: NSPoint(x: 15, y: 15), windowNumber: window.windowNumber))
    let outside = try XCTUnwrap(click(at: NSPoint(x: 300, y: 200), windowNumber: window.windowNumber))

    view.startRecording()
    XCTAssertEqual(states, [true])
    XCTAssertEqual(view.activeMonitorCount, 2)        // keyDown and clickAway both installed

    view.handleClickAway(inside)                      // clicking the field itself keeps it
    XCTAssertEqual(states, [true])
    XCTAssertEqual(view.activeMonitorCount, 2)

    view.handleClickAway(outside)                     // clicking the margin cancels
    XCTAssertEqual(states, [true, false])             // resume, so global hotkeys register again
    XCTAssertEqual(view.activeMonitorCount, 0)        // both monitors come back symmetrically

    view.handleClickAway(outside)                     // idempotent
    XCTAssertEqual(states, [true, false])
  }

  /// Every monitor that goes up must come down. Breaking that strands a monitor that keeps
  /// swallowing events after recording ends, which is why it is pinned. Covered here are
  /// the two synchronous paths, responder and window detach. The notification-driven pair,
  /// window close and key loss, along with observer removal, belong to
  /// `RecorderTeardownTests`.
  @MainActor
  func testMonitorsRemovedOnEveryTeardownPath() {
    // Path 1: resignFirstResponder, when focus moves to another field.
    let (window, view) = makeHostedRecorder()
    XCTAssertTrue(window.makeFirstResponder(view))
    view.startRecording()
    XCTAssertEqual(view.activeMonitorCount, 2)
    XCTAssertTrue(window.makeFirstResponder(nil))
    XCTAssertEqual(view.activeMonitorCount, 0)

    // Path 2: the view leaves the window, which is how SwiftUI tears it down.
    let (_, view2) = makeHostedRecorder()
    view2.startRecording()
    XCTAssertEqual(view2.activeMonitorCount, 2)
    view2.removeFromSuperview()
    XCTAssertEqual(view2.activeMonitorCount, 0)
  }

  // The decision tree, extracted from the handler so it can be tested without an event loop.
  func testDecideCancelCaptureReject() {
    // A bare Escape cancels.
    XCTAssertEqual(RecorderNSView.decide(keyCode: 53, modifiers: [], isKeyDown: true, blocksOptionOnly: true), .cancel)
    // Bare Delete and ForwardDelete are rejected like any other invalid key. The recorder
    // has no unbind gesture: a key that only dismissed a caption would read as one and
    // would not be.
    XCTAssertEqual(RecorderNSView.decide(keyCode: 51, modifiers: [], isKeyDown: true, blocksOptionOnly: true), .reject)
    XCTAssertEqual(RecorderNSView.decide(keyCode: 117, modifiers: [], isKeyDown: true, blocksOptionOnly: true), .reject)
    // ⌘⌫ carries a modifier, so it captures normally rather than being rejected.
    XCTAssertEqual(RecorderNSView.decide(keyCode: 51, modifiers: [.command], isKeyDown: true, blocksOptionOnly: true),
                   .capture(KeyChord(keyCode: 51, modifiers: [.command])))
    // ⌘T captures.
    XCTAssertEqual(RecorderNSView.decide(keyCode: 17, modifiers: [.command], isKeyDown: true, blocksOptionOnly: true),
                   .capture(KeyChord(keyCode: 17, modifiers: [.command])))
    // A bare letter is rejected.
    XCTAssertEqual(RecorderNSView.decide(keyCode: 17, modifiers: [], isKeyDown: true, blocksOptionOnly: true), .reject)
    // flagsChanged is not a keyDown, so it is ignored rather than judged.
    XCTAssertEqual(RecorderNSView.decide(keyCode: 17, modifiers: [.command], isKeyDown: false, blocksOptionOnly: true), .ignore)
  }
}
