import SwiftUI
import UIKit

/// The look of Ask in MemoUS, in SwiftUI: a violet accent, a pale page, white
/// cards with a soft shadow, outlined chips. Every colour has a dark-mode pair.
enum Theme {
  static let accent = dynamic(light: 0x6C63FF, dark: 0x8B85FF)
  static let page = dynamic(light: 0xF8F9FF, dark: 0x0F0F1A)
  static let card = dynamic(light: 0xFFFFFF, dark: 0x1C1B2E)
  static let soft = dynamic(light: 0xF5F3FF, dark: 0x27244A)
  static let ink = dynamic(light: 0x333333, dark: 0xF1F1F6)
  static let muted = dynamic(light: 0x64748B, dark: 0x9AA4B8)
  static let field = dynamic(light: 0xE0E0E0, dark: 0x3A3950)

  static let radius: CGFloat = 18

  private static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
  }
}

private extension UIColor {
  convenience init(hex: UInt32) {
    self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
              blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }
}

extension View {
  /// A white card with the soft MemoUS shadow.
  func themeCard(corners: RectangleCornerRadii = .init(topLeading: Theme.radius, bottomLeading: Theme.radius,
                                                       bottomTrailing: Theme.radius, topTrailing: Theme.radius)) -> some View {
    background(Theme.card, in: UnevenRoundedRectangle(cornerRadii: corners))
      .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
  }
}

/// MemoUS's suggestion chip: accent outline and text, on the page or a soft fill.
struct ChipStyle: ButtonStyle {
  var filled = false
  /// Smaller, for a row of short follow-ups.
  var compact = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font((compact ? Font.footnote : .subheadline).weight(.semibold))
      .foregroundStyle(Theme.accent)
      .multilineTextAlignment(.leading)
      .padding(.horizontal, compact ? 11 : 14).padding(.vertical, compact ? 6 : 8)
      .background(filled ? Theme.soft : Theme.card, in: .rect(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, lineWidth: 1.5))
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}

/// A small soft badge, such as "Can back a tip".
struct Badge: View {
  let text: String
  let symbol: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: symbol).imageScale(.small)
      Text(text)
    }
      .font(.caption.weight(.semibold))
      .foregroundStyle(Theme.accent)
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(Theme.soft, in: .capsule)
  }
}
