import AppKit
import SwiftUI
import Carbon.HIToolbox
import ScreenCaptureKit

/// A single still frame grabbed for the switcher: SCScreenshotManager takes one image and returns,
/// no stream to start or stop — the overlay is shown only briefly, so a live stream would outlive its purpose.
/// CGWindowListCreateImage, the older synchronous API, was removed in macOS 15; this needs Screen Recording access,
/// the same permission the live-view pins already request.
@MainActor
func windowThumbnail(_ entry: WindowEntry, content: SCShareableContent) async -> NSImage? {
    guard let rect = axRect(entry.element),
          let source = content.windows.first(where: { $0.owningApplication?.processID == entry.pid && sameRect($0.frame, rect) })
    else { return nil }
    let filter = SCContentFilter(desktopIndependentWindow: source)
    let config = SCStreamConfiguration()
    let scale = min(2, 900 / max(filter.contentRect.width, filter.contentRect.height, 1))
    config.width = max(2, Int(filter.contentRect.width * scale))
    config.height = max(2, Int(filter.contentRect.height * scale))
    config.showsCursor = false
    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}

/// One entry in the app grid — one per running app that has at least one open window.
struct SwitchTarget: Identifiable {
    let id: UUID
    let pid: pid_t
    let app: String
    var icon: NSImage { NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(named: NSImage.applicationIconName)! }
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowEntry] = []
    @Published var thumbnails: [UUID: NSImage] = [:]
    @Published var selection = 0
    private var loadToken = UUID()

    var apps: [SwitchTarget] {
        var seen = Set<pid_t>()
        var out: [SwitchTarget] = []
        for entry in windows where !seen.contains(entry.pid) {
            seen.insert(entry.pid)
            out.append(SwitchTarget(id: entry.id, pid: entry.pid, app: entry.app))
        }
        return out.sorted { $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
    }

    /// Snapshot the current window list fresh each time the overlay opens, and load thumbnails one at a time
    /// in the background — SCScreenshotManager calls are relatively heavy, so this avoids flooding them at once.
    func refresh(_ entries: [WindowEntry]) {
        windows = entries.sorted { ($0.app, $0.title) < ($1.app, $1.title) }
        selection = 0
        let token = UUID(); loadToken = token
        thumbnails.removeAll()
        Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            guard let self else { return }
            for entry in self.windows {
                guard self.loadToken == token else { return }
                if let image = await windowThumbnail(entry, content: content), self.loadToken == token {
                    self.thumbnails[entry.id] = image
                }
            }
        }
    }
    func moveSelection(_ delta: Int) {
        let count = windows.count
        guard count > 0 else { return }
        selection = ((selection + delta) % count + count) % count
    }
}

/// A rounded thumbnail card with the app icon and title beneath it — the top row of the overlay.
struct ThumbnailCard: View {
    let entry: WindowEntry
    let image: NSImage?
    let selected: Bool
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06))
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(6) }
                else { ProgressView().controlSize(.small) }
            }.frame(width: 220, height: 140)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.10), lineWidth: selected ? 2.5 : 1))
            HStack(spacing: 6) {
                Image(nsImage: NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!)
                    .resizable().frame(width: 16, height: 16)
                Text(entry.app).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }.frame(width: 220, alignment: .leading)
        }
    }
}

/// One app icon in the grid beneath the thumbnails — click switches straight to that app.
struct AppIconTile: View {
    let target: SwitchTarget
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: target.icon).resizable().frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            Text(target.app).font(.system(size: 11)).lineLimit(1).foregroundStyle(.secondary)
        }.frame(width: 72)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    var onPick: (WindowEntry) -> Void
    var onPickApp: (pid_t) -> Void
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                Text("Offene Fenster").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.windows.count) FENSTER").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            if model.windows.isEmpty {
                Text("Keine offenen Fenster").foregroundStyle(.secondary).frame(height: 140)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, entry in
                            ThumbnailCard(entry: entry, image: model.thumbnails[entry.id], selected: index == model.selection)
                                .onTapGesture { onPick(entry) }
                        }
                    }.padding(.horizontal, 2)
                }
            }
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3").foregroundStyle(.secondary)
                Text("Alle offenen Apps").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 16), count: 8), spacing: 16) {
                    ForEach(model.apps) { target in
                        AppIconTile(target: target).onTapGesture { onPickApp(target.pid) }
                    }
                }
            }.frame(maxHeight: 220)
        }
        .padding(24)
        .frame(width: 980)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        .preferredColorScheme(.dark)
    }
}

/// Dark vibrancy behind the card, independent of the system appearance — the switcher is always dark.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.appearance = NSAppearance(named: .vibrantDark)
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The overlay panel: borderless, floats above everything, closes on Escape or losing key focus.
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}

/// Owns the global shortcut, the panel, and the window-picking logic.
@MainActor
final class SwitcherController: NSObject, NSWindowDelegate {
    private let panel = SwitcherPanel()
    private let model = SwitcherModel()
    private var keyMonitor: Any?
    private var localMonitor: Any?
    private var latestEntries: [WindowEntry] = []
    private var visible = false

    func install() {
        let host = NSHostingView(rootView: SwitcherView(
            model: model,
            onPick: { [weak self] entry in self?.activate(entry) },
            onPickApp: { [weak self] pid in self?.activateApp(pid) }))
        panel.contentView = host
        panel.delegate = self
        // ⌥Space: doesn't collide with Spotlight (⌘Space) or Mission Control defaults, and is easy to reach one-handed.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == kVK_Space, event.modifierFlags.contains(.option) else { return }
            self?.toggle()
        }
    }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) } }

    func reconcile(_ entries: [WindowEntry]) { latestEntries = entries }

    /// Menu-bar entry point, distinct from the shortcut monitor so it always opens rather than toggling closed.
    func showFromMenu() { if !visible { show() } }

    private func toggle() { visible ? hide() : show() }

    private func show() {
        model.refresh(latestEntries)
        // Fixed card size (the SwiftUI root view pins its own width); fittingSize is unreliable before first layout.
        let content = NSSize(width: 980, height: 500)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.frame {
            panel.setFrame(NSRect(x: frame.midX - content.width / 2, y: frame.midY - content.height / 2, width: content.width, height: content.height), display: false)
        }
        panel.alphaValue = 0
        // Activate first: doing this after makeKeyAndOrderFront steals the panel's key status right back,
        // which immediately fires windowDidResignKey and closes the panel before it is ever seen.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        visible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape: self.hide(); return nil
            case kVK_RightArrow: self.model.moveSelection(1); return nil
            case kVK_LeftArrow: self.model.moveSelection(-1); return nil
            case kVK_Return:
                if self.model.windows.indices.contains(self.model.selection) { self.activate(self.model.windows[self.model.selection]) }
                return nil
            default: return event
            }
        }
    }
    private func hide() {
        guard visible else { return }
        visible = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.panel.orderOut(nil) })
    }
    private func activate(_ entry: WindowEntry) {
        hide()
        guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        app.activate(options: [])
        _ = AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        _ = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
    }
    private func activateApp(_ pid: pid_t) {
        hide()
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
    func windowDidResignKey(_ notification: Notification) { hide() }
}
