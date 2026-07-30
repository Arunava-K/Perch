import SwiftUI
import Defaults

/// The Music tab: square cover or spinning vinyl, title/artist, progress, transport.
struct NowPlayingDetailView: View {
    @ObservedObject var music: MusicManager
    @Default(.musicVinylMode) private var vinylMode

    var body: some View {
        Group {
            if music.hasActivePlayer {
                GeometryReader { geo in
                    let side = min(geo.size.height, vinylMode ? geo.size.height * 0.95 : geo.size.height)
                    HStack(spacing: 18) {
                        art(side: side)
                            .frame(width: side, height: side)

                        VStack(alignment: .leading, spacing: 11) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    MarqueeText(text: music.title.isEmpty ? "Not Playing" : music.title,
                                                fontSize: 15, weight: .semibold, color: .white)
                                    MarqueeText(text: music.artist,
                                                fontSize: 12.5, weight: .regular, color: .white.opacity(0.55))
                                }
                                Spacer(minLength: 0)
                                vinylToggle
                            }
                            progress
                        }

                        Spacer(minLength: 10)

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
                .transition(.tabContent)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Nothing playing")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    vinylToggle
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.tabContent)
            }
        }
        .animation(Motion.content, value: music.hasActivePlayer)
        .animation(Motion.content, value: vinylMode)
    }

    // MARK: Artwork

    @ViewBuilder
    private func art(side: CGFloat) -> some View {
        Group {
            if vinylMode {
                VinylView(
                    artwork: music.artwork,
                    isPlaying: music.isPlaying,
                    accent: music.accentColor,
                    size: side
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
            } else {
                artworkSquare(side: side)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
            }
        }
    }

    @ViewBuilder
    private func artworkSquare(side: CGFloat) -> some View {
        ZStack {
            if let art = music.artwork {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: side, height: side, alignment: .center)
                    .clipped()
                    .id(ObjectIdentifier(art))
                    .transition(.opacity)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white)
                }
                .frame(width: side, height: side)
                .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(Motion.crossfade, value: music.artwork != nil)
        .animation(Motion.crossfade, value: music.title)
    }

    private var vinylToggle: some View {
        Button {
            withAnimation(Motion.snappy) {
                vinylMode.toggle()
            }
            Haptics.tap()
        } label: {
            Image(systemName: vinylMode ? "square.grid.2x2" : "circle.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.08)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.92))
        .help(vinylMode ? "Square cover" : "Vinyl mode")
    }

    // MARK: Progress / controls

    private var progress: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(vinylMode ? music.accentColor.opacity(0.9) : .white.opacity(0.9))
                        .frame(width: max(0, geo.size.width * fraction))
                        .animation(Motion.metric, value: fraction)
                }
            }
            .frame(height: 3)

            HStack {
                Text(timeString(music.elapsed))
                    .contentTransition(.numericText(value: music.elapsed))
                Spacer()
                Text(timeString(music.duration))
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
            .animation(Motion.metric, value: music.elapsed)
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
                    Circle()
                        .fill(vinylMode ? music.accentColor.opacity(0.22) : .white.opacity(0.14))
                        .frame(width: 38, height: 38)
                }
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.9))
    }
}
