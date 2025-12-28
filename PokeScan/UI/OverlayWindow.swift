import SwiftUI

@MainActor
final class OverlayWindowController: ObservableObject {
    weak var window: NSWindow?
    @Published var alwaysOnTop: Bool = true

    func attach(window: NSWindow) {
        self.window = window
        apply()
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
        apply()
    }

    private func apply() {
        window?.level = alwaysOnTop ? .floating : .normal
    }
}

final class OverlayWindow: NSPanel {
    init(rootView: some View, controller: OverlayWindowController) {
        let contentRect = NSRect(x: 200, y: 200, width: 300, height: 200)
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false  // We'll handle shadow ourselves
        hidesOnDeactivate = false

        // Create hosting view with transparent background
        let hosting = TransparentHostingView(rootView: rootView)
        hosting.frame = contentRect
        contentView = hosting

        controller.attach(window: self)
    }

    override var canBecomeKey: Bool { false }
}

// Custom hosting view that ensures full transparency
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Remove any layer background
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Force transparent background on window
        window?.backgroundColor = .clear
        window?.isOpaque = false
        // Also ensure view and layer are clear
        layer?.backgroundColor = .clear
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    override func updateLayer() {
        layer?.backgroundColor = .clear
    }
}
