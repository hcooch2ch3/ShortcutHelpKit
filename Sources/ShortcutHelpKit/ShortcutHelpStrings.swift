import Foundation

/// Chrome strings the shortcut window renders. The host supplies them already localized;
/// the library never reaches into a bundle.
///
/// Deliberately has no default: there is no bundle to fall back to, and a silent
/// fallback would hide a wiring mistake. A future package release may add one.
///
/// Platform-agnostic by design: Foundation only, no AppKit. That is a contract, not a
/// coincidence. The host injects every string, so nothing here needs a platform.
public struct ShortcutHelpStrings: Sendable {
  public var title: String
  public var empty: String
  public var modifierLeft: String
  public var modifierRight: String
  public var modifierBoth: String
  public var modifierPickerAccessibilityLabel: String
  public var lockedFixed: String
  public var lockedDeferred: String

  public init(title: String,
              empty: String,
              modifierLeft: String,
              modifierRight: String,
              modifierBoth: String,
              modifierPickerAccessibilityLabel: String,
              lockedFixed: String,
              lockedDeferred: String) {
    self.title = title
    self.empty = empty
    self.modifierLeft = modifierLeft
    self.modifierRight = modifierRight
    self.modifierBoth = modifierBoth
    self.modifierPickerAccessibilityLabel = modifierPickerAccessibilityLabel
    self.lockedFixed = lockedFixed
    self.lockedDeferred = lockedDeferred
  }

  /// The chrome slot names, derived from the type's own fields.
  /// **Internal on purpose; see the warning below.**
  ///
  /// Why this exists: the slot table in `ChromeSlotTests` is hand-written, so renaming a
  /// slot there and in the renderer together would pass while the two drift from what the
  /// type actually declares. This list is derived from the type, so the test compares its
  /// own table against the fields rather than against itself.
  ///
  /// ⚠️ Publishing this so an adopter's test bundle could reach it looks tempting and is
  /// wrong. The argument for it is "adding a field breaks `probe` at compile time." That is a
  /// property of the initializer above, which takes every field and defaults none of them.
  /// It is not a property of `Mirror`:
  ///
  ///     public var added: String        init fails to compile, then `probe` does        ✅
  ///     public var added: String = ""   both compile clean; this list silently grows    ⚠️
  ///     private var cache: Int = 0      leaks in; `children` ignores access control    ⚠️
  ///     @Wrapper public var empty       yields "_empty", the storage name               ⚠️
  ///     public var computed: String {…} correctly absent                                ✅
  ///
  /// A struct declaring `title`, an undefaulted `added` and a private `cache` yields
  /// `["title", "added", "cache"]`; a wrapped property would arrive as `"_empty"` instead.
  /// Built with reflection metadata stripped of names it yields `[]` instead.
  ///
  /// Every one of those surfaces as a loud test failure rather than a false pass, because
  /// the call site compares against an 8-entry set. None of it is safe to freeze as public
  /// API. The real exhaustiveness contract is the initializer, so keep its fields
  /// undefaulted.
  static let slotNames: [String] = {
    let probe = ShortcutHelpStrings(title: "", empty: "", modifierLeft: "", modifierRight: "",
                                    modifierBoth: "", modifierPickerAccessibilityLabel: "",
                                    lockedFixed: "", lockedDeferred: "")
    return Mirror(reflecting: probe).children.compactMap(\.label)
  }()
}
