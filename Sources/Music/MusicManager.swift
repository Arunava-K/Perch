import AppKit

/// Polls Apple Music and Spotify (via AppleScript) for now-playing state and
/// exposes simple transport controls. Only queries apps that are already
/// running, so it never launches a player.
@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var hasActivePlayer = false
    @Published private(set) var isPlaying = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var activeApp: Player?
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0

    enum Player: String {
        case music = "Music"
        case spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    }

    private var timer: Timer?
    private var tickTimer: Timer?
    private var artworkURLString: String?
    private var mockMode = false

    /// Inject a fake now-playing state for UI verification (no real player).
    func injectMock() {
        mockMode = true
        hasActivePlayer = true
        isPlaying = true
        title = "Midnight City"
        artist = "M83"
        activeApp = .spotify
        let art = NSImage(size: NSSize(width: 100, height: 100))
        art.lockFocus()
        NSGradient(colors: [.systemPink, .systemPurple])?.draw(in: NSRect(x: 0, y: 0, width: 100, height: 100), angle: -45)
        art.unlockFocus()
        artwork = art
    }

    func start() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Smoothly advance elapsed time between polls.
        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.duration > 0 else { return }
                self.elapsed = min(self.duration, self.elapsed + 1)
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.tickTimer = ticker

        refresh()
    }

    // MARK: Transport

    func togglePlayPause() { control("playpause") }
    func nextTrack() { control("next track") }
    func previousTrack() { control("previous track") }

    private func control(_ command: String) {
        guard let app = activeApp else { return }
        _ = runScript("tell application \"\(app.rawValue)\" to \(command)")
        refresh()
    }

    // MARK: Polling

    func refresh() {
        guard !mockMode else { return }
        // Prefer whichever player is actually playing; fall back to any running one.
        if let state = query(.spotify), state.isPlaying { apply(state, .spotify); return }
        if let state = query(.music), state.isPlaying { apply(state, .music); return }
        if let state = query(.spotify) { apply(state, .spotify); return }
        if let state = query(.music) { apply(state, .music); return }
        hasActivePlayer = false
        isPlaying = false
        activeApp = nil
    }

    private struct State {
        var isPlaying: Bool
        var title: String
        var artist: String
        var artworkURL: String?
        var elapsed: Double
        var duration: Double
    }

    private func query(_ player: Player) -> State? {
        guard isRunning(player.bundleID) else { return nil }
        // Spotify exposes an artwork URL and ms durations; Music doesn't.
        let artworkExpr = player == .spotify ? "(artwork url of current track)" : "\"\""
        let durationExpr = player == .spotify
            ? "((duration of current track) / 1000)"
            : "(duration of current track)"
        let script = """
        tell application "\(player.rawValue)"
          if player state is stopped then return "stopped"
          set t to (name of current track)
          set a to (artist of current track)
          return (player state as string) & "\\n" & t & "\\n" & a & "\\n" & \(artworkExpr) & "\\n" & (player position) & "\\n" & \(durationExpr)
        end tell
        """
        guard let out = runScript(script), out != "stopped" else { return nil }
        let parts = out.components(separatedBy: "\n")
        guard parts.count >= 3 else { return nil }
        return State(
            isPlaying: parts[0] == "playing",
            title: parts[1],
            artist: parts[2],
            artworkURL: parts.count >= 4 && !parts[3].isEmpty ? parts[3] : nil,
            elapsed: parts.count >= 5 ? Double(parts[4]) ?? 0 : 0,
            duration: parts.count >= 6 ? Double(parts[5]) ?? 0 : 0
        )
    }

    private func apply(_ state: State, _ player: Player) {
        hasActivePlayer = true
        activeApp = player
        isPlaying = state.isPlaying
        title = state.title
        artist = state.artist
        elapsed = state.elapsed
        duration = state.duration
        loadArtwork(urlString: state.artworkURL, fallbackApp: player)
    }

    private func loadArtwork(urlString: String?, fallbackApp: Player) {
        if let urlString, urlString != artworkURLString, let url = URL(string: urlString) {
            artworkURLString = urlString
            Task { [weak self] in
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = NSImage(data: data) {
                    await MainActor.run { self?.artwork = image }
                }
            }
        } else if urlString == nil {
            // Apple Music: use the app icon as artwork.
            artworkURLString = nil
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: fallbackApp.bundleID).first,
               let icon = app.icon {
                artwork = icon
            }
        }
    }

    // MARK: Helpers

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
