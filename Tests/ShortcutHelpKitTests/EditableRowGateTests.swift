import XCTest
@testable import ShortcutHelpKit

@MainActor
final class EditableRowGateTests: XCTestCase {
  func testSingleIsEditable() {
    let item = ShortcutItem(id: "nav.newTab", title: "New Tab",
                            unit: .single(KeyChord(keyCode: 17, modifiers: [.command])))
    XCTAssertTrue(KeyboardShortcutsView.isEditable(item))
  }
  func testPositionalNotEditable() {
    let item = ShortcutItem(id: "tab.select", title: "Tab",
                            unit: .positionalDigits(modifiers: [.command], count: 10))
    XCTAssertFalse(KeyboardShortcutsView.isEditable(item))   // only .single is editable; positionalDigits is a locked row
  }
  func testFixedNotEditable() {
    let item = ShortcutItem(id: "sel.confirm", title: "Confirm",
                            unit: .fixed(glyphs: [.named("Return")], label: nil))
    XCTAssertFalse(KeyboardShortcutsView.isEditable(item))
  }

  /// The README tells adopters a rejection caption clears on a successful rebind. This is
  /// what pins it, and the detail is easy to state wrongly: it is nil, not the empty
  /// string, that removes the row's entry, and only an accepted outcome without a warning
  /// produces nil.
  func testAcceptedRebindWithoutWarningRemovesTheCaption() {
    XCTAssertNil(KeyboardShortcutsView.message(from: .accepted(warning: nil)),
                 "an accepted rebind with no warning has to remove the caption")
    XCTAssertEqual(KeyboardShortcutsView.message(from: .accepted(warning: "shadows a system key")),
                   "shadows a system key")
    XCTAssertEqual(KeyboardShortcutsView.message(from: .rejected(reason: "already bound")),
                   "already bound")

    // The dictionary write in rowTrailing assigns this result directly, so nil removes.
    var messages: [CommandID: String] = ["row": "already bound"]
    messages["row"] = KeyboardShortcutsView.message(from: .accepted(warning: nil))
    XCTAssertNil(messages["row"])
  }
}
