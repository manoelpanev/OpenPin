import AppKit
import ScreenCaptureKit
import AVFoundation

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
    let preview = LivePreview(frame: .zero)
    private var stream: SCStream?
    private var stopped = false
    private var firstFrame = false
    private var handedOff = false
    private var paused = false
    private var frameTimeout: DispatchWorkItem?
    var onStatus: ((String) -> Void)?
    var onRelease: (() -> Void)?
    var onFailure: ((String) -> Void)?

    init(entry: WindowEntry, source: SCWindow) {
        self.entry = entry
        let width: CGFloat = 520
        let height = max(180, min(560, width * source.frame.height / max(source.frame.width, 1)))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height + 44),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "\(entry.app) · OpenPin"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 280, height: 190)
        panel.delegate = self
        let root = NSView()
        panel.contentView = root
        let icon = NSImageView()
        icon.image = NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("\(entry.app) App-Symbol")
        let title = NSTextField(labelWithString: entry.app)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let button = NSButton(title: "Original öffnen ↗", target: self, action: #selector(openOriginal))
        button.bezelStyle = .rounded
        button.toolTip = "Im Original bedienen. Beim App-Wechsel erscheint die Live-Ansicht wieder."
        for view in [icon, title, button, preview] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
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
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - width - 24, y: frame.maxY - 50))
        } else { panel.center() }
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
        panel.orderOut(nil)
        preview.video.sampleBufferRenderer.flush(removingDisplayedImage: true)
        let old = stream
        stream = nil
        Task { try? await old?.stopCapture() }
    }

    func update(frontPID: pid_t?, paused: Bool) {
        self.paused = paused
        if handedOff && frontPID != entry.pid {
            handedOff = false
            onStatus?("Live-Ansicht · oben angeheftet")
        }
        guard !stopped, firstFrame else { return }
        if paused || handedOff { panel.orderOut(nil) }
        else if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func show() {
        guard !stopped, firstFrame else { return }
        handedOff = false; paused = false
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func openOriginal() {
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else { onRelease?(); return }
        handedOff = true
        panel.orderOut(nil)
        _ = AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        _ = AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.unhide()
        app.activate(options: [])
        _ = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        onStatus?("Original geöffnet · Live-Ansicht kehrt beim App-Wechsel zurück")
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
            if !paused { panel.orderFrontRegardless() }
            onStatus?("Live-Ansicht · oben angeheftet")
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
    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updatePanels()
        }
    }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
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
                let session = LiveSession(entry: entry, source: source)
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
