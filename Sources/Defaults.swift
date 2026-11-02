import Cocoa
import Carbon

// grid, gap, hotkey (keyCode/keyMods/keyLabel, default ⌃⌥D), target rule, shake-for-layouts, panel tint and presets live in UserDefaults
let defaults: UserDefaults = {
    let d = UserDefaults.standard
    let fullScreen = Preset(name: "Full screen", x: 0, y: 0, w: 1, h: 1, keyCode: kVK_ANSI_F, keyMods: optionKey | controlKey, keyLabel: "⌃⌥F")
    d.register(defaults: ["cols": 12, "rows": 8, "gap": 0, "shakeLayouts": true, "presets": try! JSONEncoder().encode([fullScreen])])
    return d
}()
var cols: Int { min(max(defaults.integer(forKey: "cols"), 1), 24) }
var rows: Int { min(max(defaults.integer(forKey: "rows"), 1), 24) }

// tint over the glass of the grid and layouts panels, stored as "r g b a" in sRGB
let defaultTint = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 0.30)
var panelTint: NSColor {
    get {
        let c = (defaults.string(forKey: "panelTint") ?? "").split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
        return c.count == 4 ? NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3]) : defaultTint
    }
    set {
        guard let c = newValue.usingColorSpace(.sRGB) else { return }
        defaults.set("\(c.redComponent) \(c.greenComponent) \(c.blueComponent) \(c.alphaComponent)", forKey: "panelTint")
    }
}
var panelInk: NSColor {   // white on dark tints, black once a light tint covers the (dark) glass enough
    guard let c = panelTint.usingColorSpace(.sRGB) else { return .white }
    let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    return lum * c.alphaComponent + 0.15 * (1 - c.alphaComponent) > 0.55 ? .black : .white
}
