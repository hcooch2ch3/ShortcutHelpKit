import SwiftUI
import XCTest
import ShortcutHelpKit   // deliberately not @testable - see the lint in ShortcutHelpLintTests

/// The README's integration example, as code the compiler checks.
///
/// The example is written against the package's public API only, so it builds for a reader
/// who has nothing but this package. It lives here where it must compile, and
/// `ReadmeFidelityTests` asserts the README still quotes it verbatim.
///
/// That gives the example two independent guards: the compiler catches an API change,
/// and the fidelity test catches the README drifting away from what compiles. Neither
/// alone is enough, because a doc snippet can be stale *and* plausible.
///
/// The plain import is the third guard and the one that makes the sentence above true.
/// Under `@testable` this file would compile against internal symbols, so an example
/// quoting something an adopter cannot reach would still look correct here.
enum ReadmeExample {

  // MARK: - The example the README quotes

  static func makeCatalog() -> ShortcutCatalog {
    let newTab = ShortcutItem(
      id: "nav.newTab",
      title: "New Tab",
      unit: .single(KeyChord(keyCode: 17, modifiers: [.command])))

    let selectTab = ShortcutItem(
      id: "tab.select",
      title: "Select Tab",
      unit: .positionalDigits(modifiers: [.command], count: 4))

    let confirm = ShortcutItem(
      id: "sel.confirm",
      title: "Confirm",
      unit: .fixed(glyphs: [.named("Return")], label: nil))

    return ShortcutCatalog(sections: [
      ShortcutSection(id: "navigation", title: "Navigation", items: [newTab]),
      ShortcutSection(id: "selection", title: "Selection", items: [selectTab, confirm]),
    ])
  }

  /// Maps a key code to what the keycap should say. Returning a `.named` string the
  /// illustration does not know fails silently: it compiles, it renders, and the key
  /// simply never highlights.
  static let projector: KeyProjector = { keyCode in
    switch keyCode {
    case 17: return .character("T")
    case 36: return .named("Return")
    case 49: return .named("Space")
    default: return .keyCode(keyCode)
    }
  }

  /// Built here rather than taken as a parameter. An example that accepts a value never
  /// calls the initializer an adopter has to call first, and that initializer could lose
  /// its `public` with every test in this package still green.
  static let strings = ShortcutHelpStrings(
    title: "Keyboard Shortcuts",
    empty: "No shortcuts yet",
    modifierLeft: "Left",
    modifierRight: "Right",
    modifierBoth: "Both",
    modifierPickerAccessibilityLabel: "Modifier keys to show",
    lockedFixed: "Fixed by focus",
    lockedDeferred: "Not editable yet")

  @MainActor
  static func makeView(onClose: @escaping () -> Void) -> KeyboardShortcutsView {
    KeyboardShortcutsView(
      catalog: makeCatalog(),
      keyProjector: projector,
      strings: strings,
      onClose: onClose)
  }

  /// The pre-ship check, quoted by the README. All three are needed and they look at
  /// different things: the catalog audit walks the rows you shipped, the fold sweep finds
  /// key codes that collapse onto one token, while the projector
  /// sweep walks key codes nobody has bound yet, which is where a rebind lands.
  static func runDiagnostics() -> (dead: [HighlightAudit.Finding],
                                   unnamed: [Int: KeyToken],
                                   folded: [KeyToken: Set<Int>]) {
    let audit = HighlightAudit(catalog: makeCatalog(), projector: projector)
    let unnamed = HighlightAudit.unnamedKeys(from: projector, over: 0...127)
    let folded = HighlightAudit.foldedKeys(from: projector, over: 0...127)
    return (audit.findings, unnamed, folded)
  }
}

/// Proves the example above is not merely compilable but coherent: the catalog it
/// builds is the one the README describes.
final class ReadmeExampleTests: XCTestCase {

  func testExampleCatalogHasTheShapeTheReadmeDescribes() {
    let catalog = ReadmeExample.makeCatalog()
    XCTAssertEqual(catalog.sections.map(\.id), ["navigation", "selection"])
    XCTAssertEqual(catalog.allItems.map(\.id.rawValue), ["nav.newTab", "tab.select", "sel.confirm"])
  }

  /// Reads every field back. The initializer and these eight getters are the surface an
  /// adopter touches before anything else. Without this, any one of them could be
  /// de-published without a single test noticing.
  func testTheStringsAnAdopterMustSupplyAreReadable() {
    let s = ReadmeExample.strings
    XCTAssertEqual([s.title, s.empty, s.modifierLeft, s.modifierRight, s.modifierBoth,
                    s.modifierPickerAccessibilityLabel, s.lockedFixed, s.lockedDeferred],
                   ["Keyboard Shortcuts", "No shortcuts yet", "Left", "Right", "Both",
                    "Modifier keys to show", "Fixed by focus", "Not editable yet"])
  }

  /// The `.named` vocabulary is closed: the illustration can only highlight a token it has
  /// a keycap for. This asserts the example's own tokens are inside it, and doubles as the
  /// executable form of the README's warning about `.named("Enter")`.
  func testProjectorTokensAreNamesTheIllustrationKnows() {
    let known = KeyboardLayout.highlightableTokens
    for keyCode in [36, 49] {
      let token = ReadmeExample.projector(keyCode)
      XCTAssertTrue(known.contains(token), "\(token) has no keycap, so it would never highlight")
    }
    XCTAssertFalse(known.contains(.named("Enter")),
                   "if this ever passes, the README's warning about .named(\"Enter\") is stale")
  }

  /// The diagnostics the README tells an adopter to run must actually be clean for the
  /// example the README ships. A dirty example would teach the failure it warns about.
  ///
  /// The `unnamed` half is asserted as *non-empty* on purpose: the example projector
  /// returns `.keyCode` for everything it does not name, so a sweep that reported nothing
  /// would mean the sweep stopped working, not that the projector got better.
  func testTheReadmeDiagnosticsAreCleanForTheReadmeExample() {
    let (dead, unnamed, folded) = ReadmeExample.runDiagnostics()
    XCTAssertEqual(dead, [], "the README's own example ships a row that never lights")
    XCTAssertFalse(unnamed.isEmpty, "the projector sweep reported nothing - it is not running")
    XCTAssertNil(unnamed[17], "keyCode 17 is named and has a cap; it must not be reported")
    XCTAssertEqual(folded, [:], "the README's own example projector folds two keys onto one cap")
  }
}
