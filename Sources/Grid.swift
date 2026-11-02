import Cocoa

func cellRange(_ lo: CGFloat, _ hi: CGFloat, _ n: Int) -> ClosedRange<Int> {
    let a = Int((lo * CGFloat(n)).rounded()), b = Int((hi * CGFloat(n)).rounded()) - 1
    let c = min(max(Int((lo + hi) / 2 * CGFloat(n)), 0), n - 1)
    return a <= b ? max(a, 0)...min(b, n - 1) : c...c
}

final class GridView: NSView {
    var start: (Int, Int)?, end: (Int, Int)?
    var active = false, moved = false, pending = false
    var hoverCell: (Int, Int)?   // cell under the cursor before a drag starts
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    var grid: NSRect { bounds.insetBy(dx: 14, dy: 14) }
    func cell(_ e: NSEvent) -> (Int, Int) {
        let p = convert(e.locationInWindow, from: nil)
        return (min(max(Int((p.x - grid.minX) / grid.width * CGFloat(cols)), 0), cols - 1),
                min(max(Int((p.y - grid.minY) / grid.height * CGFloat(rows)), 0), rows - 1))
    }
    var selection: (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
        guard let s = start, let e = end else { return nil }
        return (min(s.0, e.0)...max(s.0, e.0), min(s.1, e.1)...max(s.1, e.1))
    }
    var selectionFraction: NSRect? {
        guard let s = selection else { return nil }
        return NSRect(x: Double(s.x.lowerBound) / Double(cols), y: Double(s.y.lowerBound) / Double(rows),
                      width: Double(s.x.count) / Double(cols), height: Double(s.y.count) / Double(rows))
    }

    var ghosts: [NSRect] = []
    var original: (CGPoint, CGSize)?   // window frame when the grid opened, restored on cancel
    var selectionFrame: NSRect? { selectionFraction.map { screenFrame(fraction: $0, on: targetScreen) } }
    func preview() {   // live: the window follows the selection and snaps back when there is none
        guard let win = targetWindow else { return }
        if let r = selectionFrame { applyFrame(win, r); moved = true } else if moved, let o = original { axSet(win, o.0, o.1) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with e: NSEvent) {
        guard active else { return }
        let c = grid.contains(convert(e.locationInWindow, from: nil)) ? cell(e) : nil
        guard c?.0 != hoverCell?.0 || c?.1 != hoverCell?.1 else { return }
        hoverCell = c; needsDisplay = true
    }
    override func mouseExited(with e: NSEvent) { if hoverCell != nil { hoverCell = nil; needsDisplay = true } }

    override func mouseDown(with e: NSEvent) {
        guard active else { return }
        hoverCell = nil
        start = cell(e); end = start; pending = false; needsDisplay = true   // no preview yet: one cell is a tiny window, wait for the drag
    }
    func track(_ e: NSEvent) {   // cursor outside the panel = no selection, so releasing there cancels
        guard active else { return }
        let new = bounds.contains(convert(e.locationInWindow, from: nil)) ? cell(e) : nil
        guard new?.0 != end?.0 || new?.1 != end?.1 else { return }   // only hit AX when the cell changes
        end = new; needsDisplay = true; preview()
    }
    override func mouseDragged(with e: NSEvent) { track(e) }
    override func mouseUp(with e: NSEvent) { track(e); commit(save: e.modifierFlags.contains(.shift)) }
    override func keyDown(with e: NSEvent) {
        guard active else { return }
        if e.keyCode == 53 { cancel(); return }   // esc, also mid-drag
        let shift = e.modifierFlags.contains(.shift)
        switch e.specialKey {
        case .carriageReturn?, .enter?: commit(save: shift)
        case .leftArrow?: step(-1, 0, resize: shift)
        case .rightArrow?: step(1, 0, resize: shift)
        case .downArrow?: step(0, -1, resize: shift)
        case .upArrow?: step(0, 1, resize: shift)
        default: break
        }
    }
    func step(_ dx: Int, _ dy: Int, resize: Bool) {
        var lo = (0, 0), hi = (cols - 1, rows - 1)
        if let s = selection {
            lo = (s.x.lowerBound, s.y.lowerBound); hi = (s.x.upperBound, s.y.upperBound)
            if resize {
                hi = (min(max(hi.0 + dx, lo.0), cols - 1), min(max(hi.1 + dy, lo.1), rows - 1))
            } else {
                let mx = min(max(dx, -lo.0), cols - 1 - hi.0), my = min(max(dy, -lo.1), rows - 1 - hi.1)
                lo = (lo.0 + mx, lo.1 + my); hi = (hi.0 + mx, hi.1 + my)
            }
            if !pending, lo == (s.x.lowerBound, s.y.lowerBound), hi == (s.x.upperBound, s.y.upperBound) { return }
        }
        start = lo; end = hi; pending = false; needsDisplay = true; preview()
    }
    func commit(save: Bool) {
        guard active else { return }
        active = false
        preview()
        if selection != nil, let w = targetWindow { remember(w); if let o = original { lastSnap = (w, o.0, o.1) } }
        let f = (save || recordMode) ? selectionFraction : nil   // shift saves a preset
        hideGrid()
        if let f { newPreset(f) }
    }
    func cancel() {
        guard active else { return }
        active = false; start = nil; end = nil; preview(); hideGrid()
    }

    override func draw(_ dirty: NSRect) {
        guard !grid.isEmpty else { return }   // layer-backed views get drawn at zero size before the panel is shown
        panelTint.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        let ink = panelInk
        let cw = grid.width / CGFloat(cols), ch = grid.height / CGFloat(rows)
        let radius = min(6, max(2, min(cw, ch) * 0.2))   // rounder corners on bigger cells
        // extra gap at boundary i of n: halves widest, thirds/quarters narrower, everything else uniform
        func gap(_ i: Int, _ n: Int) -> CGFloat {
            i == 0 || i == n ? 0 : (i * 2) % n == 0 ? 3 : (i * 3) % n == 0 || (i * 4) % n == 0 ? 1.5 : 0
        }
        func edge(_ c: CGFloat, _ n: Int, _ size: CGFloat, _ tol: CGFloat, _ sign: CGFloat) -> CGFloat {
            let i = c.rounded()
            return abs(c - i) <= tol ? i * size + sign * (2 + gap(Int(i), n)) : c * size
        }
        func path(_ r: NSRect, tolX: CGFloat = 0, tolY: CGFloat = 0) -> NSBezierPath {
            let x0 = grid.minX + edge(r.minX, cols, cw, tolX, 1), x1 = grid.minX + edge(r.maxX, cols, cw, tolX, -1)
            let y0 = grid.minY + edge(r.minY, rows, ch, tolY, 1), y1 = grid.minY + edge(r.maxY, rows, ch, tolY, -1)
            return NSBezierPath(roundedRect: NSRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0)), xRadius: radius, yRadius: radius)
        }
        func rect(_ x: ClosedRange<Int>, _ y: ClosedRange<Int>) -> NSBezierPath {
            path(NSRect(x: x.lowerBound, y: y.lowerBound, width: x.count, height: y.count))
        }
        for x in 0..<cols { for y in 0..<rows {
            let p = rect(x...x, y...y), hot = hoverCell?.0 == x && hoverCell?.1 == y
            ink.withAlphaComponent(hot ? 0.22 : 0.07).setFill(); p.fill()
            ink.withAlphaComponent(hot ? 0.40 : 0.13).setStroke(); p.lineWidth = 1; p.stroke()
        }}
        let v = targetScreen.visibleFrame, c = CGFloat(cols), r = CGFloat(rows)
        for u in ghosts {   // other snapped windows: soft fill, dashed outline
            let p = path(NSRect(x: u.minX * c, y: u.minY * r, width: u.width * c, height: u.height * r), tolX: 2 * c / v.width, tolY: 2 * r / v.height)
            ink.withAlphaComponent(0.12).setFill(); p.fill()
            ink.withAlphaComponent(0.45).setStroke(); p.lineWidth = 1.5; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }
        if let s = selection {
            let p = rect(s.x, s.y)
            if pending {   // the window's current cells
                NSColor.controlAccentColor.withAlphaComponent(0.22).setFill(); p.fill()
                NSColor.controlAccentColor.setStroke(); p.lineWidth = 2; p.stroke()
            } else {
                drawHighlight(p)
                drawSizeLabel("\(s.x.count) × \(s.y.count)", in: p.bounds)
            }
        }
    }
}

func drawHighlight(_ p: NSBezierPath) {   // accent fill with a soft glow and a lighter top, shared with the layouts panel
    let accent = NSColor.controlAccentColor
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = accent.withAlphaComponent(0.55); glow.shadowBlurRadius = 10; glow.shadowOffset = .zero; glow.set()
    accent.withAlphaComponent(0.9).setFill(); p.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: accent.withAlphaComponent(0.9), ending: (accent.blended(withFraction: 0.3, of: .white) ?? accent).withAlphaComponent(0.95))?
        .draw(in: p, angle: 90)
    NSColor.white.withAlphaComponent(0.55).setStroke(); p.lineWidth = 1; p.stroke()
}
func drawSizeLabel(_ text: String, in r: NSRect) {   // e.g. "6 × 4" in the middle of the selection, when it fits
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.95)]
    let s = NSAttributedString(string: text, attributes: attrs), size = s.size()
    guard size.width + 8 <= r.width, size.height + 4 <= r.height else { return }
    s.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2))
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); view.cancel() }
}

func glass(around content: NSView) -> NSView {   // rounded glass backdrop shared by the grid and the layouts panel
    if #available(macOS 26, *) {
        let g = NSGlassEffectView(); g.cornerRadius = 18; g.contentView = content
        g.wantsLayer = true; g.layer?.cornerRadius = 18; g.layer?.masksToBounds = true  // clip the backdrop too
        return g
    }
    let v = NSVisualEffectView(); v.material = .hudWindow; v.state = .active
    v.wantsLayer = true; v.layer?.cornerRadius = 18; v.addSubview(content)
    return v
}

let view = GridView()
let panel: Panel = {
    let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.contentView = glass(around: view)
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.hasShadow = false  // a shadow is computed on the square bounds and leaks through the corners
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hidesOnDeactivate = false
    panel.acceptsMouseMovedEvents = true   // hover highlight
    panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
    return panel
}()

func showGrid() {
    targetWindow = recordMode ? nil : pickTarget()   // before the panel appears; record mode moves nothing
    targetScreen = screenUnderCursor()
    view.original = targetWindow.flatMap(axFrame)
    if view.original == nil { targetWindow = nil }
    view.ghosts = ghostFractions(on: targetScreen)
    view.start = nil; view.end = nil; view.moved = false; view.pending = false; view.hoverCell = nil; view.needsDisplay = true
    if let o = view.original {
        let r = NSRect(x: o.0.x, y: NSScreen.screens[0].frame.maxY - o.0.y - o.1.height, width: o.1.width, height: o.1.height)
        let u = screenFraction(of: r, on: targetScreen)
        if NSMouseInRect(NSPoint(x: r.midX, y: r.midY), targetScreen.frame, false), !u.isEmpty {
            let x = cellRange(u.minX, u.maxX, cols), y = cellRange(u.minY, u.maxY, rows)
            view.start = (x.lowerBound, y.lowerBound); view.end = (x.upperBound, y.upperBound); view.pending = true
        }
    }
    let f = targetScreen.visibleFrame, w: CGFloat = 480, h = w * f.height / f.width
    panel.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: true)
    view.frame = panel.contentView!.bounds
    panel.alphaValue = 0
    view.active = true
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(view)
    NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
}
func hideGrid() {
    recordMode = false
    NSAnimationContext.runAnimationGroup({ $0.duration = 0.10; panel.animator().alphaValue = 0 }) { if !view.active { panel.orderOut(nil) } }
}
