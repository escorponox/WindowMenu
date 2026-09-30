import AppKit

struct TaskItem {
    let window: WindowInfo
    let isFocused: Bool
}

/// Vista dibujada dentro del botón del status item: una "barra de tareas" de ventanas.
final class TaskbarView: NSView {

    var items: [TaskItem] = [] { didSet { hovered = nil; needsDisplay = true } }
    var showTitles = true { didSet { needsDisplay = true } }
    var maxTotalWidth: CGFloat = 700 { didSet { needsDisplay = true } }

    var onClick: ((TaskItem) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var hovered: Int?

    private let iconSize: CGFloat = 16
    private let pad: CGFloat = 6
    private let gap: CGFloat = 5
    private let maxItemWidth: CGFloat = 170
    private let iconOnlyWidth: CGFloat = 28

    private var font: NSFont { NSFont.menuBarFont(ofSize: 12) }

    // MARK: Layout

    private func itemWidths() -> [CGFloat] {
        guard !items.isEmpty else { return [] }
        guard showTitles else { return Array(repeating: iconOnlyWidth, count: items.count) }
        let cap = min(maxItemWidth, max(iconOnlyWidth, maxTotalWidth / CGFloat(items.count)))
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return items.map { item in
            let textW = (item.window.label as NSString).size(withAttributes: attrs).width
            let natural = pad + iconSize + gap + ceil(textW) + pad
            return cap < 60 ? iconOnlyWidth : min(cap, natural)
        }
    }

    private func itemRects() -> [NSRect] {
        var x: CGFloat = 0
        return itemWidths().map { w in
            defer { x += w + 2 }
            return NSRect(x: x, y: 0, width: w, height: bounds.height)
        }
    }

    var preferredWidth: CGFloat {
        let widths = itemWidths()
        return widths.isEmpty ? iconOnlyWidth : widths.reduce(0, +) + CGFloat(widths.count - 1) * 2
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !items.isEmpty else { return }

        let rects = itemRects()
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail

        for (i, item) in items.enumerated() {
            let r = rects[i]
            let bg = r.insetBy(dx: 0, dy: 2)
            let path = NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5)

            if item.isFocused {
                NSColor.labelColor.withAlphaComponent(0.22).setFill()
                path.fill()
                // Indicador tipo Windows
                let barW = min(bg.width - 8, 24)
                let bar = NSRect(x: bg.midX - barW / 2, y: bg.minY + 1, width: barW, height: 2)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
            } else if hovered == i {
                NSColor.labelColor.withAlphaComponent(0.10).setFill()
                path.fill()
            }

            let alpha: CGFloat = item.window.isMinimized ? 0.4 : 1
            let showText = r.width > iconOnlyWidth + 1
            let iconX = showText ? r.minX + pad : r.midX - iconSize / 2
            let iconRect = NSRect(x: iconX, y: r.midY - iconSize / 2, width: iconSize, height: iconSize)
            item.window.appIcon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: alpha)

            if showText {
                let color: NSColor = item.window.isMinimized ? .tertiaryLabelColor : .labelColor
                let f = item.isFocused ? NSFont.boldSystemFont(ofSize: font.pointSize) : font
                let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: para]
                let textX = iconRect.maxX + gap
                let h = ceil(f.ascender - f.descender)
                let textRect = NSRect(x: textX, y: r.midY - h / 2, width: r.maxX - pad - textX, height: h)
                (item.window.label as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            }
        }
    }

    // MARK: Mouse

    // El panel nunca es "key": sin esto el primer clic se perdería.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func index(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return itemRects().firstIndex { $0.contains(p) }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onRightClick?(event); return }
        if let i = index(at: event), i < items.count { onClick?(items[i]) }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let i = index(at: event)
        guard i != hovered else { return }
        hovered = i
        toolTip = i.map { items[$0].window.tooltip }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }
}
