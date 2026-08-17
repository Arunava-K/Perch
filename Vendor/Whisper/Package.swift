// swift-tools-version: 6.0
import PackageDescription

/// Vendored whisper.cpp for local, offline speech-to-text.
///
/// The XCFramework is the official prebuilt macOS slice from whisper.cpp
/// v1.9.2 (Metal-accelerated, metallib embedded in the binary), trimmed of
/// iOS/tvOS slices and dSYMs:
/// https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.2
/// Regenerate with:
///   xcodebuild -create-xcframework \
///     -framework <unzipped>/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework \
///     -output whisper.xcframework
let package = Package(
    name: "Whisper",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "whisper", targets: ["whisper"])
    ],
    targets: [
        .binaryTarget(name: "whisper", path: "whisper.xcframework")
    ]
)
