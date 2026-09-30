import AppKit

/// Panel transparente que se coloca encima de la barra de menús de un monitor.
final class TaskbarPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        // En todos los Spaces, fija en Mission Control y fuera de ⌘`.
        // Sin .fullScreenAuxiliary → no aparece sobre apps a pantalla completa.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
