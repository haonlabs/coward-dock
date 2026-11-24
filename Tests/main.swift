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

var failed = 0
for (name, windows, dock, want) in cases where windowsOverlapDock(windows, dock) != want {
    print("FAIL: \(name) (expected \(want))")
    failed += 1
}
print(failed == 0 ? "selftest: \(cases.count) cases passed" : "selftest: \(failed) failed")
exit(failed == 0 ? 0 : 1)
