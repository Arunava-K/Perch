import Defaults
import Foundation

/// Catalog, download, and storage of GGML whisper models. Files live under
/// `~/Library/Application Support/Perch/models/` and are fetched on demand —
/// nothing is bundled with the app.
@MainActor
final class DictationModelStore: ObservableObject {
    struct ModelInfo: Identifiable, Hashable {
        let id: String          // canonical whisper model id, e.g. "base.en"
        let title: String
        let blurb: String
        let sizeBytes: Int64

        var isEnglishOnly: Bool { id.hasSuffix(".en") }
    }

    /// Curated catalog (multilingual variants alongside the .en ones).
    /// Sizes are the published ggml sizes, used only for display; downloads
    /// report real progress from Content-Length.
    static let catalog: [ModelInfo] = [
        ModelInfo(id: "tiny.en", title: "Tiny", blurb: "Fastest · English", sizeBytes: 77_700_000),
        ModelInfo(id: "base.en", title: "Base", blurb: "Balanced · English · recommended", sizeBytes: 147_950_000),
        ModelInfo(id: "small.en", title: "Small", blurb: "Accurate · English", sizeBytes: 487_140_000),
        ModelInfo(id: "tiny", title: "Tiny ML", blurb: "Fastest · Multilingual", sizeBytes: 77_700_000),
        ModelInfo(id: "base", title: "Base ML", blurb: "Balanced · Multilingual", sizeBytes: 147_950_000),
        ModelInfo(id: "small", title: "Small ML", blurb: "Accurate · Multilingual", sizeBytes: 487_140_000),
        ModelInfo(id: "large-v3-turbo", title: "Turbo", blurb: "Most accurate · Multilingual", sizeBytes: 1_630_000_000),
    ]

    static let defaultModelID = "base.en"

    static func info(for id: String) -> ModelInfo? {
        catalog.first { $0.id == id }
    }

    // MARK: Paths

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func modelURL(for id: String) -> URL {
        modelsDirectory.appendingPathComponent("ggml-\(id).bin")
    }

    /// A model counts as installed only if the file exists, is non-trivially
    /// sized, and carries the ggml magic (0x67676d6c, little-endian on disk) —
    /// partial/corrupt files don't.
    private static let ggmlMagic = Data([0x6c, 0x6d, 0x67, 0x67])

    static func isDownloaded(_ id: String) -> Bool {
        let url = modelURL(for: id)
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
              size > 1_000_000,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic == ggmlMagic else { return false }
        return true
    }

    // MARK: Instance state (Settings UI)

    @Published private(set) var installed: Set<String> = []
    @Published private(set) var downloading: Set<String> = []
    /// 0…1 per model id while downloading.
    @Published private(set) var progress: [String: Double] = [:]
    /// Last error message per model id, surfaced inline.
    @Published var failure: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        refresh()
    }

    func refresh() {
        installed = Set(Self.catalog.map(\.id).filter { Self.isDownloaded($0) })
    }

    // MARK: Download

    func download(_ id: String) {
        guard Self.info(for: id) != nil, !downloading.contains(id) else { return }
        let dest = Self.modelURL(for: id)
        let partial = dest.deletingLastPathComponent()
            .appendingPathComponent(dest.lastPathComponent + ".partial", isDirectory: false)
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: dest)

        downloading.insert(id)
        progress[id] = 0
        failure[id] = nil

        tasks[id] = Task { [weak self] in
            do {
                try await Self.fetch(id: id, to: partial) { fraction in
                    Task { @MainActor [weak self] in
                        self?.progress[id] = fraction
                    }
                }
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: partial, to: dest)
                await MainActor.run { [weak self] in
                    self?.progress[id] = 1
                    self?.installed.insert(id)
                    self?.downloading.remove(id)
                }
            } catch let error where self?.isCancellation(error) == true {
                try? FileManager.default.removeItem(at: partial)
                await MainActor.run { [weak self] in
                    self?.downloading.remove(id)
                    self?.progress[id] = 0
                }
            } catch {
                try? FileManager.default.removeItem(at: partial)
                await MainActor.run { [weak self] in
                    self?.failure[id] = error.localizedDescription
                    self?.downloading.remove(id)
                }
            }
        }
    }

    func cancelDownload(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    func delete(_ id: String) {
        cancelDownload(id)
        try? FileManager.default.removeItem(at: Self.modelURL(for: id))
        progress[id] = nil
        failure[id] = nil
        downloading.remove(id)
        installed.remove(id)
        // Never leave a deleted model selected.
        if Defaults[.dictationModelID] == id {
            Defaults[.dictationModelID] = Self.defaultModelID
        }
    }

    /// Streams the model to a temp file with progress. The file is only
    /// promoted to `.partial`/final after the ggml magic has been verified.
    private static func fetch(id: String, to partial: URL, onProgress: @escaping (Double) -> Void) async throws {
        guard let remote = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(id).bin") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 60

        let delegate = DownloadProgress(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Sanity: whisper ggml files start with the ggml magic (LE on disk).
        guard let handle = try? FileHandle(forReadingFrom: tempURL),
              let magic = try? handle.read(upToCount: 4),
              magic == ggmlMagic
        else {
            throw URLError(.cannotDecodeContentData)
        }
        try? handle.close()

        if FileManager.default.fileExists(atPath: partial.path) {
            try FileManager.default.removeItem(at: partial)
        }
        try FileManager.default.moveItem(at: tempURL, to: partial)
        onProgress(1)
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// URLSession download delegate that reports byte progress (throttled).
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    private var lastReport = Date.distantPast

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        guard Date().timeIntervalSince(lastReport) > 0.15 else { return }
        lastReport = Date()
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
