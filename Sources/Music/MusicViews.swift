import SwiftUI

/// A small animated audio equalizer (random bar heights while playing).
struct EqualizerView: View {
    var isPlaying: Bool
    var barColor: Color = .white
    var maxHeight: CGFloat = 16

    @State private var heights: [CGFloat] = [0.4, 0.8, 0.5, 0.9]
    private let timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(barColor)
                    .frame(width: 2.5, height: max(3, heights[i] * maxHeight))
            }
        }
        .frame(height: maxHeight)
        .opacity(isPlaying ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.16), value: heights)
        .onReceive(timer) { _ in
            guard isPlaying else { return }
            heights = heights.map { _ in CGFloat.random(in: 0.25...1.0) }
        }
    }
}

/// Album art tucked into the left corner and an equalizer into the right,
/// flanking the camera while the notch is idle.
struct CollapsedMediaView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 0) {
            artwork
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.leading, 16)

            Spacer(minLength: 0)

            EqualizerView(isPlaying: music.isPlaying, barColor: music.accentColor, maxHeight: 13)
                .padding(.trailing, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = music.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack { Color.white.opacity(0.15); Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.white) }
        }
    }
}

/// Full now-playing row (artwork, title/artist, transport) for the open notch.
struct NowPlayingBar: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(music.title.isEmpty ? "Not Playing" : music.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                transportButton("backward.fill", size: 12) { music.previousTrack() }
                transportButton(music.isPlaying ? "pause.fill" : "play.fill", size: 15,
                                tint: music.accentColor) { music.togglePlayPause() }
                transportButton("forward.fill", size: 12) { music.nextTrack() }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = music.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack { Color.white.opacity(0.12); Image(systemName: "music.note").foregroundStyle(.white) }
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, tint: Color = .white,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
