// Overlap-rule self-check, run by build.sh. Numbers mirror a real 1800x1169 screen with an 85pt Dock.
import AppKit

let bottom = DockArea(rect: CGRect(x: 0, y: 0, width: 1800, height: 85), edge: .bottom)
let left = DockArea(rect: CGRect(x: 0, y: 0, width: 80, height: 1169), edge: .left)
let right = DockArea(rect: CGRect(x: 1720, y: 0, width: 80, height: 1169), edge: .right)

let cases: [(String, [CGRect], DockArea, Bool)] = [
    ("no windows", [], bottom, false),
    ("floating window above the Dock", [CGRect(x: 400, y: 300, width: 900, height: 600)], bottom, false),
    ("window 10pt above the Dock", [CGRect(x: 400, y: 95, width: 900, height: 600)], bottom, false),
    ("maximized window touching the Dock", [CGRect(x: 0, y: 85, width: 1800, height: 1045)], bottom, true),
    ("window laid out against a taller Dock", [CGRect(x: 0, y: 89, width: 1800, height: 1041)], bottom, true),
    ("maximized window grown after Dock hid", [CGRect(x: 0, y: 0, width: 1800, height: 1130)], bottom, true),
    ("left-half tile touching the Dock", [CGRect(x: 0, y: 85, width: 900, height: 1045)], bottom, true),
    ("top-half tile", [CGRect(x: 0, y: 607, width: 1800, height: 523)], bottom, false),
    ("window dragged over the Dock", [CGRect(x: 300, y: -771, width: 800, height: 1040)], bottom, true),
    ("window off-screen below the Dock", [CGRect(x: 300, y: -900, width: 800, height: 100)], bottom, false),
    ("one floating + one overlapping", [CGRect(x: 400, y: 300, width: 900, height: 600),
                                        CGRect(x: 100, y: 40, width: 400, height: 400)], bottom, true),
    ("left Dock: window touching it", [CGRect(x: 80, y: 200, width: 900, height: 600)], left, true),
    ("left Dock: window away from it", [CGRect(x: 300, y: 200, width: 900, height: 600)], left, false),
    ("right Dock: window touching it", [CGRect(x: 820, y: 200, width: 900, height: 600)], right, true),
    ("right Dock: window away from it", [CGRect(x: 300, y: 200, width: 900, height: 600)], right, false),
]

// Which windows get stretched into the hidden Dock's space, and to what frame.
let fillCases: [(String, CGRect, DockArea, CGRect?)] = [
    ("maximized window ending at the Dock", CGRect(x: 0, y: 90, width: 1800, height: 1040), bottom,
     CGRect(x: 0, y: 0, width: 1800, height: 1130)),
    ("half-width window ending 4pt off the Dock", CGRect(x: 900, y: 81, width: 900, height: 1049), bottom,
     CGRect(x: 900, y: 0, width: 900, height: 1130)),
    ("floating window", CGRect(x: 400, y: 300, width: 900, height: 600), bottom, nil),
    ("window dragged over the Dock", CGRect(x: 300, y: -771, width: 800, height: 1040), bottom, nil),
    ("window already filling the screen", CGRect(x: 0, y: 0, width: 1800, height: 1130), bottom, nil),
    ("window on a second screen, same height", CGRect(x: 1800, y: 89, width: 1920, height: 1041), bottom, nil),
    ("left Dock: window ending at it", CGRect(x: 80, y: 0, width: 900, height: 1130), left,
     CGRect(x: 0, y: 0, width: 980, height: 1130)),
    ("right Dock: window ending at it", CGRect(x: 820, y: 0, width: 900, height: 1130), right,
     CGRect(x: 820, y: 0, width: 980, height: 1130)),
]

var failed = 0
for (name, windows, dock, want) in cases where windowsOverlapDock(windows, dock) != want {
    print("FAIL overlap: \(name) (expected \(want))")
    failed += 1
}
for (name, window, dock, want) in fillCases where frameFillingDockSpace(window, dock) != want {
    print("FAIL fill: \(name) (expected \(String(describing: want)), got \(String(describing: frameFillingDockSpace(window, dock))))")
    failed += 1
}
let total = cases.count + fillCases.count
print(failed == 0 ? "selftest: \(total) cases passed" : "selftest: \(failed) of \(total) failed")
exit(failed == 0 ? 0 : 1)
