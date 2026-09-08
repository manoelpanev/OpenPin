import AppKit
import ScreenCaptureKit
import AVFoundation

let bubbleSize = CGSize(width: 104, height: 104)
let bubbleIconSide: CGFloat = 64
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// A frame of `size` that shares `anchor`'s top-right corner, moved inside `screen` when necessary.
/// Used both ways: the live view grows out of the bubble and shrinks back into it.
func frameSharingTopRight(of anchor: CGRect, size: CGSize, within screen: CGRect) -> CGRect {
    var frame = CGRect(x: anchor.maxX - size.width, y: anchor.maxY - size.height, width: size.width, height: size.height)
    frame.origin.x = min(max(frame.minX, screen.minX), max(screen.maxX - size.width, screen.minX))
    frame.origin.y = min(max(frame.minY, screen.minY), max(screen.maxY - size.height, screen.minY))
    return frame
}

/// Rasterize the icon at the exact pixel size it is shown at, so the largest representation is used instead of an upscaled small one.
func crispIcon(_ image: NSImage, side: CGFloat, scale: CGFloat) -> CGImage? {
    let pixels = Int(side * scale)
    guard pixels > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage
}

/// Floating app icon: bobs gently, drags anywhere, click opens the original window, right-click offers the live view/release.
final class BubbleView: NSView {
    private let floating = CALayer()
    private let icon = CALayer()
    private let dot = CALayer()
    private let image: NSImage
    private var renderedScale: CGFloat = 0
    private var dragStart: NSPoint?
    private var dragged = false
    var onOpenOriginal: (() -> Void)?
    var onExpand: (() -> Void)?
    var onRelease: (() -> Void)?

    init(image: NSImage, app: String) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: bubbleSize))
        wantsLayer = true
        layer?.masksToBounds = false
        floating.masksToBounds = false
        icon.contentsGravity = .resizeAspect
        icon.minificationFilter = .trilinear
        icon.shadowColor = NSColor.black.cgColor
        icon.shadowOpacity = 0.32
        icon.shadowRadius = 9
        icon.shadowOffset = CGSize(width: 0, height: -5)
        dot.backgroundColor = NSColor.systemGreen.cgColor
        dot.borderColor = NSColor.white.cgColor
        dot.borderWidth = 2
        dot.cornerRadius = 7
        floating.addSublayer(icon)
        floating.addSublayer(dot)
        layer?.addSublayer(floating)
        toolTip = "\(app): Klick öffnet das Original · Rechtsklick für Live-Ansicht · Ziehen verschiebt"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(app): Original öffnen")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        floating.frame = bounds
        let side = bubbleIconSide
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2 + 3, width: side, height: side)
        dot.frame = CGRect(x: icon.frame.maxX - 9, y: icon.frame.minY - 1, width: 14, height: 14)
        renderIcon()
        CATransaction.commit()
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); renderIcon() }
    private func renderIcon() {
        let scale = max(window?.backingScaleFactor ?? 2, 2)
        guard scale != renderedScale, let cgImage = crispIcon(image, side: bubbleIconSide, scale: scale) else { return }
        renderedScale = scale
        icon.contentsScale = scale
        icon.contents = cgImage
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    /// Restart the levitation loop; hidden windows drop their layer animations.
    func startFloating() {
        floating.removeAllAnimations()
        icon.removeAnimation(forKey: "shadow")
        guard !reduceMotion else { return }
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -3.5; bob.toValue = 3.5
        bob.duration = 2.4; bob.autoreverses = true; bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        floating.add(bob, forKey: "bob")
        let shadow = CABasicAnimation(keyPath: "shadowRadius")
        shadow.fromValue = 7; shadow.toValue = 14
        shadow.duration = bob.duration; shadow.autoreverses = true; shadow.repeatCount = .infinity
        shadow.timingFunction = bob.timingFunction
        icon.add(shadow, forKey: "shadow")
    }
    /// Spring entrance when the bubble (re)appears.
    func pop() {
        guard !reduceMotion, let layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.35; spring.toValue = 1
        spring.damping = 11; spring.stiffness = 190; spring.initialVelocity = 5
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }
    /// The icon bursts outward as the original window takes its place.
    func burst(completion: @escaping () -> Void) {
        guard !reduceMotion, let layer else { completion(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1; scale.toValue = 1.7
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        for animation in [scale, fade] {
            animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
    }
    private func hover(_ active: Bool) {
        CATransaction.begin(); CATransaction.setAnimationDuration(0.18)
        icon.transform = active ? CATransform3DMakeScale(1.1, 1.1, 1) : CATransform3DIdentity
        CATransaction.commit()
    }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let window else { return }
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - dragStart.x, y: mouse.y - dragStart.y)
        if !dragged, abs(origin.x - window.frame.minX) < 3, abs(origin.y - window.frame.minY) < 3 { return }
        dragged = true
        window.setFrameOrigin(origin)
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if !dragged { onOpenOriginal?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for (title, action) in [("Original öffnen", #selector(openOriginalAction)), ("Live-Ansicht anzeigen", #selector(expandAction)), ("Lösen", #selector(releaseAction))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func expandAction() { onExpand?() }
    @objc private func openOriginalAction() { onOpenOriginal?() }
    @objc private func releaseAction() { onRelease?() }
    override func accessibilityPerformPress() -> Bool { onOpenOriginal?(); return true }
}

/// Small pill at the original window's corner while it is out: one click sends the window back into the icon.
final class ReturnBadgeView: NSView {
    static let size = CGSize(width: 58, height: 32)
    private let pill = CALayer()
    private let icon = CALayer()
    private let chevron = CAShapeLayer()
    var onReturn: (() -> Void)?
    init(image: NSImage, app: String) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.masksToBounds = false
        pill.frame = CGRect(x: 3, y: 3, width: Self.size.width - 6, height: Self.size.height - 6)
        pill.cornerRadius = pill.frame.height / 2
        pill.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        pill.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
        pill.borderWidth = 1
        pill.shadowColor = NSColor.black.cgColor
        pill.shadowOpacity = 0.35; pill.shadowRadius = 4; pill.shadowOffset = CGSize(width: 0, height: -1)
        icon.frame = CGRect(x: 9, y: 7, width: 18, height: 18)
        icon.contentsGravity = .resizeAspect
        icon.contentsScale = 2
        icon.contents = crispIcon(image, side: 18, scale: 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 36, y: 18)); path.addLine(to: CGPoint(x: 41, y: 13)); path.addLine(to: CGPoint(x: 46, y: 18))
        chevron.path = path
        chevron.strokeColor = NSColor.white.cgColor
        chevron.fillColor = nil
        chevron.lineWidth = 2; chevron.lineCap = .round; chevron.lineJoin = .round
        layer?.addSublayer(pill); layer?.addSublayer(icon); layer?.addSublayer(chevron)
        toolTip = "\(app) zurück ins Symbol (⌃⌥P)"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(app) zurück ins Symbol")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onReturn?() } }
    override func accessibilityPerformPress() -> Bool { onReturn?(); return true }
}

final class LivePreview: NSView {
    let video = AVSampleBufferDisplayLayer()
    var openOriginal: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        video.videoGravity = .resizeAspect
        layer?.addSublayer(video)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Originalfenster öffnen")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); video.frame = bounds }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { openOriginal?() }
    override func accessibilityPerformPress() -> Bool { openOriginal?(); return true }
}

final class LiveSession: NSObject, SCStreamOutput, SCStreamDelegate, NSWindowDelegate {
    let entry: WindowEntry
    let panel: NSPanel
    let bubble: NSPanel
    let badge: NSPanel
    let preview = LivePreview(frame: .zero)
    private let bubbleView: BubbleView
    private let badgeView: ReturnBadgeView
    private var follow: Timer?
    private let panelMinSize = NSSize(width: 280, height: 190)
    private var expandedSize: NSSize
    private var collapsed = true
    private var stream: SCStream?
    private var stopped = false
    private var firstFrame = false
    private var handedOff = false
    private var handoffTime = Date.distantPast
    private var paused = false
    private var frameTimeout: DispatchWorkItem?
    var onStatus: ((String) -> Void)?
    var onRelease: (() -> Void)?
    var onFailure: ((String) -> Void)?

    init(entry: WindowEntry, source: SCWindow, slot: Int) {
        self.entry = entry
        let width: CGFloat = 520
        let height = max(180, min(560, width * source.frame.height / max(source.frame.width, 1)))
        expandedSize = NSSize(width: width, height: height + 44)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: expandedSize),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        let image = NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!
        bubbleView = BubbleView(image: image, app: entry.app)
        bubble = NSPanel(contentRect: NSRect(origin: .zero, size: bubbleSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        badgeView = ReturnBadgeView(image: image, app: entry.app)
        badge = NSPanel(contentRect: NSRect(origin: .zero, size: ReturnBadgeView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        for floating in [bubble, badge] {
            floating.isOpaque = false
            floating.backgroundColor = .clear
            floating.hasShadow = false
            floating.level = .floating
            floating.hidesOnDeactivate = false
            floating.isReleasedWhenClosed = false
            floating.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        }
        badge.contentView = badgeView
        badge.title = "\(entry.app) · OpenPin Zurück"
        badgeView.onReturn = { [weak self] in self?.returnToIcon() }
        panel.title = "\(entry.app) · OpenPin"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.minSize = panelMinSize
        panel.delegate = self
        bubble.contentView = bubbleView
        bubble.title = "\(entry.app) · OpenPin Symbol"
        bubbleView.onExpand = { [weak self] in self?.expand() }
        bubbleView.onOpenOriginal = { [weak self] in self?.openOriginal() }
        bubbleView.onRelease = { [weak self] in self?.onRelease?() }
        let root = NSView()
        panel.contentView = root
        let icon = NSImageView()
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("\(entry.app) App-Symbol")
        let title = NSTextField(labelWithString: entry.app)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let shrink = NSButton(title: "Als Symbol ⌄", target: self, action: #selector(collapse))
        shrink.bezelStyle = .rounded
        shrink.toolTip = "Live-Ansicht in das schwebende App-Symbol zurückziehen."
        let button = NSButton(title: "Original öffnen ↗", target: self, action: #selector(openOriginal))
        button.bezelStyle = .rounded
        button.toolTip = "Im Original bedienen. Beim App-Wechsel erscheint die Live-Ansicht wieder."
        for view in [icon, title, shrink, button, preview] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: shrink.leadingAnchor, constant: -8),
            shrink.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -6),
            shrink.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            preview.topAnchor.constraint(equalTo: root.topAnchor, constant: 44),
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        preview.openOriginal = { [weak self] in self?.openOriginal() }
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            bubble.setFrameTopLeftPoint(NSPoint(x: frame.maxX - bubbleSize.width - 12, y: frame.maxY - 12 - CGFloat(slot) * (bubbleSize.height - 8)))
        } else { bubble.center() }
        panel.setFrame(frameSharingTopRight(of: bubble.frame, size: expandedSize, within: screen?.visibleFrame ?? bubble.frame), display: false)
        let filter = SCContentFilter(desktopIndependentWindow: source)
        let config = SCStreamConfiguration()
        let scale = min(CGFloat(filter.pointPixelScale), 1600 / max(filter.contentRect.width, filter.contentRect.height, 1))
        config.width = max(2, Int(filter.contentRect.width * scale))
        config.height = max(2, Int(filter.contentRect.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        stream = SCStream(filter: filter, configuration: config, delegate: self)
    }

    func start() async throws {
        guard let stream else { return }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        guard !stopped else { try? await stream.stopCapture(); return }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.firstFrame, !self.stopped else { return }
            self.stop()
            self.onFailure?("Kein Live-Bild empfangen · Fenster erneut anheften")
        }
        frameTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        frameTimeout?.cancel()
        hideAll()
        preview.video.sampleBufferRenderer.flush(removingDisplayedImage: true)
        let old = stream
        stream = nil
        Task { try? await old?.stopCapture() }
    }

    private var visible: Bool { !stopped && firstFrame && !paused && !handedOff }
    private func hideAll() { panel.orderOut(nil); bubble.orderOut(nil); hideBadge() }
    private func hideBadge() { follow?.invalidate(); follow = nil; badge.orderOut(nil) }

    /// While the original is out, keep a small return pill at its top-right corner.
    private func followOriginal() {
        follow?.invalidate()
        follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.positionBadge() }
        positionBadge()
    }
    private func positionBadge() {
        guard handedOff, !stopped, let primary = NSScreen.screens.first,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.pid,
              let rect = axRect(entry.element), (axValue(entry.element, kAXMinimizedAttribute) as? Bool) != true else { badge.orderOut(nil); return }
        let size = ReturnBadgeView.size
        let origin = NSPoint(x: rect.maxX - size.width - 6, y: primary.frame.maxY - rect.minY - size.height - 6)
        badge.setFrameOrigin(origin)
        if !badge.isVisible { badge.orderFrontRegardless() }
    }

    /// Send the original window back into the icon: hide it (or minimize it when the app has other windows) and pop the bubble.
    func returnToIcon() {
        guard handedOff, !stopped, let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        hideBadge()
        let windows = axValue(AXUIElementCreateApplication(entry.pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        let others = windows.filter { !CFEqual($0, entry.element) && (axRect($0).map { $0.width > 80 && $0.height > 50 } ?? false) }
        if others.isEmpty { app.hide() } else { _ = AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        handedOff = false
        collapsed = true
        panel.orderOut(nil)
        present()
        bubbleView.pop()
        onStatus?("Symbol schwebt · Klick öffnet das Original")
    }
    var isOut: Bool { handedOff && !stopped }
    private func showBubble() {
        panel.orderOut(nil)
        bubbleView.layer?.removeAnimation(forKey: "transform.scale")
        bubbleView.layer?.removeAnimation(forKey: "opacity")
        guard !bubble.isVisible else { return }
        bubble.alphaValue = 1
        bubble.orderFrontRegardless()
        bubbleView.startFloating()
    }
    /// Show whichever form the pin currently has: the bubble or the expanded live view.
    private func present() {
        guard visible else { hideAll(); return }
        if collapsed { showBubble() } else if !panel.isVisible { panel.orderFrontRegardless() }
    }
    private var screenFrame: CGRect {
        ((collapsed ? bubble : panel).screen ?? NSScreen.main)?.visibleFrame ?? bubble.frame
    }

    /// The live view grows out of the bubble's corner.
    func expand() {
        guard visible, collapsed else { return }
        collapsed = false
        let screen = screenFrame
        let target = frameSharingTopRight(of: bubble.frame, size: expandedSize, within: screen)
        let quick = reduceMotion
        panel.minSize = NSSize(width: 1, height: 1)
        panel.alphaValue = 0
        panel.setFrame(quick ? target : bubble.frame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = quick ? 0.15 : 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
            bubble.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.minSize = self.panelMinSize
            self.bubble.orderOut(nil)
            self.bubble.alphaValue = 1
        })
        onStatus?("Live-Ansicht · oben angeheftet")
    }

    /// The live view shrinks back into a bubble at its top-right corner.
    @objc func collapse() {
        guard !stopped, !collapsed else { return }
        collapsed = true
        expandedSize = panel.frame.size
        let screen = screenFrame
        let target = frameSharingTopRight(of: panel.frame, size: bubbleSize, within: screen)
        panel.minSize = NSSize(width: 1, height: 1)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.15 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.panel.minSize = self.panelMinSize
            self.panel.setFrame(frameSharingTopRight(of: target, size: self.expandedSize, within: screen), display: false)
            self.bubble.setFrameOrigin(target.origin)
            guard self.visible, self.collapsed else { return }
            self.showBubble()
            self.bubbleView.pop()
        })
        onStatus?("Symbol schwebt · Klick öffnet das Original")
    }

    func update(frontPID: pid_t?, paused: Bool) {
        self.paused = paused
        if handedOff && frontPID != entry.pid && Date().timeIntervalSince(handoffTime) > 1 {
            handedOff = false
            onStatus?(collapsed ? "Symbol schwebt · Klick öffnet das Original" : "Live-Ansicht · oben angeheftet")
        }
        guard !stopped, firstFrame else { return }
        present()
        if handedOff && frontPID == entry.pid && follow == nil { followOriginal() }
    }

    func show() {
        guard !stopped, firstFrame else { return }
        handedOff = false; paused = false
        if collapsed { showBubble(); expand() } else { panel.makeKeyAndOrderFront(nil) }
    }

    @objc func openOriginal() {
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else { onRelease?(); return }
        handedOff = true
        handoffTime = Date()
        if collapsed, bubble.isVisible {
            panel.orderOut(nil)
            bubbleView.burst { [weak self] in self?.bubble.orderOut(nil) }
        } else { hideAll() }
        _ = AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        _ = AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.unhide()
        placeOriginalAtIcon()
        // Launch Services activation is granted regardless of which app asks; a direct activate() is refused
        // unless the system credits us with recent user interaction.
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, _ in
                guard let self else { return }
                DispatchQueue.main.async { _ = AXUIElementPerformAction(self.entry.element, kAXRaiseAction as CFString) }
            }
        } else { app.activate(options: []) }
        _ = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.handedOff else { return }
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if front != self.entry.pid { self.update(frontPID: front, paused: self.paused) } else { self.followOriginal() }
        }
        onStatus?("Original geöffnet · \(collapsed ? "Symbol" : "Live-Ansicht") kehrt beim App-Wechsel zurück")
    }

    /// Move the original window so it comes out of the icon: same top-right corner, on the icon's screen.
    private func placeOriginalAtIcon() {
        let anchorWindow = collapsed ? bubble : panel
        guard let size = axRect(entry.element)?.size, let screen = anchorWindow.screen ?? NSScreen.main,
              let primary = NSScreen.screens.first else { return }
        let target = frameSharingTopRight(of: anchorWindow.frame, size: size, within: screen.visibleFrame)
        var origin = CGPoint(x: target.minX, y: primary.frame.maxY - target.maxY)
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        _ = AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, value)
    }

    func windowWillClose(_ notification: Notification) { onRelease?() }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, stream === self.stream, type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let renderer = preview.video.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData else { return }
        renderer.enqueue(sampleBuffer)
        if !firstFrame {
            firstFrame = true
            frameTimeout?.cancel()
            present()
            if visible { bubbleView.pop() }
            onStatus?("Symbol schwebt · Klick öffnet das Original")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.stop()
            self.onFailure?("Live-Ansicht beendet: \(error.localizedDescription)")
        }
    }
}

final class LivePinController {
    var changed: ((UUID, Bool, String) -> Void)?
    private var sessions: [UUID: LiveSession] = [:]
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var paused = false
    private var observer: NSObjectProtocol?
    private var keyMonitor: Any?
    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updatePanels()
        }
        // ⌃⌥P while a pinned window is in front sends it back into its icon. Listen-only; needs the Accessibility trust we already require.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 35, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: [.control, .option]) else { return }
            self?.returnFrontToIcon()
        }
    }
    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
    /// Send the frontmost pinned window back into its icon.
    func returnFrontToIcon() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for session in sessions.values where session.isOut && session.entry.pid == pid { session.returnToIcon() }
    }
    func toggle(_ entry: WindowEntry) {
        if sessions[entry.id] != nil || pending[entry.id] != nil { release(entry.id); return }
        changed?(entry.id, true, "Live-Ansicht startet…")
        pending[entry.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                try Task.checkCancellation()
                guard let rect = axRect(entry.element) else { throw NSError(domain: "OpenPin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Originalfenster nicht erreichbar"]) }
                let candidates = content.windows.map { VisibleWindow(pid: $0.owningApplication?.processID ?? -1, frame: $0.frame) }
                guard let index = uniqueSourceIndex(pid: entry.pid, frame: rect, candidates: candidates) else { throw NSError(domain: "OpenPin", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fenster nicht eindeutig gefunden. Öffne das Original und aktualisiere die Liste."]) }
                let source = content.windows[index]
                let session = LiveSession(entry: entry, source: source, slot: self.sessions.count)
                self.sessions[entry.id] = session
                session.onStatus = { [weak self, weak session] note in
                    guard let self, let session, self.sessions[entry.id] === session else { return }
                    self.changed?(entry.id, true, note)
                }
                session.onRelease = { [weak self] in self?.release(entry.id) }
                session.onFailure = { [weak self, weak session] note in
                    guard let self, let session, self.sessions[entry.id] === session else { return }
                    self.release(entry.id)
                    self.changed?(entry.id, false, note)
                }
                session.update(frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, paused: self.paused)
                try await session.start()
                try Task.checkCancellation()
                self.pending[entry.id] = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.sessions.removeValue(forKey: entry.id)?.stop()
                self.pending[entry.id] = nil
                self.changed?(entry.id, false, "Start fehlgeschlagen: \(error.localizedDescription). Prüfe Bildschirmaufnahme-Zugriff.")
            }
        }
    }
    func release(_ id: UUID) {
        pending.removeValue(forKey: id)?.cancel()
        sessions.removeValue(forKey: id)?.stop()
        changed?(id, false, "")
    }
    func releaseAll() { for id in Set(sessions.keys).union(pending.keys) { release(id) } }
    func showAll() {
        paused = false
        for session in sessions.values { session.show() }
    }
    func reconcile(_ entries: [WindowEntry], paused: Bool) {
        let ids = Set(entries.map(\.id))
        for id in Set(sessions.keys).union(pending.keys) where !ids.contains(id) { release(id) }
        self.paused = paused
        updatePanels()
    }
    private func updatePanels() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for session in sessions.values { session.update(frontPID: pid, paused: paused) }
    }
}
