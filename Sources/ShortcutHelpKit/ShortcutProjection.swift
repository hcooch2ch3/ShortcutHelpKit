import Foundation

/// Turns a keyCode into a display token. Injected by the host so the library stays agnostic
/// about keyboard layout resolution.
///
/// Platform-agnostic by design: Foundation only, no AppKit. Resolving a keyCode needs
/// Carbon, which is why that job is the host's and this is only the token it returns.
public typealias KeyProjector = @Sendable (Int) -> KeyToken

/// Digit labels for positional shortcuts (⌘1–0 and friends).
enum ShortcutProjection {
  static let digitChars: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

  /// "1–0" for count 10, "1–7" for count 7. ("–" is U+2013)
  static func rangeLabel(count: Int) -> String {
    let last = count >= digitChars.count ? "0" : String(count)
    return "1–\(last)"
  }

  // MARK: - Keycap labels
  // These render no view; they turn a unit into the strings a keycap row shows. Keeping
  // them on `KeycapView` would mean a golden test can only reach them by making that
  // SwiftUI view type public, which drags its `body` public with it. Nothing here needs
  // SwiftUI, so the display rule lives with the other projection rules and `KeycapView`
  // stays an internal rendering detail.

  /// Turns a unit into keycap labels. The view renders exactly this, so a golden test asserting
  /// against it is asserting the shipped rule and not a second copy of it.
  static func caps(for unit: ShortcutUnit, projector: KeyProjector) -> [String] {
    switch unit {
    case .single(let chord):
      return modifierGlyphs(chord.modifiers) + [label(for: projector(chord.keyCode))]
    case .positionalDigits(let mods, let count):
      return modifierGlyphs(mods) + [rangeLabel(count: count)]
    case .fixed(let glyphs, let label):
      // .fixed renders no modifier glyphs. Harmless while every fixed unit is a bare arrow
      // or Return; adding a modified fixed unit requires handling modifiers here.
      return [label ?? glyphs.map(Self.label(for:)).joined()]
    }
  }

  /// Modifier glyphs in fixed ⌃⌥⇧⌘ order.
  static func modifierGlyphs(_ m: KeyModifiers) -> [String] {
    var c: [String] = []
    if m.contains(.control) { c.append("⌃") }
    if m.contains(.option)  { c.append("⌥") }
    if m.contains(.shift)   { c.append("⇧") }
    if m.contains(.command) { c.append("⌘") }
    return c
  }

  static func label(for token: KeyToken) -> String {
    switch token {
    case .character(let s): return s
    case .named(let s):
      switch s {
      case "Return": return "⏎"
      // The illustration (KeyboardLayout) and the recorder (ShortcutGlyphs) already draw Tab
      // as ⇥, so the list uses it too and all three screens agree.
      case "Tab": return "⇥"
      // Same rule as ⇥, for the same reason: the illustration and the recorder both draw
      // keyCode 51 as ⌫, so the list must too. Without this case the row reads "⌘ Delete"
      // while the cap beside it lights as ⌫, and an editable row changes glyph the moment
      // recording stops. `KeyToken.displayLabel` is public and documents itself as "the
      // glyph the window draws", so the default branch would make that contract false.
      case "Delete": return "⌫"
      case "Left": return "←"
      case "Right": return "→"
      case "Up": return "↑"
      case "Down": return "↓"
      default: return s
      }
    case .keyCode(let n): return "#\(n)"
    }
  }
}
