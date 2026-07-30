import SwiftUI

/// Circular album art that spins while playing. Full cover visibility — no
/// tiny center-label treatment.
struct VinylView: View {
    var artwork: NSImage?
    var isPlaying: Bool
    var accent: Color = .white
    var size: CGFloat = 120

    @State private var pausedAngle: Double = 0
    @State private var pauseDate: Date = .now
    /// Degrees per second — readable spin at notch scale.
    private let rpmDegrees: Double = 120

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let angle = currentAngle(at: context.date)
            disc(angle: angle)
        }
        .frame(width: size, height: size)
        .onChange(of: isPlaying) { wasPlaying, playing in
            if !playing {
                pausedAngle = currentAngle(at: .now)
                pauseDate = .now
            } else if !wasPlaying {
                pauseDate = .now
            }
        }
        .onAppear {
            pauseDate = .now
            if !isPlaying { pausedAngle = 0 }
        }
    }

    private func currentAngle(at date: Date) -> Double {
        if isPlaying {
            return pausedAngle + date.timeIntervalSince(pauseDate) * rpmDegrees
        }
        return pausedAngle
    }

    private func disc(angle: Double) -> some View {
        ZStack {
            // Soft accent glow
            Circle()
                .fill(accent.opacity(0.2))
                .frame(width: size * 0.94, height: size * 0.94)
                .blur(radius: size * 0.07)

            ZStack {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                } else {
                    ZStack {
                        Color(white: 0.12)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(width: size, height: size)
                }
            }
            .clipShape(Circle())
            .overlay(
                // Subtle rim so the circle reads on dark art
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.06), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1, size * 0.015)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: size * 0.06, y: size * 0.03)
            .rotationEffect(.degrees(angle))
        }
    }
}

/// Compact circular art for the collapsed notch flank.
struct MiniVinylView: View {
    var artwork: NSImage?
    var isPlaying: Bool
    var accent: Color = .white

    var body: some View {
        VinylView(artwork: artwork, isPlaying: isPlaying, accent: accent, size: 22)
    }
}
