import Foundation

public struct KeyModifiers: OptionSet, Hashable, Sendable, Codable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let command = KeyModifiers(rawValue: 1 << 0)
  public static let option  = KeyModifiers(rawValue: 1 << 1)
  public static let control = KeyModifiers(rawValue: 1 << 2)
  public static let shift   = KeyModifiers(rawValue: 1 << 3)

  // Encodes as a bare Int rather than `{"rawValue": N}`, so a stored binding serializes
  // its modifiers the same way whether it arrived as a chord or as a prefix.
  public init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(Int.self)
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(rawValue)
  }
}

// MARK: - Public model

/// Opaque command identifier. The library never interprets it: no switch over its value.
/// Not Codable on purpose: persistence is the host's, keyed by the String `rawValue`.
public struct CommandID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
}

/// One canonical binding. Codable is synthesized, and because KeyModifiers encodes as a
/// bare Int the wire form stays flat: `{"keyCode":17,"modifiers":9}`. That shape is a
/// storage contract, so changing it invalidates every persisted rebinding.
public struct KeyChord: Hashable, Sendable, Codable {
  public let keyCode: Int
  public let modifiers: KeyModifiers
  public init(keyCode: Int, modifiers: KeyModifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

/// What a row binds to, and how it draws.
public enum ShortcutUnit: Hashable, Sendable {
  case single(KeyChord)                                      // e.g. ⌘T, rebindable
  case positionalDigits(modifiers: KeyModifiers, count: Int) // ⌘1–0, ⌥1–7; locked, prefix not yet editable
  case fixed(glyphs: [KeyToken], label: String?)             // arrows, Return; owned by focus, never rebindable
}

/// A rebinding: both the onRebind payload and what the host persists.
public enum ShortcutBindingValue: Hashable, Sendable, Codable {
  case chord(KeyChord)       // for a .single command
  case prefix(KeyModifiers)  // the shared prefix of a .positionalDigits family
}

/// The host's verdict on a rebinding attempt.
public enum RebindOutcome: Sendable {
  case accepted(warning: String?)  // committed; a warning still renders, e.g. the chord
                                   // shadows a system shortcut (already localized)
  case rejected(reason: String)    // already localized
}

/// What a key is called, for both the illustration's position lookup and the keycap label.
public enum KeyToken: Hashable, Sendable {
  case character(String)  // "1", "R", "["; rendered as-is
  case named(String)      // "Space", "Return", "Left", "⌘"
  case keyCode(Int)       // a custom key the two above cannot name; the illustration skips it
}

/// One row in the help window. `id` is opaque to the library; `title` arrives
/// already localized; `unit` carries both the binding and how to draw it.
public struct ShortcutItem: Identifiable, Hashable, Sendable {
  public let id: CommandID
  public let title: String
  public let unit: ShortcutUnit
  public init(id: CommandID, title: String, unit: ShortcutUnit) {
    self.id = id
    self.title = title
    self.unit = unit
  }
}

/// One rendered group of shortcuts. The host decides grouping, order, and titles;
/// the library neither interprets `id` nor sorts.
///
/// `id` is required and must not be derived from localized text: it is the identity
/// SwiftUI's ForEach uses.
public struct ShortcutSection: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let items: [ShortcutItem]
  public init(id: String, title: String, items: [ShortcutItem]) {
    self.id = id
    self.title = title
    self.items = items
  }
}
