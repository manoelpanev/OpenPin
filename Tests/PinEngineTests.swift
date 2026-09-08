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

        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let bubble = CGRect(x: 1804, y: 939, width: bubbleSize.width, height: bubbleSize.height)
        let view = CGSize(width: 520, height: 424)
        let expanded = frameSharingTopRight(of: bubble, size: view, within: screen)
        let geometry: [(String, Bool)] = [
            ("live view grows out of the bubble's top-right corner", expanded == CGRect(x: 1388, y: 619, width: 520, height: 424)),
            ("bubble returns to the same corner after collapsing", frameSharingTopRight(of: expanded, size: bubbleSize, within: screen) == bubble),
            ("a bubble at the left edge expands inside the screen", frameSharingTopRight(of: CGRect(x: 4, y: 500, width: bubbleSize.width, height: bubbleSize.height), size: view, within: screen).minX == 0),
            ("a view taller than the screen is pushed down to the screen bottom", frameSharingTopRight(of: bubble, size: CGSize(width: 520, height: 2000), within: screen).origin == CGPoint(x: 1388, y: 0))
        ]
        for (name, passed) in geometry { precondition(passed, name) }
        print("\(cases.count)/\(cases.count) capture-source identity tests passed")
        print("\(geometry.count)/\(geometry.count) bubble geometry tests passed")
    }
}
