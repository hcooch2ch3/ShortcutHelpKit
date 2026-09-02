import XCTest
import ShortcutHelpKit

final class ShortcutModelTests: XCTestCase {
  /// This file imports the module plainly, with no @testable, so it sees exactly what an
  /// adopter sees. That is the whole point of asserting here: marking an extension public
  /// on an internal type compiles clean and exports nothing, and the rest of the suite runs
  /// under @testable, where the mistake is invisible. Dropping either public keyword makes
  /// this the only test that fails.
  func testDiagnosticSurfaceIsReachableWithoutTestable() {
    XCTAssertEqual(KeyboardLayout.highlightableTokens.count, 59)
    XCTAssertTrue(KeyboardLayout.highlightableTokens.contains(.character("A")))
  }

  /// The audit an adopter runs before shipping. Asserted from a plain import so the whole
  /// path stays reachable without @testable, and written against the failures the README
  /// warns about rather than against the implementation.
  ///
  /// The catalog spans two sections and all three unit kinds on purpose. A single-section
  /// fixture cannot tell an audit that walks every section from one that reads only
  /// `sections.first`, and a `.single`-only fixture cannot tell a live `.fixed` branch
  /// from an empty one.
  func testAuditNamesEveryRowThatSilentlyNeverLights() {
    let projector: KeyProjector = { code in
      switch code {
      case 36:  return .named("Enter")      // wrong: the cap is named Return
      case 17:  return .character("t")      // wrong: caps are drawn uppercase
      case 122: return .keyCode(122)        // deliberate: the function row is off the grid
      default:  return .character("A")
      }
    }
    let catalog = ShortcutCatalog(sections: [
      ShortcutSection(id: "one", title: "One", items: [
        .init(id: "typo.named", title: "Confirm",
              unit: .single(KeyChord(keyCode: 36, modifiers: [.command]))),
        .init(id: "typo.case", title: "New tab",
              unit: .single(KeyChord(keyCode: 17, modifiers: [.command]))),
      ]),
      ShortcutSection(id: "two", title: "Two", items: [
        .init(id: "offGrid", title: "Help",
              unit: .single(KeyChord(keyCode: 122, modifiers: [.command]))),
        .init(id: "fine", title: "Select all",
              unit: .single(KeyChord(keyCode: 0, modifiers: [.command, .shift]))),
        .init(id: "fixed.typo", title: "Back",
              unit: .fixed(glyphs: [.named("Backspace")], label: nil)),
        .init(id: "digits", title: "Panels",
              unit: .positionalDigits(modifiers: [.command], count: 4)),
      ]),
    ])

    let audit = HighlightAudit(catalog: catalog, projector: projector)

    XCTAssertEqual(audit.rowsExamined, 6, "an audit that walks one section is not an audit")
    XCTAssertFalse(audit.isClean)
    XCTAssertEqual(Set(audit.findings.map(\.id)), ["typo.named", "typo.case", "fixed.typo"])

    let byID = Dictionary(uniqueKeysWithValues: audit.findings.map { ($0.id, $0) })
    XCTAssertEqual(byID["typo.named"]?.tokens, [.named("Enter")])
    XCTAssertEqual(byID["typo.named"]?.title, "Confirm", "the finding carries the row title")
    XCTAssertEqual(byID["typo.case"]?.tokens, [.character("t")])
    XCTAssertEqual(byID["typo.case"]?.suggestions, [.character("T")])
    XCTAssertEqual(byID["fixed.typo"]?.tokens, [.named("Backspace")],
                   "a keyCode-free typo in .fixed glyphs is the host's own, not a projector skip")

    XCTAssertEqual(audit.unnamedKeys, ["offGrid": [122]],
                   "a projector that declines to name a key is reported, not hidden")
    XCTAssertNil(byID["digits"], "positional digits all have caps")
    XCTAssertNil(byID["fine"])
  }

  /// A projector that names nothing is total blindness on screen. The audit must not report
  /// that as clean, which is why the count and the unnamed keys are part of the result.
  func testBlindProjectorIsNotReportedAsClean() {
    let blind: KeyProjector = { .keyCode($0) }
    let catalog = ShortcutCatalog(sections: [
      ShortcutSection(id: "s", title: "S", items: [
        .init(id: "a", title: "A", unit: .single(KeyChord(keyCode: 1, modifiers: []))),
        .init(id: "b", title: "B", unit: .single(KeyChord(keyCode: 2, modifiers: []))),
      ]),
    ])
    let audit = HighlightAudit(catalog: catalog, projector: blind)
    XCTAssertTrue(audit.findings.isEmpty)
    XCTAssertEqual(audit.rowsExamined, 2)
    XCTAssertEqual(audit.unnamedKeys, ["a": [1], "b": [2]],
                   "every key being unnamed has to be visible in the result")

    let empty = HighlightAudit(catalog: ShortcutCatalog(sections: []), projector: blind)
    XCTAssertEqual(empty.rowsExamined, 0, "an empty catalog must not look like a clean one")
  }

  /// Two rows sharing a command id is itself a host mistake, and the host running this
  /// audit is the one likely to have made it. Neither finding may be swallowed.
  func testDuplicateCommandIDsBothSurvive() {
    let projector: KeyProjector = { $0 == 1 ? .named("One") : .named("Two") }
    let catalog = ShortcutCatalog(sections: [
      ShortcutSection(id: "a", title: "A", items: [
        .init(id: "dup", title: "First", unit: .single(KeyChord(keyCode: 1, modifiers: []))),
      ]),
      ShortcutSection(id: "b", title: "B", items: [
        .init(id: "dup", title: "Second", unit: .single(KeyChord(keyCode: 2, modifiers: []))),
      ]),
    ])
    let audit = HighlightAudit(catalog: catalog, projector: projector)
    XCTAssertEqual(audit.findings.count, 2)
    XCTAssertEqual(Set(audit.findings.flatMap(\.tokens)), [.named("One"), .named("Two")])
  }

  /// The projector surface check, which is what covers keys the user binds after shipping.
  func testUnnamedKeysWalksTheProjectorNotTheCatalog() {
    let projector: KeyProjector = { code in
      switch code {
      case 0:   return .character("A")
      case 36:  return .named("Enter")
      default:  return .keyCode(code)
      }
    }
    let result = HighlightAudit.unnamedKeys(from: projector, over: [0, 36, 122])
    XCTAssertNil(result[0], "a key with a cap is not reported")
    XCTAssertEqual(result[36], .named("Enter"))
    XCTAssertEqual(result[122], .keyCode(122))
  }

  /// The fold sweep must find what the other sweep cannot, and the pairing is the point:
  /// this asserts both halves against the same projector so neither can drift into the
  /// other's job.
  ///
  /// The fixture is a fold a real key map can have, not a contrived one: key codes 51 and
  /// 117 get the same "Delete" name, and the keypad digits get the same strings as the
  /// main row. Both produce a token that *has* a cap, which is precisely why
  /// `unnamedKeys` cannot report them: it admits a key code only when the token has none.
  func testFoldedKeysFindsWhatTheUnnamedSweepStructurallyCannot() {
    let folding: KeyProjector = { code in
      switch code {
      case 51, 117: return .named("Delete")   // backspace and forward delete, one name
      case 23, 87: return .character("5")     // main row 5 and keypad 5
      case 53: return .named("Escape")        // off grid, no cap, not a fold
      default: return .keyCode(code)
      }
    }
    let folded = HighlightAudit.foldedKeys(from: folding, over: 0...127)
    XCTAssertEqual(folded[.named("Delete")], [51, 117])
    XCTAssertEqual(folded[.character("5")], [23, 87])
    XCTAssertNil(folded[.named("Escape")], "a lone off-grid key is not a fold")
    XCTAssertEqual(folded.count, 2, "\(folded.count) folds reported, expected exactly 2")

    // The complementary sweep sees none of it, and that is the whole reason the fold sweep
    // exists. If this ever starts reporting them, the two checks have collapsed into one.
    let unnamed = HighlightAudit.unnamedKeys(from: folding, over: 0...127)
    XCTAssertNil(unnamed[51])
    XCTAssertNil(unnamed[117])
    XCTAssertNil(unnamed[87])
    XCTAssertEqual(unnamed[53], .named("Escape"), "an uncapped name must still be reported")
  }

  /// The glyph mapping lives in one place. Without this an adopter writes their own switch
  /// and it drifts the moment a glyph rule is added.
  func testTokensCarryTheLabelTheWindowDraws() {
    XCTAssertEqual(KeyToken.named("Return").displayLabel, "\u{23CE}")
    XCTAssertEqual(KeyToken.character("A").displayLabel, "A")
    // Every named token that owns a keycap must render as the glyph that cap draws, or the
    // list and the illustration disagree for the same key. ⌫ is the case asserted here
    // because a named token is easy to add without its projection case.
    XCTAssertEqual(KeyToken.named("Delete").displayLabel, "\u{232B}")
  }

  func testKeyChordCodableRoundTrip() throws {
    let c = KeyChord(keyCode: 17, modifiers: [.command, .shift])
    let data = try JSONEncoder().encode(c)
    XCTAssertEqual(try JSONDecoder().decode(KeyChord.self, from: data), c)
    // modifiers must serialize as a flat Int; that is the store format contract.
    // [.command(1), .shift(8)] is 9. Synthesized Codable does not promise key order, so this
    // asserts flatness rather than an exact string, which would be brittle for no gain.
    let json = String(data: data, encoding: .utf8) ?? ""
    XCTAssertTrue(json.contains(#""modifiers":9"#), "modifiers must be the flat Int 9: \(json)")
    XCTAssertFalse(json.contains("rawValue"), "modifiers must not nest as {\"rawValue\":N}: \(json)")
  }

  func testBindingValueCodableRoundTrip() throws {
    let values: [ShortcutBindingValue] = [
      .chord(KeyChord(keyCode: 24, modifiers: [.command])),
      .prefix([.control, .option]),
    ]
    for v in values {
      let d = try JSONEncoder().encode(v)
      XCTAssertEqual(try JSONDecoder().decode(ShortcutBindingValue.self, from: d), v)
    }
    // .prefix carries modifiers too, and they must be a bare flat Int for the same reason.
    // A {"rawValue":N} shape on one case and not the other is the asymmetry to avoid.
    let prefixJSON = String(data: try JSONEncoder().encode(ShortcutBindingValue.prefix([.control, .option])),
                            encoding: .utf8) ?? ""
    XCTAssertFalse(prefixJSON.contains("rawValue"), "prefix modifiers must be a flat Int: \(prefixJSON)")
  }

  func testCommandIDStringLiteral() {
    let id: CommandID = "nav.newTab"
    XCTAssertEqual(id.rawValue, "nav.newTab")
    XCTAssertEqual(id, CommandID(rawValue: "nav.newTab"))
  }
}
