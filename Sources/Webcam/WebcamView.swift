import SwiftUI
import AVFoundation

/// The webcam mirror shown in the expanded notch. Starts the camera on appear
/// and stops it on disappear, so the camera is only live while visible.
struct WebcamView: View {
    @ObservedObject var camera: CameraManager
    @State private var mirrored = true

    var body: some View {
        Group {
            switch camera.authorization {
            case .authorized:
                preview
            case .denied, .restricted:
                message(icon: "video.slash.fill",
                        title: "Camera access denied",
                        button: "Open System Settings") { camera.openSystemSettings() }
            default:
                message(icon: "video.fill",
                        title: "Enable the camera mirror",
                        button: "Enable Camera") { camera.requestAndStart() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { camera.requestAndStart() }
        .onDisappear { camera.stop() }
    }

    private var preview: some View {
        CameraPreview(session: camera.session, mirrored: mirrored)
            .aspectRatio(NotchViewModel.webcamDisplayAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                Button { mirrored.toggle() } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(PressableStyle())
                .help(mirrored ? "Mirrored" : "Not mirrored")
                .padding(8)
            }
            .padding(.horizontal, NotchViewModel.webcamSideInset)
    }

    private func message(icon: String, title: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Button(button, action: action)
                .buttonStyle(PressableStyle())
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.16)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` and keeps it sized to the view.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.setMirrored(mirrored)
    }

    final class PreviewNSView: NSView {
        private let previewLayer = AVCaptureVideoPreviewLayer()

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }

        func setMirrored(_ mirrored: Bool) {
            guard let connection = previewLayer.connection else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirrored != mirrored {
                connection.isVideoMirrored = mirrored
            }
        }
    }
}
