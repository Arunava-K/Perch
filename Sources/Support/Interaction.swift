import SwiftUI

/// Subtle scale-on-press feedback so pressable elements feel responsive.
/// (Emil: "Buttons must feel responsive" — scale 0.95–0.98 on press.)
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Fades + lifts a view in with an index-based delay for a cascading entrance.
/// (Emil: stagger 30–80ms between items; decorative, never blocks interaction.)
struct StaggeredAppear: ViewModifier {
    let index: Int

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.26).delay(Double(min(index, 8)) * 0.035)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

/// Blur + fade + slight scale used when notch content enters/leaves. Blur
/// bridges the visual gap between states so the swap reads as one motion.
/// (Emil: "use blur to mask imperfect transitions.")
private struct BlurFadeModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blur: 7, opacity: 0, scale: 0.97),
            identity: BlurFadeModifier(blur: 0, opacity: 1, scale: 1)
        )
    }
}
