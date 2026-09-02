import Foundation

/// Physical side of a duplicated modifier key (⌘, ⌥, ⇧). nil = position-independent, always shown.
enum KeySide: Sendable, Hashable {
  case left, right
}

/// Which side's modifier keys the illustration shows.
enum ModifierKeyMode: String, CaseIterable, Sendable {
  case left, right, both
}

struct KeyCapSpec: Hashable, Sendable {
  let token: KeyToken?   // nil = decorative cap, never highlighted
  let label: String
  let width: Double
  let side: KeySide?     // set only for the duplicated ⌘/⌥/⇧ caps
  init(token: KeyToken?, label: String, width: Double = 1, side: KeySide? = nil) {
    self.token = token
    self.label = label
    self.width = width
    self.side = side
  }

  /// Whether this cap is shown in the given mode.
  func isVisible(in mode: ModifierKeyMode) -> Bool {
    switch side {
    case nil: return true
    case .left: return mode != .right
    case .right: return mode != .left
    }
  }
}

/// The US-QWERTY keycap grid the help window draws. The grid itself stays internal; what
/// is public is the token vocabulary, so an adopter can tell which of their own key tokens
/// the illustration is able to light at all.
public enum KeyboardLayout {
  private static func c(_ s: String) -> KeyCapSpec { .init(token: .character(s), label: s) }
  private static func n(_ tok: String, _ label: String, _ w: Double = 1) -> KeyCapSpec {
    .init(token: .named(tok), label: label, width: w)
  }
  private static func nS(_ tok: String, _ label: String, _ side: KeySide, _ w: Double = 1) -> KeyCapSpec {
    .init(token: .named(tok), label: label, width: w, side: side)
  }
  private static func dead(_ label: String, _ w: Double = 1) -> KeyCapSpec {
    .init(token: nil, label: label, width: w)
  }

  /// Every token the illustration has a keycap for. A shortcut whose key is not in here
  /// still lists fine; it just never lights up. The caps lock cap is drawn and carries no
  /// token, so it is not in here either.
  ///
  /// What membership does and does not tell you:
  /// - a token in here lights its cap in all three modifier modes
  /// - a token not in here is drawn in the row and silently never lights
  /// - it cannot tell a typo from a key that is deliberately off the grid, such as the
  ///   function row: both are simply absent
  /// - it cannot see a projector that folds two physical keys onto one token. Keypad 5 and
  ///   the main row 5 both project to `.character("5")`, which is in here, so the check
  ///   passes while the wrong cap lights
  /// - `.positionalDigits` rows do not pass through a projector at all and are out of scope
  ///
  /// Published instead of `rows` on purpose: exposing the rows would make cap geometry
  /// (label, width, side) permanent API.
  public static let highlightableTokens: Set<KeyToken> = Set(rows.flatMap { $0.compactMap(\.token) })

  // Five rows: the number row, QWERTY, the home row, the bottom letter row, and modifiers.
  static let rows: [[KeyCapSpec]] = [
    // ⌫ is drawn because it is bindable AND sits on a row this grid draws. Both halves are
    // load-bearing: "bindable" alone is satisfied by much of the keyboard, since ⌘⎋, ⌘Home
    // and bare F1 all capture, so it cannot be the criterion. ⎋ stays out because it lives on
    // the function row, which `rows` does not draw at all. Of the key codes the recorder can
    // name, 51 was the last one inside a drawn row still missing a cap, so ⌘⌫ projected to
    // .named("Delete") and lit nothing. The ; ' \ caps close the same kind of hole.
    //
    // The cost, which is a property of this cap rather than a risk it might carry: a
    // projector that maps keyCode 117 (⌦) to the same name as 51 makes ⌘⌦ light this ⌫ cap,
    // the wrong physical key. The catalog audit and `unnamedKeys(from:over:)` both go quiet
    // on 117 once that happens, because a token that is in the vocabulary is no longer
    // reported; `foldedKeys(from:over:)` is the one that still sees it, and it exists for
    // exactly this class of collapse. That trades a detected gap for an undetected one,
    // on the same terms as the numpad fold; see `highlightableTokens` for why the fold is
    // invisible to the first two.
    [c("`"), c("1"), c("2"), c("3"), c("4"), c("5"), c("6"), c("7"), c("8"), c("9"), c("0"), c("-"), c("="),
     n("Delete", "⌫", 1.5)],
    // Tab carries a token so ⌃Tab can light it. A cap with a nil token has no home on the
    // board and can never be lit. The name is "Tab" because that is what a projector
    // emits for keyCode 48 when it names that key at all.
    [n("Tab", "⇥", 1.5), c("Q"), c("W"), c("E"), c("R"), c("T"), c("Y"), c("U"), c("I"), c("O"), c("P"), c("["), c("]"), c("\\")],
    [dead("⇪", 1.8), c("A"), c("S"), c("D"), c("F"), c("G"), c("H"), c("J"), c("K"), c("L"), c(";"), c("'"), n("Return", "⏎", 1.6)],
    // Both ⇧ caps carry a side, so single-side mode hides the far one. A side-less cap
    // would be visible in every mode instead, which is why the left one carries .left
    // rather than nothing. Both reuse .named("⇧"), so the pair adds one token, not two.
    [nS("⇧", "⇧", .left, 2.2), c("Z"), c("X"), c("C"), c("V"), c("B"), c("N"), c("M"), c(","), c("."), c("/"),
     nS("⇧", "⇧", .right, 2.2)],
    [n("⌃", "⌃", 1.4), nS("⌥", "⌥", .left, 1.4), nS("⌘", "⌘", .left, 1.4), n("Space", "space", 5),
     nS("⌘", "⌘", .right, 1.4), nS("⌥", "⌥", .right, 1.4), n("Left", "←"), n("Up", "↑"), n("Down", "↓"), n("Right", "→")],
  ]
}

enum ShortcutHoverMap {
  /// Maps a unit to the tokens to highlight: modifier symbols plus the key. Only `.single` resolves
  /// its key through the host-supplied projector; positional digits and fixed glyphs are
  /// already tokens.
  static func tokens(for item: ShortcutItem, projector: KeyProjector) -> Set<KeyToken> {
    switch item.unit {
    case .single(let chord):
      var set: Set<KeyToken> = [projector(chord.keyCode)]
      set.formUnion(modifierTokens(chord.modifiers))
      return set
    case .positionalDigits(let mods, let count):
      var set = Set(ShortcutProjection.digitChars.prefix(count).map { KeyToken.character($0) })
      set.formUnion(modifierTokens(mods))
      return set
    case .fixed(let glyphs, _):
      return Set(glyphs)
    }
  }

  static func items(containing token: KeyToken, in catalog: ShortcutCatalog,
                    projector: KeyProjector) -> [ShortcutItem.ID] {
    catalog.allItems.filter { tokens(for: $0, projector: projector).contains(token) }.map { $0.id }
  }

  private static func modifierTokens(_ mods: KeyModifiers) -> Set<KeyToken> {
    var set: Set<KeyToken> = []
    if mods.contains(.control) { set.insert(.named("⌃")) }
    if mods.contains(.option)  { set.insert(.named("⌥")) }
    if mods.contains(.shift)   { set.insert(.named("⇧")) }
    if mods.contains(.command) { set.insert(.named("⌘")) }
    return set
  }
}
