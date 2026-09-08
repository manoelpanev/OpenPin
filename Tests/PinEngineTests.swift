import Foundation

@main struct PinEngineTests {
    static func main() {
        let target = VisibleWindow(pid: 10, frame: CGRect(x: 100, y: 100, width: 300, height: 250))
        let overlapping = VisibleWindow(pid: 20, frame: CGRect(x: 150, y: 120, width: 300, height: 250))
        let separate = VisibleWindow(pid: 20, frame: CGRect(x: 900, y: 120, width: 300, height: 250))
        let sameApp = VisibleWindow(pid: 10, frame: CGRect(x: 130, y: 120, width: 310, height: 250))
        let cases: [(String, [VisibleWindow], [VisibleWindow], RaiseDecision)] = [
            ("covered window is raised", [overlapping, target], [target], .covered),
            ("front window is left alone", [target, overlapping], [target], .clear),
            ("separate windows do not cause raises", [separate, target], [target], .clear),
            ("two pins do not fight each other", [overlapping, target], [target, overlapping], .clear),
            ("other window of same app can cover target", [sameApp, target], [target], .covered),
            ("hidden window is not activated", [overlapping], [target], .unavailable),
            ("ambiguous identity is not guessed", [target, target], [target], .unavailable),
            ("empty desktop is not fought", [], [target], .unavailable)
        ]
        for (name, ordered, pinned, expected) in cases {
            precondition(raiseDecision(target: target, ordered: ordered, pinned: pinned) == expected, name)
        }
        print("8/8 ordering policy tests passed")
    }
}
