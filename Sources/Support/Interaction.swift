import SwiftUI

// MARK: - Motion tokens (Apple-like, restrained)

/// Shared springs/easings. Keep UI under ~300ms; keyboard paths stay snappier.
enum Motion {
    /// Notch shell open — slight overshoot so content “bulges” out.
    static let notchOpen = Animation.spring(response: 0.40, dampingFraction: 0.68, blendDuration: 0.1)
    /// Notch shell close — damped, clean tuck.
    static let notchClose = Animation.spring(response: 0.30, dampingFraction: 0.92)
    /// Tab pill, segment pills, selection chrome.
    static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.82)
    /// Tab body / webcam crossfade (more damped than shell).
    static let content = Animation.spring(response: 0.32, dampingFraction: 0.88)
    /// Clip card delete + neighbors closing gaps.
    static let delete = Animation.spring(response: 0.34, dampingFraction: 0.84)
    /// Keyboard-driven selection (palette, library) — no lag.
    static let selection = Animation.easeOut(duration: 0.12)
    /// Metric bars / progress — continuous samples.
    static let metric = Animation.easeOut(duration: 0.22)
    /// Artwork / identity crossfade.
    static let crossfade = Animation.easeOut(duration: 0.2)
}

// MARK: - Press

/// Subtle scale-on-press feedback so pressable elements feel responsive.
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Stagger

/// Fades + lifts a view in with an index-based delay. Decorative only.
/// Pass a stable `token` so day/filter changes don’t re-stagger forever.
struct StaggeredAppear: ViewModifier {
    let index: Int
    /// When this changes, stagger may re-run once (e.g. first open). Default
    /// empty = only on first appear.
    var token: String = ""

    @State private var shown = false
    @State private var lastToken: String?

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear { appearIfNeeded(force: false) }
            .onChange(of: token) { _, _ in
                // Only re-stagger when token is non-empty and actually changed
                // after first mount (callers opt in).
                guard !token.isEmpty, lastToken != nil, lastToken != token else {
                    lastToken = token
                    return
                }
                shown = false
                appearIfNeeded(force: true)
            }
    }

    private func appearIfNeeded(force: Bool) {
        if shown && !force { return }
        lastToken = token
        let delay = Double(min(index, 8)) * 0.035
        withAnimation(.easeOut(duration: 0.26).delay(delay)) {
            shown = true
        }
    }
}

extension View {
    func staggeredAppear(_ index: Int, token: String = "") -> some View {
        modifier(StaggeredAppear(index: index, token: token))
    }
}

// MARK: - Transitions

private struct BlurFadeModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat
    var anchor: UnitPoint = .top

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale, anchor: anchor)
    }
}

private struct CardDeleteModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .center)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    /// Notch content enter/leave — blur bridges the swap.
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blur: 7, opacity: 0, scale: 0.97),
            identity: BlurFadeModifier(blur: 0, opacity: 1, scale: 1)
        )
    }

    /// Tab / webcam body swap — centered, slightly tighter than shell blurFade.
    static var tabContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFadeModifier(blur: 5, opacity: 0, scale: 0.97, anchor: .center),
                identity: BlurFadeModifier(blur: 0, opacity: 1, scale: 1, anchor: .center)
            ),
            removal: .modifier(
                active: BlurFadeModifier(blur: 4, opacity: 0, scale: 0.98, anchor: .center),
                identity: BlurFadeModifier(blur: 0, opacity: 1, scale: 1, anchor: .center)
            )
        )
    }

    /// Collapsed idle flanks (timer / media / load).
    static var idleFlank: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blur: 3, opacity: 0, scale: 0.96, anchor: .center),
            identity: BlurFadeModifier(blur: 0, opacity: 1, scale: 1, anchor: .center)
        )
    }

    /// Soft opacity for detail panes (palette, library).
    static var softFade: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }

    /// Clip card dismiss — never scale(0).
    static var cardDelete: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: CardDeleteModifier(blur: 4, opacity: 0, scale: 0.94, offsetY: 6),
                identity: CardDeleteModifier(blur: 0, opacity: 1, scale: 1, offsetY: 0)
            ),
            removal: .modifier(
                active: CardDeleteModifier(blur: 6, opacity: 0, scale: 0.82, offsetY: 10),
                identity: CardDeleteModifier(blur: 0, opacity: 1, scale: 1, offsetY: 0)
            )
        )
    }
}

/// Back-compat alias used by clip strip.
enum ClipStripAnimation {
    static let delete = Motion.delete
}
