import AVFoundation
import CoreMedia
import AppKit

/// Owns the capture session for the webcam mirror. Opt-in: the session only runs
/// while the mirror is visible (started on appear, stopped on disappear), so the
/// camera is never live in the background.
///
/// Not `@MainActor` — `AVCaptureSession` configuration and start/stop block and
/// must run off the main thread; `@Published` updates are hopped back to main.
final class CameraManager: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false
    /// Width / height of the live feed, so the UI can size the preview to fill
    /// the width with the height following (no letterboxing). Defaults to 16:9.
    @Published private(set) var aspectRatio: CGFloat = 16.0 / 9.0

    private let sessionQueue = DispatchQueue(label: "com.arunavak.perch.camera")
    private var configured = false
    private var wantsRunning = false
    private var requestingAccess = false

    /// Request access if needed, then start. Called when the mirror appears.
    func requestAndStart() {
        sessionQueue.async { [weak self] in self?.wantsRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setAuthorization(.authorized)
            start()
        case .notDetermined:
            guard !requestingAccess else { return }
            requestingAccess = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.requestingAccess = false
                    self.setAuthorization(AVCaptureDevice.authorizationStatus(for: .video))
                    if granted { self.start() }
                }
            }
        default:
            setAuthorization(AVCaptureDevice.authorizationStatus(for: .video))
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.wantsRunning else { return }
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
            self.setRunning(true)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            self.setRunning(false)
        }
    }

    /// Configure the session once, on the session queue. Prefers the front camera.
    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = .high
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)

            if (try? device.lockForConfiguration()) != nil {
                // The .high preset picks a cropped/zoomed 16:9 format on the newer
                // Mac cameras (e.g. 1920x1080 is a center crop of the sensor). The
                // full field of view is the highest-pixel *landscape* format —
                // usually 4:3 — which is what Photo Booth shows. Select it.
                if let widest = device.formats
                    .filter({ let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription); return d.width > d.height })
                    .max(by: { formatArea($0) < formatArea($1) }) {
                    device.activeFormat = widest
                }

                // Turn off Center Stage (auto-zoom to follow the face) if supported.
                if device.activeFormat.isCenterStageSupported {
                    AVCaptureDevice.centerStageControlMode = .app
                    AVCaptureDevice.isCenterStageEnabled = false
                }

                device.unlockForConfiguration()
            }

            publishAspect(of: device.activeFormat)
        }
        session.commitConfiguration()
    }

    private func formatArea(_ format: AVCaptureDevice.Format) -> Int {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(d.width) * Int(d.height)
    }

    private func publishAspect(of format: AVCaptureDevice.Format) {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard d.width > 0, d.height > 0 else { return }
        let ratio = CGFloat(d.width) / CGFloat(d.height)
        DispatchQueue.main.async { self.aspectRatio = ratio }
    }

    private func setAuthorization(_ status: AVAuthorizationStatus) {
        DispatchQueue.main.async { self.authorization = status }
    }

    private func setRunning(_ running: Bool) {
        DispatchQueue.main.async { self.isRunning = running }
    }
}
