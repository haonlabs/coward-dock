import AppKit

// ponytail: private Dock API (no Automation permission needed, no Dock restart).
// If a macOS update removes it, fall back to System Events AppleScript `set autohide of dock preferences`.
@_silgen_name("CoreDockSetAutoHideEnabled") func CoreDockSetAutoHideEnabled(_ on: Bool)

enum DockEdge { case bottom, left, right }
struct DockArea { let rect: CGRect; let edge: DockEdge }  // Cocoa coords

/// True when any window overlaps or touches the Dock. Touching counts on purpose: a maximized or tiled
/// window ends right at the Dock; hiding the Dock lets it grow to the screen edge, and it then keeps
/// overlapping, so the Dock stays hidden until that window leaves.
func windowsOverlapDock(_ windows: [CGRect], _ dock: DockArea) -> Bool {
    // Grown into the screen so touching windows count. Several points of slack because the Dock shrinks as
    // apps are added, so a window laid out against an older, taller Dock may sit a few points off.
    let d = dock.rect, slack: CGFloat = 6
    let zone = switch dock.edge {
    case .bottom: CGRect(x: d.minX, y: d.minY, width: d.width, height: d.height + slack)
    case .left: CGRect(x: d.minX, y: d.minY, width: d.width + slack, height: d.height)
    case .right: CGRect(x: d.minX - slack, y: d.minY, width: d.width + slack, height: d.height)
    }
    return windows.contains { $0.intersects(zone) }
}

@MainActor
final class DockWatcher {
    private(set) var hidden = false
    private var dock: DockArea?  // measured while the Dock is visible
    private var timer: Timer?
    var onChange: (() -> Void)?
    var running: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        setHidden(false)
        // ponytail: polls every 0.5s; switch to AX window-move observers if CPU ever matters.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)  // keep ticking while the menu is open
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        setHidden(false)
    }

    private func tick() {
        if !hidden, let d = Self.measureDock() { dock = d }
        guard let dock else { return }
        let want = windowsOverlapDock(Self.visibleWindows(), dock)
        if want != hidden { setHidden(want) }
    }

    private func setHidden(_ on: Bool) {
        CoreDockSetAutoHideEnabled(on)
        hidden = on
        onChange?()
    }

    // ponytail: uses the whole screen edge strip the Dock reserves, not the exact Dock bar;
    // switch to the Dock's AX frame if windows beside the bar shouldn't count.
    private static func measureDock() -> DockArea? {
        for s in NSScreen.screens {
            let f = s.frame, v = s.visibleFrame
            if v.minY - f.minY > 10 { return DockArea(rect: CGRect(x: f.minX, y: f.minY, width: f.width, height: v.minY - f.minY), edge: .bottom) }
            if v.minX - f.minX > 10 { return DockArea(rect: CGRect(x: f.minX, y: f.minY, width: v.minX - f.minX, height: f.height), edge: .left) }
            if f.maxX - v.maxX > 10 { return DockArea(rect: CGRect(x: v.maxX, y: f.minY, width: f.maxX - v.maxX, height: f.height), edge: .right) }
        }
        return nil
    }

    /// Normal app windows on the current Space, in Cocoa coordinates.
    private static func visibleWindows() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]], let primary = NSScreen.screens.first else { return [] }
        return list.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  var r = CGRect(dictionaryRepresentation: b) else { return nil }
            r.origin.y = primary.frame.height - r.maxY  // CG (top-left origin) -> Cocoa (bottom-left)
            return r
        }
    }
}
