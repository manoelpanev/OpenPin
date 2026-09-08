import Foundation

@main struct PinEngineTests {
    static func main() {
        let frame = CGRect(x: -1743, y: 65, width: 1512, height: 893)
        let source = VisibleWindow(pid: 10, frame: frame)
        let foreign = VisibleWindow(pid: 20, frame: frame)
        let other = VisibleWindow(pid: 10, frame: CGRect(x: 100, y: 100, width: 500, height: 300))
        let accessory = VisibleWindow(pid: 10, frame: CGRect(x: -1726, y: 87, width: 66, height: 20))
        let slightlyRounded = VisibleWindow(pid: 10, frame: frame.offsetBy(dx: 1, dy: 1))
        let cases: [(String, [VisibleWindow], Int?)] = [
            ("matches the original on a monitor with negative coordinates", [source], 0),
            ("does not share another application's identical window", [foreign], nil),
            ("selects by process as well as geometry", [foreign, source], 1),
            ("does not mistake a titlebar accessory for the source", [accessory, source], 1),
            ("does not share another window of the same app", [other], nil),
            ("refuses ambiguous windows rather than capturing the wrong one", [source, source], nil),
            ("handles an absent source", [], nil),
            ("allows subpixel geometry rounding", [slightlyRounded], 0)
        ]
        for (name, candidates, expected) in cases {
            precondition(uniqueSourceIndex(pid: 10, frame: frame, candidates: candidates) == expected, name)
        }
        print("\(cases.count)/\(cases.count) capture-source identity tests passed")
    }
}
