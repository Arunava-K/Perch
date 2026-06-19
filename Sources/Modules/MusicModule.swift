import SwiftUI

@MainActor
final class MusicModule: NotchModule {
    let id = "music"
    let title = "Music"
    let icon = "music.note"

    let music: MusicManager
    init(music: MusicManager) { self.music = music }

    var indicator: Bool { music.hasActivePlayer }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(NowPlayingDetailView(music: music))
    }
}
