import SwiftUI

/// Memo, the face of Ask in MemoUS. The art belongs to MemoUS and is not covered
/// by this repository's Apache license (see MASCOT-LICENSE.md).
///
/// Decorative: hidden from VoiceOver. The avatar is a night-blue square drawn as a
/// circle; the full mascot is transparent and isn't clipped. It floats gently
/// (2 s, 3 pt each way) only on the empty screen and while an answer is on its
/// way, and never with Reduce Motion on.
struct MemoMascot: View {
  enum Variant { case mascot, avatar }

  let variant: Variant
  let size: CGFloat
  var float = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var up = false

  var body: some View {
    image
      .offset(y: floating ? (up ? -3 : 3) : 0)
      .animation(floating ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: up)
      .onAppear { if floating { up = true } }
      .onChange(of: floating) { _, now in up = now }
      .accessibilityHidden(true)
  }

  private var floating: Bool { float && !reduceMotion }

  @ViewBuilder private var image: some View {
    switch variant {
    case .mascot:
      Image("memo-mascot").resizable().scaledToFit().frame(width: size, height: size)
    case .avatar:
      Image("memo-avatar").resizable().scaledToFill().frame(width: size, height: size).clipShape(.circle)
    }
  }
}
