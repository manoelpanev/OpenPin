import AppKit
import SwiftUI
import ApplicationServices

// Native AX handles only. No screenshots, synthetic input, or target activation.
func axValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func axRect(_ element: AXUIElement) -> CGRect? {
    guard let p = axValue(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = axValue(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func sameRect(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX-b.minX) < 3 && abs(a.minY-b.minY) < 3 && abs(a.width-b.width) < 3 && abs(a.height-b.height) < 3
}
struct WindowEntry: Identifiable {
    let id: UUID
    let element: AXUIElement
    let pid: pid_t
    let app: String
    let title: String
    var pinned = false
    var note = ""
}
struct VisibleWindow {
    let pid: pid_t
    let frame: CGRect
}
func uniqueSourceIndex(pid: pid_t, frame: CGRect, candidates: [VisibleWindow]) -> Int? {
    let matches = candidates.indices.filter { candidates[$0].pid == pid && sameRect(candidates[$0].frame, frame) }
    return matches.count == 1 ? matches.first : nil
}

final class PinEngine {
    private let queue = DispatchQueue(label: "local.openpin.windows", qos: .userInitiated)
    private var entries: [WindowEntry] = []
    private var timer: DispatchSourceTimer?
    private var paused = false
    private var lastScan = Date.distantPast
    private var trusted = false
    var onChange: (([WindowEntry], Bool, Bool) -> Void)?
    func start() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(300), leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source; source.resume()
    }
    func refresh() { queue.async { self.scan() } }
    func setPin(_ id: UUID, pinned: Bool, note: String) {
        queue.async {
            guard self.trusted, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
            self.entries[i].pinned = pinned; self.entries[i].note = note
            self.publish()
        }
    }
    func releaseAll() {
        queue.async {
            for i in self.entries.indices { self.entries[i].pinned = false; self.entries[i].note = "" }
            self.paused = false; self.publish()
        }
    }
    func setPaused(_ value: Bool) { queue.async { self.paused = value; self.publish() } }
    private func publish() {
        let copy = entries, access = trusted, pause = paused
        DispatchQueue.main.async { [weak self] in self?.onChange?(copy, access, pause) }
    }
    private func scan() {
        lastScan = Date(); trusted = AXIsProcessTrusted()
        guard trusted else { entries.removeAll(); publish(); return }
        var next: [WindowEntry] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let handle = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(handle, 0.08)
            guard let windows = axValue(handle, kAXWindowsAttribute) as? [AXUIElement] else {
                next.append(contentsOf: entries.filter { $0.pid == app.processIdentifier }); continue
            }
            for window in windows {
                guard !next.contains(where: { CFEqual($0.element, window) }) else { continue }
                AXUIElementSetMessagingTimeout(window, 0.08)
                let previous = entries.first { CFEqual($0.element, window) }
                let title = axValue(window, kAXTitleAttribute) as? String ?? previous?.title ?? ""
                guard let rect = axRect(window), rect.width > 80, rect.height > 50 else {
                    if let previous { next.append(previous) }; continue
                }
                var entry = WindowEntry(id: previous?.id ?? UUID(), element: window, pid: app.processIdentifier,
                    app: app.localizedName ?? "App", title: title.isEmpty ? "Fenster ohne Titel" : title)
                entry.pinned = previous?.pinned ?? false; entry.note = previous?.note ?? ""
                next.append(entry)
            }
        }
        entries = next.sorted { ($0.app, $0.title) < ($1.app, $1.title) }
        publish()
    }
    private func tick() {
        if Date().timeIntervalSince(lastScan) > 5 { scan() }
    }
}

final class PinModel: ObservableObject {
    @Published var windows: [WindowEntry] = []
    @Published var access = false
    @Published var paused = false
    @Published var query = ""
    @Published var pinnedOnly = false
    let engine = PinEngine()
    let live = LivePinController()
    var statusChanged: ((Int, Bool) -> Void)?
    var pinnedCount: Int { windows.filter(\.pinned).count }
    var filtered: [WindowEntry] {
        windows.filter { (!pinnedOnly || $0.pinned) && (query.isEmpty || "\($0.app) \($0.title)".localizedCaseInsensitiveContains(query)) }
    }
    init() {
        live.changed = { [weak self] id, pinned, note in self?.engine.setPin(id, pinned: pinned, note: note) }
        engine.onChange = { [weak self] entries, access, paused in
            guard let self else { return }
            self.windows = entries; self.access = access; self.paused = paused
            self.live.reconcile(entries, paused: paused)
            self.statusChanged?(self.pinnedCount, paused)
        }; engine.start()
    }
    func permissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func desktopSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func releaseAll() { live.releaseAll(); engine.releaseAll() }
}
private let accent = Color(red: 0.10, green: 0.49, blue: 0.43)
struct PinInterface: View {
    @ObservedObject var model: PinModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill").font(.system(size: 22)).foregroundStyle(accent)
                    Text("OpenPin").font(.system(size: 21, weight: .bold))
                }.padding(.top, 12)
                VStack(spacing: 6) {
                    navigation("Alle Fenster", icon: "macwindow.on.rectangle", count: model.windows.count, selected: !model.pinnedOnly) { model.pinnedOnly = false }
                    navigation("Angeheftet", icon: "pin", count: model.pinnedCount, selected: model.pinnedOnly) { model.pinnedOnly = true }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.access ? "Zugriff bereit" : "Zugriff benötigt", systemImage: model.access ? "checkmark.shield" : "lock")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(model.access ? accent : .orange)
                    Text("Schwebendes App-Symbol\nKeine Speicherung · Kein Ton").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Bedienungshilfen…") { model.permissions() }.buttonStyle(.link).font(.system(size: 12))
                    Divider().padding(.vertical, 4)
                    Button("Bildschirmaufnahme…") { model.desktopSettings() }.buttonStyle(.link).font(.system(size: 12))
                }
            }.padding(22).frame(width: 210).frame(maxHeight: .infinity).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.pinnedOnly ? "Deine angehefteten Fenster" : "Dein Fenster. An seinem Platz.").font(.system(size: 25, weight: .bold))
                        Text("Das App-Symbol schwebt oben. Ein Klick holt das Fenster heraus.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.engine.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Fensterliste aktualisieren").accessibilityLabel("Fensterliste aktualisieren")
                }.padding(.bottom, 22)
                if !model.access {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Einmal Zugriff erlauben", systemImage: "hand.raised.fill").font(.headline)
                        Text("OpenPin braucht Bedienungshilfen für die Fensterliste und zum Öffnen des Originals. Für die Live-Ansicht wird zusätzlich Bildschirmaufnahme benötigt. Die Bilder bleiben auf deinem Mac und werden nicht gespeichert.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Zugriff einrichten") { model.permissions() }.buttonStyle(.borderedProminent).tint(accent)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("App oder Fenstertitel suchen", text: $model.query).textFieldStyle(.plain)
                        if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Suche löschen") }
                    }.padding(11).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    HStack {
                        Text("\(model.filtered.count) FENSTER").font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
                        Spacer()
                        if model.pinnedCount > 0 {
                            Button(model.paused ? "Fortsetzen" : "Alle pausieren") { model.engine.setPaused(!model.paused) }.buttonStyle(.link)
                            Button("Alle lösen") { model.releaseAll() }.buttonStyle(.link)
                        }
                    }.font(.system(size: 12)).padding(.vertical, 16)
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(model.filtered) { entry in row(entry) }
                            if model.filtered.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: model.pinnedOnly ? "pin.slash" : "macwindow").font(.system(size: 30)).foregroundStyle(.tertiary)
                                    Text(model.pinnedOnly ? "Noch kein Fenster angeheftet" : "Keine passenden Fenster").font(.headline)
                                    Text(model.pinnedOnly ? "Wähle unter „Alle Fenster“ dein erstes Fenster." : "Öffne eine App oder ändere deine Suche.").foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(.vertical, 55)
                            }
                        }.padding(1)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle().fill(model.paused ? Color.orange : accent).frame(width: 7, height: 7)
                        Text(model.paused ? "Symbole ausgeblendet" : "\(model.pinnedCount) Fenster angeheftet").font(.system(size: 12, weight: .medium))
                    }
                    Text("Jedes angeheftete Fenster schwebt als App-Symbol oben. Klick auf das Symbol öffnet das Original. Die kleine Ecke am Fenster oder ⌃⌥P schickt es zurück ins Symbol. Rechtsklick zeigt die Live-Ansicht.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 12)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 900, minHeight: 590).tint(accent)
    }
    func navigation(_ title: String, icon: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon); Spacer()
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }.font(.system(size: 13, weight: selected ? .semibold : .regular))
                .padding(11).background(selected ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(selected ? accent : .primary)
        }.buttonStyle(.plain)
    }
    func row(_ entry: WindowEntry) -> some View {
        HStack(spacing: 13) {
            Image(nsImage: NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!)
                .resizable().frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.app).font(.system(size: 13, weight: .semibold))
                Text(entry.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).help(entry.title)
                if !entry.note.isEmpty { Text(entry.note).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }; Spacer(minLength: 8)
            Button { model.live.toggle(entry) } label: {
                Label(entry.pinned ? "Lösen" : "Anheften", systemImage: entry.pinned ? "pin.slash" : "pin").frame(width: 85)
            }.buttonStyle(.bordered).tint(entry.pinned ? accent : .secondary)
                .accessibilityLabel("\(entry.pinned ? "Lösen" : "Anheften"): \(entry.app), \(entry.title)")
        }.padding(14).background(entry.pinned ? accent.opacity(0.055) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(entry.pinned ? accent.opacity(0.3) : Color.primary.opacity(0.07)))
    }
}
final class PinApplication: NSObject, NSApplicationDelegate {
    let model = PinModel()
    var window: NSWindow!
    var status: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(); let parent = NSMenuItem(); main.addItem(parent)
        let appMenu = NSMenu(); parent.submenu = appMenu
        appMenu.addItem(withTitle: "OpenPin beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "Bearbeiten"; main.addItem(edit); edit.submenu = NSMenu(title: "Bearbeiten")
        for (title, action, key) in [("Ausschneiden", "cut:", "x"), ("Kopieren", "copy:", "c"), ("Einfügen", "paste:", "v"), ("Alles auswählen", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
        let windowsMenu = NSMenuItem(title: "Fenster", action: nil, keyEquivalent: "")
        windowsMenu.submenu = NSMenu(title: "Fenster")
        let showLive = NSMenuItem(title: "Live-Ansichten anzeigen", action: #selector(showLiveViews), keyEquivalent: "l")
        showLive.target = self
        windowsMenu.submenu?.addItem(showLive)
        main.addItem(windowsMenu)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "OpenPin")
        let menu = NSMenu()
        for (title, selector) in [("OpenPin öffnen", #selector(show)), ("Fenster zurück ins Symbol  ⌃⌥P", #selector(returnToIcon)), ("Alle lösen", #selector(releaseAll)), ("Beenden", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }; status.menu = menu
        model.statusChanged = { [weak self] count, paused in self?.status.button?.title = count > 0 ? " \(count)\(paused ? " Ⅱ" : "")" : "" }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "OpenPin"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PinInterface(model: model))
        window.minSize = NSSize(width: 900, height: 620); window.center(); show()
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func releaseAll() { model.releaseAll() }
    @objc func returnToIcon() { model.live.returnFrontToIcon() }
    @objc func showLiveViews() { model.engine.setPaused(false); model.live.showAll() }
    func applicationWillTerminate(_ notification: Notification) { model.live.releaseAll() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}
#if !PIN_TESTS
@main struct PinMain {
    static func main() {
        if CommandLine.arguments.contains("--window-order") {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            for info in windows where (info[kCGWindowLayer as String] as? Int) == 0 || (info[kCGWindowOwnerName as String] as? String) == "OpenPin" {
                let rect = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
                print("\(info[kCGWindowOwnerName as String] ?? "?") layer=\(info[kCGWindowLayer as String] ?? 0) pid=\(info[kCGWindowOwnerPID as String] ?? 0) id=\(info[kCGWindowNumber as String] ?? 0) bounds=\(rect)")
            }
            return
        }
        let application = NSApplication.shared
        let delegate = PinApplication()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif
