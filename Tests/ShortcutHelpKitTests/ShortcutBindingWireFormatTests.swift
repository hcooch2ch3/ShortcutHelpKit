import XCTest
import ShortcutHelpKit

/// The persisted encoding of a rebinding, in canonical (key-sorted) form. The format is a
/// cross-version contract, so it is pinned here, in the package's own bundle. A format the
/// package defines but never checks would leave every adopter to discover a change for it.
///
/// Scope of the contract: the structure and the field values, NOT the byte order.
/// A plain `JSONEncoder()`, which is what an adopter will reach for, leaves object key
/// order unspecified, and it need not match declaration order, so a byte-equality claim
/// against what users have on disk would be false.
/// What is asserted instead: persisted bytes normalize to this canonical form, and they
/// round-trip.
///
/// The `_0` wrapper is Swift's synthesized Codable for an enum with associated values;
/// `modifiers` is `KeyModifiers.rawValue`, a bare Int by hand-written Codable, not a list.
/// If this format ever has to change, the migration path is a hand-written Codable plus
/// a defaults migration, not an edit to these literals.
///
/// Scope: this file owns the **value-level** contract, because `ShortcutBindingValue` is
/// a library type an adopter will depend on. The **envelope**, meaning whatever storage key
/// an adopter picks and the `[String: ShortcutBindingValue]` dictionary around it, is
/// theirs to pin, because the package neither chooses that key nor reads it.
final class ShortcutBindingWireFormatTests: XCTestCase {

  private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = .sortedKeys
    return e
  }()

  private func canonical(_ value: ShortcutBindingValue) throws -> String {
    try XCTUnwrap(String(data: try encoder.encode(value), encoding: .utf8))
  }

  func testBindingValueWireFormatIsFrozen() throws {
    let chord = ShortcutBindingValue.chord(KeyChord(keyCode: 17, modifiers: [.command, .shift]))
    let chordJSON = try canonical(chord)
    XCTAssertEqual(chordJSON, #"{"chord":{"_0":{"keyCode":17,"modifiers":9}}}"#)

    let prefix = ShortcutBindingValue.prefix([.command, .option])
    let prefixJSON = try canonical(prefix)
    XCTAssertEqual(prefixJSON, #"{"prefix":{"_0":3}}"#)

    // Decoding is asserted from the literal, never from the encoder's own output: a
    // migration that changes encode and decode together, which synthesized `Codable`
    // does by regenerating both, sails through a round-trip and fails here.
    let decoder = JSONDecoder()
    XCTAssertEqual(try decoder.decode(ShortcutBindingValue.self, from: Data(chordJSON.utf8)), chord)
    XCTAssertEqual(try decoder.decode(ShortcutBindingValue.self, from: Data(prefixJSON.utf8)), prefix)

    // What an adopter's encoder actually writes, normalized: same structure and values, key order
    // unspecified. This is the assertion that ties the golden to real stored data.
    let asPersisted = try JSONEncoder().encode(chord)
    let normalized = try encoder.encode(
      try decoder.decode(ShortcutBindingValue.self, from: asPersisted))
    XCTAssertEqual(String(decoding: normalized, as: UTF8.self), chordJSON)
  }

  func testRoundTrip() throws {
    let cases: [ShortcutBindingValue] = [
      .chord(KeyChord(keyCode: 17, modifiers: [.command])),
      .chord(KeyChord(keyCode: 49, modifiers: [.command, .shift])),
      .prefix([.command]),
      .prefix([.control, .option]),
    ]
    for value in cases {
      let data = try JSONEncoder().encode(value)
      XCTAssertEqual(try JSONDecoder().decode(ShortcutBindingValue.self, from: data), value)
    }
  }
}
