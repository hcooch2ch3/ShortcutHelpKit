import SwiftUI

/// Renders one shortcut as a row of keycaps: modifiers in fixed ⌃⌥⇧⌘ order, then the key.
struct KeycapView: View {
  private let caps: [String]
  init(unit: ShortcutUnit, projector: KeyProjector) {
    self.caps = ShortcutProjection.caps(for: unit, projector: projector)
  }

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
        Text(cap)
          .font(.system(size: 12, weight: .medium))
          .frame(minWidth: 22, minHeight: 22)
          .padding(.horizontal, 5)
          .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
          .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
      }
    }
  }
}
