import AppKit

/// A corner handle for resizing the popover, which has no resizable frame of its own.
/// Reports how far the pointer has moved since the drag began, in screen points
/// (width grows to the right, height grows downward).
final class ResizeGrip: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onReset: (() -> Void)?

    private var start: NSPoint?

    override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 14) }
    override var mouseDownCanMoveWindow: Bool { false }
    // A pinned popover may not be key when the user reaches for the grip; the first click should still drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        applyLanguage()
        NotificationCenter.default.addObserver(forName: Language.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyLanguage()
        }
    }

    private func applyLanguage() {
        toolTip = tr("拖曳可調整視窗大小，按兩下恢復預設大小", "Drag to resize; double-click to restore the default size")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        // Three short diagonals, the classic size-grip look.
        NSColor.secondaryLabelColor.setStroke()
        let b = bounds
        for i in 0..<3 {
            let inset = CGFloat(i) * 4 + 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: b.maxX - inset, y: b.minY + 1))
            path.line(to: NSPoint(x: b.maxX - 1, y: b.minY + inset))
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            start = nil
            onReset?()
            return
        }
        start = screenPoint(event)
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = screenPoint(event)
        onDrag?(CGSize(width: p.x - start.x, height: start.y - p.y))
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
    }

    /// Screen coordinates stay put while the popover window itself changes size underneath.
    private func screenPoint(_ event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}
