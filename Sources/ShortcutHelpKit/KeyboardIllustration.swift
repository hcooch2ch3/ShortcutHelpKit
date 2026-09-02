import SwiftUI

struct KeyboardIllustration: View {
  private let highlighted: Set<KeyToken>
  private let modifierMode: ModifierKeyMode
  private let onHoverToken: (KeyToken?) -> Void
  init(highlighted: Set<KeyToken>, modifierMode: ModifierKeyMode = .both,
       onHoverToken: @escaping (KeyToken?) -> Void) {
    self.highlighted = highlighted
    self.modifierMode = modifierMode
    self.onHoverToken = onHoverToken
  }

  var body: some View {
    VStack(spacing: 5) {
      ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 5) {
          let caps = row.filter { $0.isVisible(in: modifierMode) }
          ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in keyCap(cap) }
        }
      }
    }
    .padding(16)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder private func keyCap(_ cap: KeyCapSpec) -> some View {
    let isOn = cap.token.map { highlighted.contains($0) } ?? false
    let dim = !highlighted.isEmpty && !isOn
    Text(cap.label)
      .font(.system(size: 12))
      .frame(minWidth: 30 * cap.width, minHeight: 30)
      .padding(.horizontal, 4)
      .foregroundStyle(isOn ? Color.white : Color.primary)
      .background(RoundedRectangle(cornerRadius: 6)
        .fill(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
      .opacity(dim ? 0.4 : 1)
      .onHover { inside in onHoverToken(inside ? cap.token : nil) }  // hovering a key highlights its row
  }
}
