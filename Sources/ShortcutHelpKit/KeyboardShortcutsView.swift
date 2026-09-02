import SwiftUI

/// Per-row rejection and warning captions. Owned and injected by the host so they survive
/// the view being rebuilt when bindings change.
@MainActor public final class RebindFeedback: ObservableObject {
  @Published public var messages: [CommandID: String] = [:]
  public init() {}
}

public struct KeyboardShortcutsView: View {
  private let catalog: ShortcutCatalog
  private let keyProjector: KeyProjector
  private let strings: ShortcutHelpStrings
  private let onClose: () -> Void
  private let onRebind: ((CommandID, ShortcutBindingValue) -> RebindOutcome)?
  private let onRecordingChange: (Bool) -> Void
  @ObservedObject private var feedback: RebindFeedback
  @State private var hoveredItemID: ShortcutItem.ID?
  @State private var hoveredToken: KeyToken?
  @State private var modifierMode: ModifierKeyMode = .both
  @State private var isRecordingActiveLocal = false
  public init(catalog: ShortcutCatalog, keyProjector: @escaping KeyProjector,
              strings: ShortcutHelpStrings,
              onClose: @escaping () -> Void = {},
              onRebind: ((CommandID, ShortcutBindingValue) -> RebindOutcome)? = nil,
              onRecordingChange: @escaping (Bool) -> Void = { _ in },
              feedback: RebindFeedback = RebindFeedback()) {
    self.catalog = catalog
    self.keyProjector = keyProjector
    self.strings = strings
    self.onClose = onClose
    self.onRebind = onRebind
    self.onRecordingChange = onRecordingChange
    self._feedback = ObservedObject(wrappedValue: feedback)
  }

  /// The edit gate: only `.single` rows get a recorder. `.positionalDigits` and `.fixed`
  /// render a locked keycap instead. That is deliberately narrower than "not fixed", which would
  /// offer a recorder for the digit rows, where only the modifier prefix is rebindable.
  static func isEditable(_ item: ShortcutItem) -> Bool {
    if case .single = item.unit { return true }
    return false
  }

  private var highlightedTokens: Set<KeyToken> {
    if let id = hoveredItemID, let item = catalog.allItems.first(where: { $0.id == id }) {
      return ShortcutHoverMap.tokens(for: item, projector: keyProjector)
    }
    if let t = hoveredToken { return [t] }
    return []
  }

  private var highlightedRows: Set<ShortcutItem.ID> {
    // Hovering a bare modifier (⌘/⌥/⌃/⇧) would highlight every row that carries it, which
    // says something about the modifier rather than about any one key, so reverse
    // highlighting only fires for real keys.
    guard let t = hoveredToken, !Self.isBareModifier(t) else { return [] }
    return Set(ShortcutHoverMap.items(containing: t, in: catalog, projector: keyProjector))
  }

  private static func isBareModifier(_ t: KeyToken) -> Bool {
    if case let .named(s) = t { return ["⌘", "⌥", "⌃", "⇧"].contains(s) }
    return false
  }

  // MARK: - String slots
  // Extracted so the mapping from slot to key is testable. Keep them as named functions
  // rather than inlining them into the body: `ChromeSlotTests` asserts against them, and
  // inlined expressions are not reachable from a test.

  static func windowTitle(strings: ShortcutHelpStrings) -> String {
    strings.title
  }

  static func emptyMessage(strings: ShortcutHelpStrings) -> String {
    strings.empty
  }

  static func modifierLabel(for mode: ModifierKeyMode, strings: ShortcutHelpStrings) -> String {
    switch mode {
    case .left:  return strings.modifierLeft
    case .right: return strings.modifierRight
    case .both:  return strings.modifierBoth
    }
  }

  static func modifierPickerAccessibilityLabel(strings: ShortcutHelpStrings) -> String {
    strings.modifierPickerAccessibilityLabel
  }

  /// .fixed rows are owned by focus and can never be rebound; positional digits are
  /// deferred to a later release.
  static func lockReason(for item: ShortcutItem, strings: ShortcutHelpStrings) -> String {
    switch item.unit {
    case .fixed: return strings.lockedFixed
    default:     return strings.lockedDeferred
    }
  }

  public var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(Self.windowTitle(strings: strings)).font(.headline)
        Spacer()
        // Top right: which side's modifier keys (⌘, ⌥, ⇧) the illustration shows
        Picker(Self.modifierPickerAccessibilityLabel(strings: strings), selection: $modifierMode) {
          Text(Self.modifierLabel(for: .left, strings: strings)).tag(ModifierKeyMode.left)
          Text(Self.modifierLabel(for: .right, strings: strings)).tag(ModifierKeyMode.right)
          Text(Self.modifierLabel(for: .both, strings: strings)).tag(ModifierKeyMode.both)
        }
        .pickerStyle(.segmented)
        .labelsHidden()  // hidden visually only; VoiceOver still reads the label above
        .fixedSize()
      }.padding()
      .onChange(of: modifierMode) {
        // Clear the hovered token: switching modes can filter out the cap it points at,
        // which would otherwise leave a highlight with nothing under the cursor.
        hoveredToken = nil
      }
      Divider()
      KeyboardIllustration(highlighted: highlightedTokens, modifierMode: modifierMode,
                           onHoverToken: { hoveredToken = $0 })
      Divider()
      ScrollView {
        if catalog.sections.isEmpty {
          Text(Self.emptyMessage(strings: strings)).foregroundStyle(.secondary).padding()
        } else {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(catalog.sections) { section in
              VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                  .font(.caption).fontWeight(.bold).foregroundStyle(.secondary).textCase(.uppercase)
                ForEach(section.items) { item in
                  HStack {
                    Text(item.title).font(.body)
                    Spacer()
                    rowTrailing(for: item)
                  }
                  .padding(.vertical, 4).padding(.horizontal, 8)
                  .background(RoundedRectangle(cornerRadius: 6)
                    .fill(highlightedRows.contains(item.id) ? Color.accentColor.opacity(0.15) : .clear))
                  // Enter sets this row. Exit clears only if this row is still the hovered one:
                  // moving between adjacent rows can deliver B's enter before A's exit.
                  .onHover { inside in hoveredItemID = inside ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID) }
                }
              }
            }
          }
          .padding().frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(width: 760, height: 560)
    // `.onExitCommand` is macOS-only SwiftUI, the one platform constraint in this file
    // that reading it does not reveal (everything else here is portable SwiftUI).
    .onExitCommand { if !isRecordingActiveLocal { onClose() } }  // while recording, ESC cancels the capture
  }

  /// Trailing edge of a row. An editable `.single` shows a recorder *instead of* the keycap,
  /// never both. A locked row shows the keycap plus a padlock carrying the reason. Without
  /// `onRebind` the view is read-only and shows the bare keycap.
  @ViewBuilder
  private func rowTrailing(for item: ShortcutItem) -> some View {
    if let onRebind, Self.isEditable(item), case let .single(chord) = item.unit {
      VStack(alignment: .trailing, spacing: 2) {
        ShortcutRecorderField(
          current: chord,
          onCapture: { newChord in feedback.messages[item.id] = Self.message(from: onRebind(item.id, .chord(newChord))) },
          onRecordingChange: { active in isRecordingActiveLocal = active; onRecordingChange(active) }
        )
        .frame(width: 120, height: 26)
        if let msg = feedback.messages[item.id], !msg.isEmpty {   // an empty string renders no caption
          Text(msg).font(.caption).foregroundStyle(.secondary)
        }
      }
    } else if onRebind != nil {
      HStack(spacing: 6) {
        KeycapView(unit: item.unit, projector: keyProjector)
        Image(systemName: "lock.fill").foregroundStyle(.tertiary).help(Self.lockReason(for: item, strings: strings))
      }
    } else {
      KeycapView(unit: item.unit, projector: keyProjector)   // read-only
    }
  }

  /// nil removes the row's caption, which is how an accepted rebind with no warning
  /// clears a previous rejection. Static and named for the same reason as the string
  /// slots above: it is a rule worth pinning, not view plumbing.
  static func message(from o: RebindOutcome) -> String? {
    switch o { case .rejected(let r): return r; case .accepted(let w): return w }
  }
}
