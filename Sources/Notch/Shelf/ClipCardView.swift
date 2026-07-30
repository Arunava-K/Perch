import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A single clip card. Click pastes (or toggles selection); hold enters
/// multi-select; drag exports one or many clips as files for drop targets.
struct ClipCardView: View {
    let item: ClipItem
    var isSelected: Bool = false
    var selectionMode: Bool = false
    var onPick: () -> Void = {}
    var onLongPress: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil
    var onDelete: () -> Void = {}
    var onShare: (() -> Void)? = nil
    var dragItems: () -> [ClipItem] = { [] }

    @State private var confirm = false
    @State private var confirmLabel = "Copied"
    @State private var hovering = false
    @State private var pressing = false

    private let cardSize = CGSize(width: 132, height: 118)
    private let radius: CGFloat = 13
    private let footerHeight: CGFloat = 26

    var body: some View {
        ZStack {
            cardChrome
            // AppKit owns click / long-press / drag — SwiftUI gestures fight the
            // non-activating notch panel and each other.
            CardInteractionView(
                onClick: activate,
                onLongPress: {
                    guard !selectionMode else { return }
                    onLongPress?()
                },
                onDrag: { event in
                    let batch = dragItems()
                    let items = batch.isEmpty ? [item] : batch
                    ClipDragExporter.beginDragging(items: items, event: event)
                },
                onPressingChanged: { pressing = $0 }
            )
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(pressing ? 0.96 : (hovering && !selectionMode ? 1.03 : 1))
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .animation(.easeOut(duration: 0.12), value: pressing)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .onHover { hovering = $0 }
        .help(tooltip)
        .contextMenu {
            if let onTogglePin {
                Button(item.isPinned ? "Unpin" : "Pin",
                       systemImage: item.isPinned ? "pin.slash" : "pin", action: onTogglePin)
            }
            if let onShare {
                Button("Share…", systemImage: "square.and.arrow.up", action: onShare)
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var cardChrome: some View {
        VStack(spacing: 0) {
            preview
                .frame(width: cardSize.width,
                       height: hasFooter ? cardSize.height - footerHeight : cardSize.height)
                .clipped()
            if hasFooter { footer }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(Color.white.opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.95) : .clear, lineWidth: 2)
        }
        .overlay(alignment: .topLeading) { leadingBadge }
        .overlay(alignment: .topTrailing) { formatTag }
        .overlay { confirmOverlay }
    }

    private var backgroundOpacity: Double {
        if isSelected { return 0.18 }
        if pressing { return 0.14 }
        return hovering ? 0.11 : 0.06
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text(let string):
            Text(string)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

        case .link(let url):
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)

        case .color(let hex):
            ZStack(alignment: .bottomLeading) {
                (Color(hexString: hex) ?? .gray)
                Text(hex.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(9)
            }

        case .image(let blobFile, _, _, _):
            ImageThumbnail(blobFile: blobFile, maxPixel: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .file(_, let path, _):
            FileThumbnail(path: path, size: CGSize(width: 80, height: 80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .locked(let type):
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 18))
                Text("Locked \(type)").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hasFooter: Bool {
        switch item.kind {
        case .file, .image: return false
        default: return true
        }
    }

    private var tooltip: String {
        if case .file(_, _, let name) = item.kind { return name }
        if selectionMode { return isSelected ? "Selected — drag to drop" : "Click to select" }
        return "Click to paste · Hold to multi-select · Drag to drop"
    }

    @ViewBuilder
    private var formatTag: some View {
        if let label = tagLabel {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(.black.opacity(0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .padding(6)
        }
    }

    private var tagLabel: String? {
        switch item.kind {
        case .file(_, let path, _):
            let ext = (path as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "FILE" : ext
        case .image:
            return "PNG"
        default:
            return nil
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: typeSymbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(item.sourceAppName ?? item.kind.typeName.capitalized)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 12)
        .frame(width: cardSize.width, height: footerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    private var typeSymbol: String {
        switch item.kind {
        case .text: return "textformat"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo"
        case .file: return "doc"
        case .locked: return "lock.fill"
        }
    }

    @ViewBuilder
    private var leadingBadge: some View {
        if selectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.45),
                                 isSelected ? .white : .white.opacity(0.2))
                .padding(6)
        } else if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.yellow)
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var confirmOverlay: some View {
        if confirm {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.6))
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                    Text(confirmLabel).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func activate() {
        if selectionMode {
            onPick()
            return
        }
        let outcome = PasteService.paste(item)
        Haptics.tap()
        confirmLabel = outcome == .pasted ? "Pasted" : "Copied"
        withAnimation(.easeOut(duration: 0.15)) { confirm = true }
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            onPick()
            withAnimation(.easeIn(duration: 0.2)) { confirm = false }
        }
    }
}

// MARK: - AppKit interaction (click / hold / drag)

/// Owns mouse events so long-press and multi-drag work inside the non-activating
/// notch panel (SwiftUI Button + gestures are unreliable there).
private struct CardInteractionView: NSViewRepresentable {
    var onClick: () -> Void
    var onLongPress: () -> Void
    var onDrag: (NSEvent) -> Void
    var onPressingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> CardHitView {
        let view = CardHitView()
        view.onClick = onClick
        view.onLongPress = onLongPress
        view.onDrag = onDrag
        view.onPressingChanged = onPressingChanged
        return view
    }

    func updateNSView(_ nsView: CardHitView, context: Context) {
        nsView.onClick = onClick
        nsView.onLongPress = onLongPress
        nsView.onDrag = onDrag
        nsView.onPressingChanged = onPressingChanged
    }
}

private final class CardHitView: NSView {
    var onClick: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onDrag: ((NSEvent) -> Void)?
    var onPressingChanged: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var longPressTimer: Timer?
    private var didLongPress = false
    private var didDrag = false
    private let dragThreshold: CGFloat = 5
    private let longPressDuration: TimeInterval = 0.4

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownEvent = event
        didLongPress = false
        didDrag = false
        onPressingChanged?(true)
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mouseDownEvent != nil, !self.didDrag else { return }
                self.didLongPress = true
                self.onPressingChanged?(false)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                self.onLongPress?()
            }
        }
        RunLoop.main.add(longPressTimer!, forMode: .common)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, !didDrag else { return }
        let a = down.locationInWindow
        let b = event.locationInWindow
        let dist = hypot(a.x - b.x, a.y - b.y)
        guard dist >= dragThreshold else { return }

        // Movement cancels long-press and starts a drag.
        longPressTimer?.invalidate()
        longPressTimer = nil
        didDrag = true
        onPressingChanged?(false)
        onDrag?(down)
    }

    override func mouseUp(with event: NSEvent) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        onPressingChanged?(false)
        defer {
            mouseDownEvent = nil
            didLongPress = false
            didDrag = false
        }
        // Click only if we neither long-pressed nor dragged.
        if !didLongPress && !didDrag {
            onClick?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Keep tracking; drag may continue outside.
    }

    deinit {
        longPressTimer?.invalidate()
    }
}
