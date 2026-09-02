import AppKit
import XCTest
@testable import ShortcutHelpKit

/// Layout and visibility tests that touch no adopter symbol. They belong in this bundle:
/// `@testable` already reaches everything they need, and running them from outside the
/// module would force publishing the whole illustration model.
///
/// One exception: `testBindableDeleteHasACapToLight` reaches into `ShortcutCaptureValidation`,
/// which is AppKit-backed. That coupling is the point of the test, tying a drawn cap to the
/// rule that earns it, so `AppKit` is imported explicitly rather than relied on arriving
/// through XCTest, the way every other file touching that API does it.
final class KeyboardLayoutTests: XCTestCase {
  /// The visibility truth table, over every row rather than the bottom one.
  ///
  /// Be precise about what covering every row buys, because the obvious answer is wrong:
  /// the bottom row already contains all three kinds of cap, so it is a complete witness
  /// for every unconditional bug in `isVisible`, and a single-row table catches those just
  /// as well. What a single row cannot witness is a visibility rule conditional on the cap or
  /// the row, the shape a layout with a second keyboard would invite, and that passes a
  /// single-row table while failing here.
  ///
  /// These assertions derive their counts from the row under test, so they hold for any row
  /// contents at all as long as `isVisible` is sound. They check the function, not the
  /// layout. A row that lost a cap, or drew its sided caps in the wrong order, is caught by
  /// the two tests below instead.
  func testModifierModeVisibilityTruthTable() {
    let bottom = KeyboardLayout.rows[4]
    // The only figures here not derived from the row itself, and the only thing that
    // catches a duplicated modifier pair.
    XCTAssertEqual(bottom.filter { $0.side == .left }.count, 2,
                   "rows[4] left-side modifier count changed - expected option and command")
    XCTAssertEqual(bottom.filter { $0.side == .right }.count, 2,
                   "rows[4] right-side modifier count changed - expected command and option")

    for (index, row) in KeyboardLayout.rows.enumerated() {
      let leftCount = row.filter { $0.side == .left }.count
      let rightCount = row.filter { $0.side == .right }.count

      XCTAssertEqual(row.filter { $0.isVisible(in: .both) }.count, row.count,
                     "rows[\(index)] hides a cap in both-sides mode")
      XCTAssertEqual(row.filter { $0.isVisible(in: .left) }.count, row.count - rightCount,
                     "rows[\(index)] shows the wrong number of caps in left mode")
      XCTAssertEqual(row.filter { $0.isVisible(in: .right) }.count, row.count - leftCount,
                     "rows[\(index)] shows the wrong number of caps in right mode")
      XCTAssertTrue(row.filter { $0.isVisible(in: .left) }.allSatisfy { $0.side != .right },
                    "rows[\(index)] leaks a right cap into left mode")
      XCTAssertTrue(row.filter { $0.isVisible(in: .right) }.allSatisfy { $0.side != .left },
                    "rows[\(index)] leaks a left cap into right mode")

      // A side-less cap belongs to no side and is drawn in every mode. Asserted once per
      // row and mode: per-cap assertions buried the counts above under a hundred lines.
      for mode in ModifierKeyMode.allCases {
        let hidden = row.filter { $0.side == nil && !$0.isVisible(in: mode) }.map(\.label)
        XCTAssertTrue(hidden.isEmpty,
                      "rows[\(index)] hides the side-less caps \(hidden) in \(mode) mode")
      }
    }
  }

  /// Left caps are drawn before right caps. Nothing else pins this: counts, pairing and
  /// the token vocabulary all survive a layout whose sides are swapped, and the result is a
  /// keyboard that draws its modifiers on the wrong side of the space bar while the whole
  /// suite stays green.
  func testSidedCapsKeepTheirPhysicalOrder() {
    for (index, row) in KeyboardLayout.rows.enumerated() {
      let sided = row.enumerated().compactMap { pair in pair.element.side.map { (pair.offset, $0) } }
      guard let lastLeft = sided.filter({ $0.1 == .left }).map(\.0).max(),
            let firstRight = sided.filter({ $0.1 == .right }).map(\.0).min() else { continue }
      XCTAssertLessThan(lastLeft, firstRight,
                        "rows[\(index)] draws a right-side cap before a left-side one")
    }
  }

  /// Three tokens, not four: the right shift reuses .named("\u{21E7}"). Asserting on the flat
  /// array rather than the set is deliberate - a Set hides a duplicate cap, and a duplicate
  /// cap draws two keys that light together. Only the three sided modifiers may repeat.
  func testTokenVocabularyAndDuplicateCaps() {
    let flat = KeyboardLayout.rows.flatMap { $0 }.compactMap(\.token)
    XCTAssertEqual(Set(flat).count, 59,
                   "token vocabulary changed - a cap was added, dropped, or retokenised")
    var counts: [KeyToken: Int] = [:]
    for t in flat { counts[t, default: 0] += 1 }
    let repeated = counts.filter { $0.value > 1 }.keys
    XCTAssertEqual(Set(repeated), [.named("\u{2318}"), .named("\u{2325}"), .named("\u{21E7}")],
                   "only the left/right modifier pairs may share a token")
    for label in ["\\", ";", "'"] {
      XCTAssertTrue(Set(flat).contains(.character(label)), "the \(label) cap lost its token")
    }
  }

  /// The ⌫ cap and the rule that earns it, pinned together.
  ///
  /// The rule is "bindable AND on a row this grid draws", not "bindable", which is true of
  /// ⌘⎋, ⌘Home and bare F1 as well, none of which is given a cap. Stating only the first
  /// half would invite the next reader to add ⎋, which lives on a row `rows` never draws.
  ///
  /// Assertions 1 and 2 duplicate `ShortcutCaptureValidationTests` on purpose: they are not
  /// here to detect a capture regression (that file already does) but to fail loudly *in the
  /// cap's own test* if the justification for drawing it disappears. Do not delete either as
  /// redundant without moving that link somewhere else.
  ///
  /// Assertion 3 is the one nothing else covers. The two token-count assertions are
  /// name-blind: rename the token and keep the count and they stay green while the cap goes
  /// permanently dark, which is exactly the silent never-lights bug this cap exists to close.
  /// Assertions 4 and 5 pin the glyph and the row, neither of which any other assertion
  /// here constrains: a cap drawn "XX", or drawn on the QWERTY row, still lights correctly
  /// and still lies to the reader about which key to press.
  func testBindableDeleteHasACapToLight() {
    XCTAssertTrue(ShortcutCaptureValidation.validate(keyCode: 51, modifiers: [.command],
                                                     blocksOptionOnly: true),
                  "⌘⌫ no longer captures - the ⌫ cap has lost the reason it was drawn")
    XCTAssertFalse(ShortcutCaptureValidation.validate(keyCode: 51, modifiers: [],
                                                      blocksOptionOnly: true),
                   "bare ⌫ must still be rejected - only the modified chord earns the cap")
    XCTAssertTrue(KeyboardLayout.highlightableTokens.contains(.named("Delete")),
                  "⌘⌫ is bindable but its projected token has no cap - it would never light")

    let cap = KeyboardLayout.rows[0].last
    XCTAssertEqual(cap?.token, .named("Delete"),
                   "the ⌫ cap left the end of the number row - the grid now draws it elsewhere")
    XCTAssertEqual(cap?.label, "\u{232B}",
                   "the ⌫ cap is drawn with the wrong glyph - it lights, but names another key")
  }

  /// No row may outgrow the window the help view fixes at 760pt wide.
  ///
  /// Nothing else here constrains width: setting the ⌫ cap to 12 units leaves every other
  /// assertion satisfied while the number row runs ~900pt and clips in silence. The number
  /// row is where that is reachable, because it carries the first non-unit width.
  func testNoRowOutgrowsTheWindow() {
    // KeyboardIllustration: 30pt per unit, 4pt padding each side of a cap, 5pt between caps,
    // 16pt outer padding each side.
    for (index, row) in KeyboardLayout.rows.enumerated() {
      let width = row.reduce(0.0) { $0 + $1.width * 30 + 8 } + Double(row.count - 1) * 5 + 32
      XCTAssertLessThan(width, 760,
                        "rows[\(index)] renders \(width)pt and clips inside the 760pt window")
    }
  }

  /// Every row that carries sided caps must survive both single-side modes, and each sided
  /// token must appear exactly once per side. Checking rows[4] alone is not enough once
  /// rows[3] carries sided caps: mutating both shifts to .right leaves .left mode with no
  /// shift key at all while a rows[4]-only truth table stays green.
  func testSidedCapsAreBalancedInEveryRow() {
    for (index, row) in KeyboardLayout.rows.enumerated() {
      let sided = row.filter { $0.side != nil }
      guard !sided.isEmpty else { continue }
      for mode in [ModifierKeyMode.left, .right] {
        XCTAssertTrue(sided.contains { $0.isVisible(in: mode) },
                      "rows[\(index)] shows no sided cap in \(mode) mode")
      }
      for token in Set(sided.compactMap(\.token)) {
        let left = sided.filter { $0.token == token && $0.side == .left }.count
        let right = sided.filter { $0.token == token && $0.side == .right }.count
        XCTAssertEqual(left, 1, "rows[\(index)] \(token) is missing its left cap")
        XCTAssertEqual(right, 1, "rows[\(index)] \(token) is missing its right cap")
      }
    }
  }

  func testLayoutHasFiveRowsAndModifierKeys() {
    XCTAssertEqual(KeyboardLayout.rows.count, 5)
    let bottom = KeyboardLayout.rows[4].compactMap { $0.token }
    XCTAssertTrue(bottom.contains(.named("⌘")) && bottom.contains(.named("Space")))
  }

  /// The modifier symbol tokens that `tokens(for:)` inserts must exist in the layout
  /// byte-identically. Pinning that catches a lookalike glyph, U+2388 standing in for
  /// U+2318, which would otherwise leave a modifier with no home and no error to show.
  func testAllModifierGlyphsHaveLayoutHome() {
    let layoutTokens = Set(KeyboardLayout.rows.flatMap { $0.compactMap { $0.token } })
    for m in ["⌃", "⌥", "⇧", "⌘"] {
      XCTAssertTrue(layoutTokens.contains(.named(m)), "modifier \(m) has no home in the layout")
    }
  }

  /// A key the board does not draw stays readable in the list and simply lights nothing.
  /// Function keys and some punctuation deliberately have no cap, so a custom binding on
  /// one of them degrades to a readable token with the illustration highlight skipped.
  /// Stated in a comment with no test under it, that contract can decay into a blank row
  /// or a crash with nothing noticing.
  func testKeyOutsideLayoutStaysReadableAndLightsNothing() {
    let projector: KeyProjector = { $0 == 122 ? .named("F1") : .character("?") }
    let item = ShortcutItem(id: "help.show", title: "Help",
                            unit: .single(KeyChord(keyCode: 122, modifiers: [.command])))
    let tokens = ShortcutHoverMap.tokens(for: item, projector: projector)
    XCTAssertTrue(tokens.contains(.named("F1")))
    XCTAssertEqual(KeyToken.named("F1").displayLabel, "F1")

    let layoutTokens = Set(KeyboardLayout.rows.flatMap { $0.compactMap { $0.token } })
    XCTAssertFalse(layoutTokens.contains(.named("F1")))
    XCTAssertEqual(layoutTokens.intersection(tokens), [.named("⌘")])
  }
}
