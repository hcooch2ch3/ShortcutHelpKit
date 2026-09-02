import XCTest
@testable import ShortcutHelpKit

/// Proves that each field of `ShortcutHelpStrings` reaches the slot that renders it:
/// `.title` is what the window-title slot draws, and so on for the rest.
///
/// The table below is hand-written, so `testSlotNamesMatchTheDeclaredFields` compares it
/// against `ShortcutHelpStrings.slotNames`, which is derived from the type. Without that
/// comparison a slot renamed here and in the renderer together would pass while both had
/// drifted from the field they claim to render.
///
/// What this does NOT cover, and cannot: whether the adopter wired their own localized
/// strings to the right fields. This package never sees their string table and takes every
/// string as a plain value, so that mismatch surfaces in their suite, not this one.
///
/// Sentinels, not real strings: every field gets a distinct marker, so a slot wired to the
/// wrong field returns the wrong marker. Asserting against the real localized values would
/// pass even after a swap whenever two slots happen to share a value.
enum ChromeSlotGolden {
  /// (slot name, sentinel injected into the same-named `ShortcutHelpStrings` field).
  static let chromeSlots: [(slot: String, sentinel: String)] = [
    ("title", "SENTINEL_title"),
    ("empty", "SENTINEL_empty"),
    ("modifierLeft", "SENTINEL_modifierLeft"),
    ("modifierRight", "SENTINEL_modifierRight"),
    ("modifierBoth", "SENTINEL_modifierBoth"),
    ("modifierPickerAccessibilityLabel", "SENTINEL_modifierPickerAccessibilityLabel"),
    ("lockedFixed", "SENTINEL_lockedFixed"),
    ("lockedDeferred", "SENTINEL_lockedDeferred"),
  ]

  static let strings = ShortcutHelpStrings(
    title: "SENTINEL_title",
    empty: "SENTINEL_empty",
    modifierLeft: "SENTINEL_modifierLeft",
    modifierRight: "SENTINEL_modifierRight",
    modifierBoth: "SENTINEL_modifierBoth",
    modifierPickerAccessibilityLabel: "SENTINEL_modifierPickerAccessibilityLabel",
    lockedFixed: "SENTINEL_lockedFixed",
    lockedDeferred: "SENTINEL_lockedDeferred"
  )
}

@MainActor
final class ChromeSlotTests: XCTestCase {

  /// Every chrome slot, resolved through the function the view body actually calls.
  private static func rendered(_ s: ShortcutHelpStrings) -> [String: String] {
    [
      "title": KeyboardShortcutsView.windowTitle(strings: s),
      "empty": KeyboardShortcutsView.emptyMessage(strings: s),
      "modifierLeft": KeyboardShortcutsView.modifierLabel(for: .left, strings: s),
      "modifierRight": KeyboardShortcutsView.modifierLabel(for: .right, strings: s),
      "modifierBoth": KeyboardShortcutsView.modifierLabel(for: .both, strings: s),
      "modifierPickerAccessibilityLabel":
        KeyboardShortcutsView.modifierPickerAccessibilityLabel(strings: s),
      "lockedFixed": KeyboardShortcutsView.lockReason(
        for: ShortcutItem(id: "x.fixed", title: "t",
                          unit: .fixed(glyphs: [.named("Return")], label: nil)),
        strings: s),
      "lockedDeferred": KeyboardShortcutsView.lockReason(
        for: ShortcutItem(id: "x.digits", title: "t",
                          unit: .positionalDigits(modifiers: [.command], count: 10)),
        strings: s),
    ]
  }

  func testEverySlotRendersItsOwnField() {
    let actual = Self.rendered(ChromeSlotGolden.strings)
    for (slot, sentinel) in ChromeSlotGolden.chromeSlots {
      XCTAssertEqual(actual[slot], sentinel, "slot '\(slot)' does not render field '\(slot)'")
    }
  }

  /// Inside this file: a new chrome slot must appear in `chromeSlots`, and `chromeSlots`
  /// must not name a slot `rendered` no longer covers.
  func testSlotInventoryHasNotDrifted() {
    XCTAssertEqual(Set(Self.rendered(ChromeSlotGolden.strings).keys),
                   Set(ChromeSlotGolden.chromeSlots.map(\.slot)),
                   "chromeSlots and the rendered slots have drifted apart")
  }

  /// The table above is written by hand; `ShortcutHelpStrings.slotNames` is derived from the
  /// type. Comparing them is what keeps a rename honest: rename a slot here and in the
  /// renderer together and this still fails, because the type did not change with them.
  func testSlotNamesMatchTheDeclaredFields() {
    XCTAssertEqual(Set(ChromeSlotGolden.chromeSlots.map(\.slot)),
                   Set(ShortcutHelpStrings.slotNames),
                   "this table and ShortcutHelpStrings.slotNames disagree; one side renamed a slot")
  }

  /// The sentinels must be distinct, or a swapped slot could pass by coincidence.
  func testSentinelsAreDistinct() {
    let sentinels = ChromeSlotGolden.chromeSlots.map(\.sentinel)
    XCTAssertEqual(Set(sentinels).count, sentinels.count, "duplicate sentinel weakens the anchor")
  }
}
