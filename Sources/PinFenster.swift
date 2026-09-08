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
enum RaiseDecision { case unavailable, clear, covered }
func raiseDecision(target: VisibleWindow, ordered: [VisibleWindow], pinned: [VisibleWindow]) -> RaiseDecision {
    let positions = ordered.indices.filter { ordered[$0].pid == target.pid && sameRect(ordered[$0].frame, target.frame) }
    guard positions.count == 1, let position = positions.first else { return .unavailable }
    let covered = ordered.prefix(position).contains { other in
        other.frame.intersects(target.frame) && !pinned.contains { $0.pid == other.pid && sameRect($0.frame, other.frame) }
    }
    return covered ? .covered : .clear
}

final class PinEngine {
    private let queue = DispatchQueue(label: "local.pinfenster.windows", qos: .userInitiated)
    private var entries: [WindowEntry] = []
    private var errors: [UUID: Int] = [:]
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
    func toggle(_ id: UUID) {
        queue.async {
            guard self.trusted, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
            self.entries[i].pinned.toggle(); self.entries[i].note = ""; self.errors[id] = nil
            self.publish()
        }
    }
    func releaseAll() {
        queue.async {
            for i in self.entries.indices { self.entries[i].pinned = false; self.entries[i].note = "" }
            self.errors.removeAll(); self.paused = false; self.publish()
        }
    }
    func setPaused(_ value: Bool) { queue.async { self.paused = value; self.publish() } }
    private func publish() {
        let copy = entries, access = trusted, pause = paused
        DispatchQueue.main.async { [weak self] in self?.onChange?(copy, access, pause) }
    }
    private func scan() {
        lastScan = Date(); trusted = AXIsProcessTrusted()
        guard trusted else { entries.removeAll(); errors.removeAll(); publish(); return }
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
        let ids = Set(entries.map(\.id)); errors = errors.filter { ids.contains($0.key) }
        publish()
    }
    private func tick() {
        if Date().timeIntervalSince(lastScan) > 5 { scan() }
        guard trusted, !paused, entries.contains(where: \.pinned) else { return }
        guard AXIsProcessTrusted() else { scan(); return }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front != ProcessInfo.processInfo.processIdentifier else { return }
        // Metadata is sufficient; no capture or window titles from CG are needed.
        let infos = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let normal: [VisibleWindow] = infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict) else { return nil }
            return VisibleWindow(pid: pid, frame: frame)
        }
        let pins: [VisibleWindow] = entries.filter(\.pinned).compactMap { entry in
            guard let frame = axRect(entry.element) else { return nil }; return VisibleWindow(pid: entry.pid, frame: frame)
        }
        var changed = false
        for i in entries.indices where entries[i].pinned {
            let entry = entries[i]
            guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else { continue }
            if app.isHidden || (axValue(entry.element, kAXMinimizedAttribute) as? Bool) == true {
                if entries[i].note != "Pausiert · Fenster ausgeblendet" { entries[i].note = "Pausiert · Fenster ausgeblendet"; changed = true }; continue
            }
            guard let rect = axRect(entry.element) else { continue }
            let decision = raiseDecision(target: VisibleWindow(pid: entry.pid, frame: rect), ordered: normal, pinned: pins)
            guard decision != .unavailable else {
                if entries[i].note != "Wartet · Fenster nicht sichtbar oder nicht eindeutig" {
                    entries[i].note = "Wartet · Fenster nicht sichtbar oder nicht eindeutig"; changed = true
                }; continue
            }
            if !entries[i].note.isEmpty { entries[i].note = ""; changed = true }
            guard decision == .covered else { continue }
            let result = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
            if front != entry.pid && NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.pid {
                paused = true; entries[i].note = "Pausiert · App hat den Eingabefokus übernommen"; publish(); return
            }
            if result == .success { errors[entry.id] = 0 }
            else {
                errors[entry.id, default: 0] += 1
                if errors[entry.id, default: 0] >= 3 {
                    entries[i].pinned = false
                    entries[i].note = "Nicht unterstützt · Vorholen fehlgeschlagen (\(result.rawValue))"; changed = true
                }
            }
        }
        if changed { publish() }
    }
}

final class PinModel: ObservableObject {
    @Published var windows: [WindowEntry] = []
    @Published var access = false
    @Published var paused = false
    @Published var query = ""
    @Published var pinnedOnly = false
    let engine = PinEngine()
    var statusChanged: ((Int, Bool) -> Void)?
    var pinnedCount: Int { windows.filter(\.pinned).count }
    var filtered: [WindowEntry] {
        windows.filter { (!pinnedOnly || $0.pinned) && (query.isEmpty || "\($0.app) \($0.title)".localizedCaseInsensitiveContains(query)) }
    }
    init() {
        engine.onChange = { [weak self] entries, access, paused in
            guard let self else { return }
            self.windows = entries; self.access = access; self.paused = paused
            self.statusChanged?(self.pinnedCount, paused)
        }; engine.start()
    }
    func permissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func desktopSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }
}
private let accent = Color(red: 0.10, green: 0.49, blue: 0.43)
struct PinInterface: View {
    @ObservedObject var model: PinModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill").font(.system(size: 22)).foregroundStyle(accent)
                    Text("PinFenster").font(.system(size: 21, weight: .bold))
                }.padding(.top, 12)
                VStack(spacing: 6) {
                    navigation("Alle Fenster", icon: "macwindow.on.rectangle", count: model.windows.count, selected: !model.pinnedOnly) { model.pinnedOnly = false }
                    navigation("Angeheftet", icon: "pin", count: model.pinnedCount, selected: model.pinnedOnly) { model.pinnedOnly = true }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.access ? "Zugriff bereit" : "Zugriff benötigt", systemImage: model.access ? "checkmark.shield" : "lock")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(model.access ? accent : .orange)
                    Text("Originalfenster\nKeine Bildschirmaufnahme").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Bedienungshilfen…") { model.permissions() }.buttonStyle(.link).font(.system(size: 12))
                    Divider().padding(.vertical, 4)
                    Button("Desktop-Verhalten…") { model.desktopSettings() }.buttonStyle(.link).font(.system(size: 12))
                }
            }.padding(22).frame(width: 210).frame(maxHeight: .infinity).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.pinnedOnly ? "Deine angehefteten Fenster" : "Dein Fenster. An seinem Platz.").font(.system(size: 25, weight: .bold))
                        Text("Anheften, direkt bedienen und jederzeit wieder lösen.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.engine.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Fensterliste aktualisieren").accessibilityLabel("Fensterliste aktualisieren")
                }.padding(.bottom, 22)
                if !model.access {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Einmal Zugriff erlauben", systemImage: "hand.raised.fill").font(.headline)
                        Text("PinFenster braucht Bedienungshilfen, um deine Originalfenster nach vorne zu holen. Aktiviere PinFenster in den Systemeinstellungen. Die Liste lädt anschließend automatisch.")
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
                            Button("Alle lösen") { model.engine.releaseAll() }.buttonStyle(.link)
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
                        Text(model.paused ? "Vorholen pausiert" : "\(model.pinnedCount) Fenster zum Vorholen markiert").font(.system(size: 12, weight: .medium))
                    }
                    Text("Automatisches Vorholen: macOS garantiert kein dauerhaftes Obenbleiben. Bei „Schreibtisch anzeigen“ können Fenster weiterhin verschwinden.")
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
            Button { model.engine.toggle(entry.id) } label: {
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
        appMenu.addItem(withTitle: "PinFenster beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "Bearbeiten"; main.addItem(edit); edit.submenu = NSMenu(title: "Bearbeiten")
        for (title, action, key) in [("Ausschneiden", "cut:", "x"), ("Kopieren", "copy:", "c"), ("Einfügen", "paste:", "v"), ("Alles auswählen", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "PinFenster")
        let menu = NSMenu()
        for (title, selector) in [("PinFenster öffnen", #selector(show)), ("Alle lösen", #selector(releaseAll)), ("Beenden", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }; status.menu = menu
        model.statusChanged = { [weak self] count, paused in self?.status.button?.title = count > 0 ? " \(count)\(paused ? " Ⅱ" : "")" : "" }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "PinFenster"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PinInterface(model: model))
        window.minSize = NSSize(width: 900, height: 620); window.center(); show()
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func releaseAll() { model.engine.releaseAll() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}
#if !PIN_TESTS
@main struct PinMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = PinApplication()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif
