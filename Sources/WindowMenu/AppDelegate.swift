import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    /// Icono pequeño para ajustes (y de paso nos da la apariencia real de la barra de menús).
    private var statusItem: NSStatusItem!
    private let tracker = WindowTracker()
    private var timer: Timer?
    private var statusTimer: Timer?

    /// Distancia desde el borde derecho del monitor hasta el primer icono de la barra de menús.
    private var statusOffset: CGFloat?
    private var scanningStatusItems = false

    /// Ancho de los menús (Archivo, Edición…) por monitor. Cada monitor muestra los menús
    /// de la última app que estuvo activa en él, así que solo se mide el del monitor activo.
    private var menusOffsets: [CGDirectDisplayID: CGFloat] = [:]

    @MainActor
    private final class Bar {
        let panel = TaskbarPanel()
        let view = TaskbarView()
        var signature = ""
        init() { panel.contentView = view }
    }
    /// Una barra por monitor.
    private var bars: [CGDirectDisplayID: Bar] = [:]

    /// Orden estable (como en Windows): los botones no saltan al cambiar el foco.
    private var order: [CGWindowID: Int] = [:]
    private var nextOrder = 0

    private let defaults = UserDefaults.standard

    // Ajustes: globales en sus claves de siempre; los de cada monitor personalizado, en "display.<UUID>",
    // con una copia completa (no hereda nada del global). `monitor == nil` = global.
    private let defaultSettings: [String: Any] = ["showTitles": true, "maxWidth": 700.0, "alignRight": true]

    private func customSettings(_ monitor: String) -> [String: Any] {
        defaults.dictionary(forKey: "display.\(monitor)") ?? [:]
    }
    private func setting(_ key: String, _ monitor: String?) -> Any? {
        monitor.flatMap { customSettings($0)[key] } ?? defaults.object(forKey: key)
    }
    private func showTitles(_ monitor: String?) -> Bool { setting("showTitles", monitor) as? Bool ?? true }
    private func maxWidth(_ monitor: String?) -> CGFloat { CGFloat(setting("maxWidth", monitor) as? Double ?? 700) }
    private func alignRight(_ monitor: String?) -> Bool { setting("alignRight", monitor) as? Bool ?? true }

    /// Rellena los ajustes de un monitor con los globales que le falten.
    private func completed(_ settings: [String: Any]) -> [String: Any] {
        var d = settings
        for key in defaultSettings.keys where d[key] == nil { d[key] = defaults.object(forKey: key) }
        return d
    }

    private func set(_ value: Any, _ key: String, _ monitor: String?) {
        if let monitor {
            var d = completed(customSettings(monitor))   // al personalizarlo, se congela con los globales actuales
            d[key] = value
            defaults.set(d, forKey: "display.\(monitor)")
        } else {
            defaults.set(value, forKey: key)
        }
        invalidate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: defaultSettings)
        // Monitores guardados cuando solo se guardaban los valores cambiados: completarlos ya.
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("display.") {
            guard let d = value as? [String: Any], !d.isEmpty else { continue }
            let full = completed(d)
            if full.count != d.count { defaults.set(full, forKey: key) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                           accessibilityDescription: "WindowMenu")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        timer = Timer.scheduledTimer(timeInterval: 0.7, target: self, selector: #selector(refresh),
                                     userInfo: nil, repeats: true)
        statusTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(scanStatusItems),
                                           userInfo: nil, repeats: true)

        if !tracker.isTrusted { tracker.requestAccessibility() }
        rebuildBars()
        scanStatusItems()
        refresh()
    }

    // MARK: Monitores

    @objc private func screensChanged() {
        rebuildBars()
        invalidate()
    }

    private func rebuildBars() {
        let ids = Set(NSScreen.screens.compactMap { WindowTracker.displayID(of: $0) })
        for (id, bar) in bars where !ids.contains(id) {
            bar.panel.orderOut(nil)
            bars[id] = nil
            menusOffsets[id] = nil
        }
        for id in ids where bars[id] == nil {
            let bar = Bar()
            bar.view.onClick = { [weak self] item in self?.handleClick(item) }
            bar.view.onRightClick = { [weak self, weak bar] event in
                guard let self, let view = bar?.view else { return }
                NSMenu.popUpContextMenu(self.buildMenu(for: id), with: event, for: view)
            }
            bars[id] = bar
        }
    }

    private func invalidate() {
        bars.values.forEach { $0.signature = "" }
        refresh()
    }

    // MARK: Refresco

    @objc private func refresh() {
        let all = tracker.snapshot()
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedID = tracker.focusedWindowID()
            ?? all.first(where: { !$0.isMinimized && $0.pid == frontPid })?.id
        let activeDisplay = all.first(where: { $0.id == focusedID })?.displayID
            ?? WindowTracker.displayUnderMouse()

        for w in all where order[w.id] == nil { order[w.id] = nextOrder; nextOrder += 1 }
        let sorted = all.sorted { order[$0.id]! < order[$1.id]! }

        let screens = NSScreen.screens

        // Ancho de los menús de la app activa, en el monitor donde se muestran.
        if let p = tracker.appMenusEnd(),
           let s = screens.first(where: { WindowTracker.cgFrame(of: $0).contains(p) }),
           let id = WindowTracker.displayID(of: s) {
            menusOffsets[id] = p.x - s.frame.minX
        }

        let appearance = statusItem.button?.effectiveAppearance

        for screen in screens {
            guard let id = WindowTracker.displayID(of: screen), let bar = bars[id] else { continue }

            let windows = sorted.filter {
                $0.displayID == id || ($0.isMinimized && $0.displayID == nil && id == activeDisplay)
            }
            let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
            guard !windows.isEmpty, menuBarH >= 10 else {   // sin ventanas o barra oculta
                bar.panel.orderOut(nil); bar.signature = ""; continue
            }

            // Límites horizontales libres en la barra de este monitor
            let rightLimit = screen.frame.maxX - (statusOffset ?? 350)
            var leftLimit = screen.frame.minX + (menusOffsets[id] ?? 320) + 16
            if #available(macOS 12, *), let right = screen.auxiliaryTopRightArea {   // notch
                leftLimit = max(leftLimit, screen.frame.maxX - right.width + 8)
            }
            let available = rightLimit - 8 - leftLimit
            guard available >= 28 else { bar.panel.orderOut(nil); bar.signature = ""; continue }

            let items = windows.map { TaskItem(window: $0, isFocused: $0.id == focusedID) }
            let monitor = WindowTracker.displayUUID(id)
            bar.view.showTitles = showTitles(monitor)
            bar.view.maxTotalWidth = min(maxWidth(monitor), available)
            bar.view.items = items
            let width = min(bar.view.preferredWidth, available)
            let x = alignRight(monitor) ? rightLimit - 8 - width : leftLimit
            let frame = NSRect(x: x, y: screen.frame.maxY - menuBarH, width: width, height: menuBarH)

            let signature = items.map { "\($0.window.id)|\($0.window.label)|\($0.window.isMinimized)|\($0.isFocused)" }
                .joined(separator: ";") + "#\(frame)"
            if signature != bar.signature {
                bar.signature = signature
                bar.panel.setFrame(frame, display: true)
                bar.view.needsDisplay = true
            }
            if bar.panel.appearance?.name != appearance?.name { bar.panel.appearance = appearance }
            if !bar.panel.isVisible { bar.panel.orderFrontRegardless() }
        }

        let alive = Set(all.map(\.id))
        order = order.filter { alive.contains($0.key) }
    }

    // MARK: Iconos de la barra de menús

    /// Lee las posiciones de los iconos en segundo plano (tarda ~1 s con muchas apps).
    @objc private func scanStatusItems() {
        guard !scanningStatusItems else { return }
        scanningStatusItems = true
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        DispatchQueue.global(qos: .utility).async {
            let frames = WindowTracker.statusItemFrames(pids: pids)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanningStatusItems = false
                self.updateStatusOffset(frames)
            }
        }
    }

    /// Cada app reporta sus iconos en un solo monitor (no siempre el mismo), pero todas las barras
    /// muestran los mismos iconos alineados a la derecha: nos quedamos con la mayor distancia.
    private func updateStatusOffset(_ frames: [CGRect]) {
        var offset: CGFloat?
        for s in NSScreen.screens {
            let cg = WindowTracker.cgFrame(of: s)
            let strip = CGRect(x: cg.minX, y: cg.minY, width: cg.width, height: 60)
            // Los iconos ocultos (overflow, notch) dan posiciones fuera de la barra.
            for f in frames where strip.contains(CGPoint(x: f.midX, y: f.midY)) {
                offset = max(offset ?? 0, s.frame.maxX - f.minX)
            }
        }
        guard offset != statusOffset else { return }
        statusOffset = offset
        invalidate()
    }

    private func handleClick(_ item: TaskItem) {
        if item.isFocused && !item.window.isMinimized {
            tracker.minimize(item.window)          // clic en la activa = minimizar (como Windows)
        } else {
            tracker.focus(item.window)
        }
        for delay in [0.1, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    // MARK: Menú de ajustes

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(for: WindowTracker.displayUnderMouse()).items.forEach { item in
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    /// Menú de ajustes. `displayID` es el monitor de la barra (o el del ratón, desde el icono).
    private func buildMenu(for displayID: CGDirectDisplayID?) -> NSMenu {
        let menu = NSMenu()

        if !tracker.isTrusted {
            menu.addItem(item("⚠︎ Conceder permiso de Accesibilidad…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let global = NSMenuItem(title: "Global (por defecto)", action: nil, keyEquivalent: "")
        global.submenu = settingsMenu(nil)
        menu.addItem(global)

        if let displayID, let monitor = WindowTracker.displayUUID(displayID) {
            let name = NSScreen.screens.first { WindowTracker.displayID(of: $0) == displayID }?.localizedName
            let this = NSMenuItem(title: "Este monitor: \(name ?? "?")", action: nil, keyEquivalent: "")
            let sub = settingsMenu(monitor)
            sub.addItem(.separator())
            let reset = item("Usar ajustes globales", #selector(resetMonitor(_:)))
            reset.representedObject = monitor
            if customSettings(monitor).isEmpty { reset.action = nil }   // deshabilitado
            sub.addItem(reset)
            this.submenu = sub
            menu.addItem(this)
        }

        menu.addItem(.separator())
        let login = item("Abrir al iniciar sesión", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// Títulos, ancho y posición de un monitor (o los globales si `monitor == nil`).
    private func settingsMenu(_ monitor: String?) -> NSMenu {
        let menu = NSMenu()

        let titles = item("Mostrar títulos", #selector(toggleTitles(_:)), monitor)
        titles.state = showTitles(monitor) ? .on : .off
        menu.addItem(titles)

        let widthItem = NSMenuItem(title: "Ancho máximo", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for w in [400, 600, 800, 1000, 1400] {
            let i = item("\(w) pt", #selector(setMaxWidth(_:)), monitor)
            i.tag = w
            i.state = Int(maxWidth(monitor)) == w ? .on : .off
            sub.addItem(i)
        }
        widthItem.submenu = sub
        menu.addItem(widthItem)

        let posItem = NSMenuItem(title: "Posición", action: nil, keyEquivalent: "")
        let pos = NSMenu()
        let r = item("Junto a los iconos (derecha)", #selector(setAlign(_:)), monitor); r.tag = 1
        let l = item("Junto a los menús (izquierda)", #selector(setAlign(_:)), monitor); l.tag = 0
        r.state = alignRight(monitor) ? .on : .off
        l.state = alignRight(monitor) ? .off : .on
        pos.addItem(r); pos.addItem(l)
        posItem.submenu = pos
        menu.addItem(posItem)
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ monitor: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.representedObject = monitor
        return i
    }

    @objc private func toggleTitles(_ sender: NSMenuItem) {
        let monitor = sender.representedObject as? String
        set(!showTitles(monitor), "showTitles", monitor)
    }

    @objc private func setMaxWidth(_ sender: NSMenuItem) {
        set(Double(sender.tag), "maxWidth", sender.representedObject as? String)
    }

    @objc private func setAlign(_ sender: NSMenuItem) {
        set(sender.tag == 1, "alignRight", sender.representedObject as? String)
    }

    @objc private func resetMonitor(_ sender: NSMenuItem) {
        guard let monitor = sender.representedObject as? String else { return }
        defaults.removeObject(forKey: "display.\(monitor)")
        invalidate()
    }

    @objc private func openAccessibilitySettings() {
        tracker.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Launch at login error: \(error)") }
    }
}
