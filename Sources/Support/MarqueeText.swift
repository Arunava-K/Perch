import SwiftUI
import AppKit

/// Single-line text that scrolls horizontally only when it overflows its
/// container, with a soft edge fade. Honors Reduce Motion (truncates instead).
///
/// The view is sized by a flexible `Color.clear`; the text lives in an overlay
/// so its intrinsic width never forces the container (or parents) wider.
/// (Emil: constant motion → `linear`; respect `prefers-reduced-motion`.)
struct MarqueeText: View {
    let text: String
    var fontSize: CGFloat = 14
    var weight: Font.Weight = .semibold
    var color: Color = .white

    private let gap: CGFloat = 46
    private let pointsPerSecond: Double = 30
    private let startDelay: Double = 1.1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var containerWidth: CGFloat = 0
    @State private var animate = false

    private var nsFont: NSFont { NSFont.systemFont(ofSize: fontSize, weight: weight.nsWeight) }
    private var textSize: CGSize { (text as NSString).size(withAttributes: [.font: nsFont]) }
    private var shouldScroll: Bool { textSize.width > containerWidth + 0.5 && !reduceMotion }

    var body: some View {
        let scroll = shouldScroll
        return Color.clear
            .frame(height: textSize.height)
            .frame(maxWidth: .infinity)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in containerWidth = new }
            })
            .overlay(alignment: .leading) {
                HStack(spacing: gap) {
                    label
                    if scroll { label }
                }
                .fixedSize()
                .offset(x: scroll && animate ? -(textSize.width + gap) : 0)
                .animation(
                    scroll
                        ? .linear(duration: (textSize.width + gap) / pointsPerSecond)
                            .repeatForever(autoreverses: false)
                        : .default,
                    value: animate
                )
            }
            .clipped()
            .mask(scroll ? AnyView(edgeFade) : AnyView(Color.black))
            .onChange(of: scroll) { _, s in restart(s) }
            .onAppear { DispatchQueue.main.async { restart(shouldScroll) } }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.96),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func restart(_ scroll: Bool) {
        animate = false
        guard scroll else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            if shouldScroll { animate = true }
        }
    }
}

private extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
