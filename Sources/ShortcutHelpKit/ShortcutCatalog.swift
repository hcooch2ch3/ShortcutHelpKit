import Foundation

/// Sections in render order. The library does not reorder or filter them:
/// the host must omit empty sections (the `empty` string shows only when
/// there are no sections at all).
public struct ShortcutCatalog: Sendable {
  public let sections: [ShortcutSection]
  public var allItems: [ShortcutItem] { sections.flatMap(\.items) }

  public init(sections: [ShortcutSection]) {
    self.sections = sections
  }
}
