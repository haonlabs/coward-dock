import AppKit

// ponytail: private Dock API (no Automation permission needed, no Dock restart).
// If a macOS update removes it, fall back to System Events AppleScript `set autohide of dock preferences`.
@_silgen_name("CoreDockSetAutoHideEnabled") func CoreDockSetAutoHideEnabled(_ on: Bool)
@_silgen_name("CoreDockGetAutoHideEnabled") func CoreDockGetAutoHideEnabled() -> Bool

enum DockEdge { case bottom, left, right }
struct DockArea { let rect: CGRect; let edge: DockEdge }  // Cocoa coords

// Several points of slack because the Dock shrinks as apps are added, so a window laid out against an
// older, taller Dock may sit a few points off its current edge.
let dockSlack: CGFloat = 6

/// True when any window overlaps or touches the Dock. Touching counts on purpose: a maximized window
/// ends right at the Dock, and hiding the Dock lets it fill that space.
func windowsOverlapDock(_ windows: [CGRect], _ dock: DockArea) -> Bool {
    let d = dock.rect
    let zone = switch dock.edge {  // grown into the screen so touching windows count
    case .bottom: CGRect(x: d.minX, y: d.minY, width: d.width, height: d.height + dockSlack)
    case .left: CGRect(x: d.minX, y: d.minY, width: d.width + dockSlack, height: d.height)
    case .right: CGRect(x: d.minX - dockSlack, y: d.minY, width: d.width + dockSlack, height: d.height)
    }
    return windows.contains { $0.intersects(zone) }
}

/// The frame a window ending at the Dock's edge should get to fill the hidden Dock's space,
/// or nil when the window doesn't end there (floating, dragged over the Dock, on another screen).
func frameFillingDockSpace(_ r: CGRect, _ dock: DockArea) -> CGRect? {
    let d = dock.rect
    switch dock.edge {
    case .bottom:
        guard abs(r.minY - d.maxY) <= dockSlack, r.minX < d.maxX, r.maxX > d.minX else { return nil }
        return CGRect(x: r.minX, y: d.minY, width: r.width, height: r.maxY - d.minY)
    case .left:
        guard abs(r.minX - d.maxX) <= dockSlack, r.minY < d.maxY, r.maxY > d.minY else { return nil }
        return CGRect(x: d.minX, y: r.minY, width: r.maxX - d.minX, height: r.height)
    case .right:
        guard abs(r.maxX - d.minX) <= dockSlack, r.minY < d.maxY, r.maxY > d.minY else { return nil }
        return CGRect(x: r.minX, y: r.minY, width: d.maxX - r.minX, height: r.height)
    }
}

@MainActor
final class DockWatcher {
    private struct Window { let id: CGWindowID; let pid: pid_t; let frame: CGRect }  // Cocoa coords

    private(set) var hidden = false
    private var dock: DockArea?  // measured while the Dock is visible
    private var timer: Timer?
    private var unresizable = Set<CGWindowID>()  // fixed-size or AX-less windows, so they aren't retried every tick
    private var attempted: [CGWindowID: CGRect] = [:]  // a window's frame when we last tried to stretch it
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
        // Trust the Dock, not our last request: inside a fullscreen Space the Dock ignores auto-hide
        // changes, and a remembered "hidden" would leave it stuck visible on the next desktop.
        let actual = CoreDockGetAutoHideEnabled()
        if actual != hidden { hidden = actual; onChange?() }
        if !hidden, let d = Self.measureDock() { dock = d }
        guard let dock else { return }
        let windows = Self.visibleWindows()
        // Windows that only end at the Dock keep their size when it hides (only macOS-tiled ones adapt).
        if hidden, AXIsProcessTrusted() { fillDockSpace(windows, dock) }
        let want = windowsOverlapDock(windows.map(\.frame), dock)
        // Re-sent every tick while the Dock ignores it (fullscreen); that's measured to cost nothing.
        if want != hidden { CoreDockSetAutoHideEnabled(want) }  // read back as `hidden` next tick
    }

    private func setHidden(_ on: Bool) {
        CoreDockSetAutoHideEnabled(on)
        hidden = on
        onChange?()
    }

    private func fillDockSpace(_ windows: [Window], _ dock: DockArea) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        // Not once per window: some apps (Ghostex, for one) shrink their window back to the visible area
        // whenever the Dock shows, so it has to be stretched again each time.
        let flip = { (r: CGRect) in CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
        for w in windows where !unresizable.contains(w.id) {
            guard let target = frameFillingDockSpace(w.frame, dock) else { attempted[w.id] = nil; continue }
            // Judged a tick later, since some apps apply AX resizes asynchronously.
            if attempted[w.id] == w.frame { unresizable.insert(w.id); continue }  // last try didn't budge it
            attempted[w.id] = w.frame
            guard let ax = Self.axWindow(pid: w.pid, frame: flip(w.frame)) else { unresizable.insert(w.id); continue }
            Self.axSetFrame(ax, flip(target))  // AX uses top-left origin, like CG
        }
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

    /// Normal app windows on the current Space(s).
    private static func visibleWindows() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]], let primary = NSScreen.screens.first else { return [] }
        let me = getpid()
        return list.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  var r = CGRect(dictionaryRepresentation: b) else { return nil }
            r.origin.y = primary.frame.height - r.maxY  // CG (top-left origin) -> Cocoa (bottom-left)
            return Window(id: id, pid: pid, frame: r)
        }
    }

    /// The app's AX window whose frame (top-left coords) matches the CG window's.
    private static func axWindow(pid: pid_t, frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)  // never let a hung app stall the menu bar
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { w in
            guard let f = axFrame(w) else { return false }
            return abs(f.minX - frame.minX) < 2 && abs(f.minY - frame.minY) < 2
                && abs(f.width - frame.width) < 2 && abs(f.height - frame.height) < 2
        }
    }

    private static func axFrame(_ e: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?, p = CGPoint.zero, s = CGSize.zero
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success,
              AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s)
        else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func axSetFrame(_ e: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v) }
    }
}
