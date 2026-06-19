import SwiftUI

/// The Music tab: a large square album art (filling the notch height) with
/// title/artist, a progress bar, and transport controls.
struct NowPlayingDetailView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        if music.hasActivePlayer {
            GeometryReader { geo in
                let side = geo.size.height
                HStack(spacing: 18) {
                    artwork
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 11) {
                        VStack(alignment: .leading, spacing: 3) {
                            MarqueeText(text: music.title.isEmpty ? "Not Playing" : music.title,
                                        fontSize: 15, weight: .semibold, color: .white)
                            MarqueeText(text: music.artist,
                                        fontSize: 12.5, weight: .regular, color: .white.opacity(0.55))
                        }
                        progress
                    }

                    Spacer(minLength: 14)

                    HStack(spacing: 22) {
                        control("backward.fill", 15) { music.previousTrack() }
                        control(music.isPlaying ? "pause.fill" : "play.fill", 18, prominent: true) {
                            music.togglePlayPause()
                        }
                        control("forward.fill", 15) { music.nextTrack() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Nothing playing")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = music.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.1)
                Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white)
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 3)

            HStack {
                Text(timeString(music.elapsed))
                Spacer()
                Text(timeString(music.duration))
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var fraction: Double {
        music.duration > 0 ? min(1, music.elapsed / music.duration) : 0
    }

    private func timeString(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func control(_ symbol: String, _ size: CGFloat, prominent: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle().fill(.white.opacity(0.14)).frame(width: 38, height: 38)
                }
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.9))
    }
}
