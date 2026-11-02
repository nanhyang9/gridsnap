import Cocoa

// Shake a window left and right while dragging it by its title bar: a Windows 11 style layouts panel appears at the top
// of the screen. Keep dragging onto a zone and release to snap the window there; release anywhere else and nothing happens.

func frac(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: y, width: w, height: h) }
let layouts: [[NSRect]] = [   // fractions of the visible screen, origin bottom-left (same as presets)
    [frac(0, 0, 0.5, 1), frac(0.5, 0, 0.5, 1)],
    [frac(0, 0, 2.0 / 3, 1), frac(2.0 / 3, 0, 1.0 / 3, 1)],
    [frac(0, 0, 1.0 / 3, 1), frac(1.0 / 3, 0, 1.0 / 3, 1), frac(2.0 / 3, 0, 1.0 / 3, 1)],
    [frac(0, 0, 0.5, 1), frac(0.5, 0.5, 0.5, 0.5), frac(0.5, 0, 0.5, 0.5)],
    [frac(0, 0.5, 0.5, 0.5), frac(0.5, 0.5, 0.5, 0.5), frac(0, 0, 0.5, 0.5), frac(0.5, 0, 0.5, 0.5)],
    [frac(0, 0, 0.25, 1), frac(0.25, 0, 0.5, 1), frac(0.75, 0, 0.25, 1)],
]

final class LayoutsView: NSView {
    static let pad: CGFloat = 12, thumbW: CGFloat = 96, perRow = 3
    static var rowCount: Int { (layouts.count + perRow - 1) / perRow }
    var thumbH: CGFloat = 54   // follows the screen's aspect ratio
    var hover: (layout: Int, zone: Int)?
    var size: NSSize {
        let p = LayoutsView.pad, n = CGFloat(LayoutsView.perRow), r = CGFloat(LayoutsView.rowCount)
        return NSSize(width: n * LayoutsView.thumbW + (n + 1) * p, height: r * thumbH + (r + 1) * p)
    }

    func thumb(_ i: Int) -> NSRect {
        let p = LayoutsView.pad, w = LayoutsView.thumbW
        let col = CGFloat(i % LayoutsView.perRow), row = CGFloat(i / LayoutsView.perRow)
        return NSRect(x: p + col * (w + p), y: bounds.maxY - p - thumbH - row * (thumbH + p), width: w, height: thumbH)
    }
    func zoneRect(_ i: Int, _ j: Int) -> NSRect {
        let t = thumb(i), z = layouts[i][j]
        return NSRect(x: t.minX + z.minX * t.width, y: t.minY + z.minY * t.height, width: z.width * t.width, height: z.height * t.height)
    }
    func zone(at p: NSPoint) -> (layout: Int, zone: Int)? {
        for i in layouts.indices { for j in layouts[i].indices where zoneRect(i, j).contains(p) { return (i, j) } }
        return nil
    }

    override func draw(_ dirty: NSRect) {
        for i in layouts.indices { for j in layouts[i].indices {
            let on = hover?.layout == i && hover?.zone == j
            let p = NSBezierPath(roundedRect: zoneRect(i, j).insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            (on ? NSColor.controlAccentColor.withAlphaComponent(0.85) : NSColor.white.withAlphaComponent(0.12)).setFill(); p.fill()
            NSColor.white.withAlphaComponent(on ? 0.7 : 0.3).setStroke(); p.stroke()
        }}
    }
}

func overlayPanel(level: NSWindow.Level) -> NSPanel {   // never takes clicks: the dragging app owns the mouse, we hit-test ourselves
    let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = level
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.ignoresMouseEvents = true
    p.hidesOnDeactivate = false
    p.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
    return p
}
let layoutsView = LayoutsView()
let layoutsPanel: NSPanel = {
    let p = overlayPanel(level: .popUpMenu)   // above the window being dragged
    p.contentView = glass(around: layoutsView)
    p.appearance = NSAppearance(named: .darkAqua)
    return p
}()
let zonePreview: NSPanel = {   // outline of where the window will land
    let p = overlayPanel(level: .floating)
    let v = NSView(); v.wantsLayer = true
    v.layer?.cornerRadius = 10; v.layer?.borderWidth = 2
    v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
    v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
    p.contentView = v
    return p
}()

final class ShakeTracker {
    static let titleBand: CGFloat = 56        // how far below a window's top edge a press still counts as its title bar
    static let minStroke: CGFloat = 30        // shortest horizontal swing that counts
    static let reversalsNeeded = 3            // left-right-left-right = two shakes
    static let within: TimeInterval = 1.5     // all of them inside this many seconds

    var down: NSPoint?, looked = false
    var win: AXUIElement?, start: (CGPoint, CGSize)?
    var dir: CGFloat = 0, anchor: CGFloat = 0, extreme: CGFloat = 0, reversals: [TimeInterval] = []
    var showing = false, screen: NSScreen = .main!, hover: (layout: Int, zone: Int)?

    func mouseDown() {
        if showing { hidePanels() }
        reset()
        guard defaults.bool(forKey: "shakeLayouts") else { return }
        let m = NSEvent.mouseLocation
        down = m; anchor = m.x; extreme = m.x
    }
    func dragged() {
        guard let d = down else { return }
        let m = NSEvent.mouseLocation
        if showing { hoverAt(m); return }
        if !looked { looked = true; lookUp(d) }   // on the first drag, not every click: plain clicks cost no AX calls
        guard win != nil else { return }
        if shook(m.x) { show() }
    }
    func mouseUp() {
        defer { reset() }
        guard showing else { return }
        hidePanels()
        guard let h = hover, let w = win else { return }
        let r = screenFrame(fraction: layouts[h.layout][h.zone], on: screen)
        if let s = start { lastSnap = (w, s.0, s.1) }   // undo puts it back where the drag began
        remember(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { applyFrame(w, r) }   // let the app finish its own drag first
    }

    func reset() {
        down = nil; looked = false; win = nil; start = nil
        dir = 0; reversals = []; showing = false; hover = nil
    }
    func lookUp(_ d: NSPoint) {   // was the press on a window's title bar?
        guard let w = windowAt(d), let f = axFrame(w) else { return }
        let y = NSScreen.screens[0].frame.maxY - d.y - f.0.y   // press distance below the window's top edge
        guard y >= 0, y <= ShakeTracker.titleBand, d.x >= f.0.x, d.x <= f.0.x + f.1.width else { return }
        win = w; start = f
    }
    func shook(_ x: CGFloat) -> Bool {
        if dir == 0 {   // first swing: also proves the window really moves with the mouse (not a text selection etc.)
            guard abs(x - anchor) >= ShakeTracker.minStroke else { return false }
            guard let w = win, let s = start, let f = axFrame(w), hypot(f.0.x - s.0.x, f.0.y - s.0.y) >= 10 else { win = nil; return false }
            dir = x > anchor ? 1 : -1; extreme = x
            return false
        }
        if (x - extreme) * dir > 0 { extreme = x; return false }   // still going the same way
        guard (extreme - x) * dir >= ShakeTracker.minStroke else { return false }   // turned back far enough
        let now = ProcessInfo.processInfo.systemUptime
        anchor = extreme; extreme = x; dir = -dir
        reversals = reversals.filter { now - $0 <= ShakeTracker.within } + [now]
        return reversals.count >= ShakeTracker.reversalsNeeded
    }

    func show() {
        showing = true; hover = nil
        screen = screenUnderCursor()
        let v = screen.visibleFrame
        layoutsView.thumbH = (LayoutsView.thumbW * v.height / v.width).rounded()
        layoutsView.hover = nil
        let s = layoutsView.size
        layoutsPanel.setFrame(NSRect(x: v.midX - s.width / 2, y: v.maxY - s.height - 8, width: s.width, height: s.height), display: true)
        layoutsView.frame = layoutsPanel.contentView!.bounds
        layoutsView.needsDisplay = true
        layoutsPanel.alphaValue = 0
        layoutsPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; layoutsPanel.animator().alphaValue = 1 }
        hoverAt(NSEvent.mouseLocation)
    }
    func hoverAt(_ m: NSPoint) {
        let h = layoutsView.zone(at: layoutsView.convert(layoutsPanel.convertPoint(fromScreen: m), from: nil))
        guard h?.layout != hover?.layout || h?.zone != hover?.zone else { return }
        hover = h; layoutsView.hover = h; layoutsView.needsDisplay = true
        if let h {
            zonePreview.setFrame(screenFrame(fraction: layouts[h.layout][h.zone], on: screen), display: true)
            zonePreview.orderFrontRegardless()
        } else {
            zonePreview.orderOut(nil)
        }
    }
    func hidePanels() {
        zonePreview.orderOut(nil)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.10; layoutsPanel.animator().alphaValue = 0 }) {
            if !shake.showing { layoutsPanel.orderOut(nil) }
        }
    }
}
let shake = ShakeTracker()

func installShakeMonitor() {   // global monitors only see other apps' events, which is exactly what we want here
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { e in
        switch e.type {
        case .leftMouseDown: shake.mouseDown()
        case .leftMouseDragged: shake.dragged()
        default: shake.mouseUp()
        }
    }
}
