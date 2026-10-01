import AppKit
import ApplicationServices

// API privada (la usan AltTab, Rectangle, etc.) para obtener el CGWindowID de un AXUIElement.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let displayID: CGDirectDisplayID?
    let axElement: AXUIElement?
    let appIcon: NSImage?
    let isMinimized: Bool

    var label: String { title.isEmpty ? appName : title }
    var tooltip: String { title.isEmpty ? appName : "\(appName) — \(title)" }
}

final class WindowTracker {

    /// Último monitor en el que vimos cada ventana (para ubicar las minimizadas).
    private var lastDisplay: [CGWindowID: CGDirectDisplayID] = [:]

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Ventanas visibles del Space actual (todos los monitores) + minimizadas.
    func snapshot() -> [WindowInfo] {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let trusted = isTrusted
        var axCache: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()

        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            if cgBounds.width < 40 || cgBounds.height < 40 { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            if app?.activationPolicy == .prohibited { continue }

            if axCache[pid] == nil { axCache[pid] = axWindows(pid: pid) }
            let ax = axCache[pid]?[wid]
            if trusted && ax == nil { continue }   // descarta ventanas "fantasma"
            // Durante la animación hacia el Dock sigue en pantalla, pero ya encima del monitor del Dock:
            // se trata como minimizada para no perder su monitor.
            if let ax, axBool(ax, kAXMinimizedAttribute) == true { continue }

            let display = Self.displayID(of: Self.bestScreen(for: Self.toAppKit(cgBounds)))
            if let display { lastDisplay[wid] = display }

            let title = ax.flatMap { axString($0, kAXTitleAttribute) }
                ?? (info[kCGWindowName as String] as? String) ?? ""
            result.append(WindowInfo(
                id: wid, pid: pid,
                appName: app?.localizedName ?? (info[kCGWindowOwnerName as String] as? String) ?? "?",
                title: title, displayID: display, axElement: ax, appIcon: app?.icon, isMinimized: false))
            seen.insert(wid)
        }

        // Minimizadas (solo con permiso de Accesibilidad)
        if trusted {
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != myPid && !app.isHidden {
                let pid = app.processIdentifier
                let map = axCache[pid] ?? axWindows(pid: pid)
                for (wid, el) in map where !seen.contains(wid) {
                    guard axBool(el, kAXMinimizedAttribute) == true,
                          axString(el, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String)
                    else { continue }
                    result.append(WindowInfo(
                        id: wid, pid: pid, appName: app.localizedName ?? "?",
                        title: axString(el, kAXTitleAttribute) ?? "",
                        displayID: lastDisplay[wid], axElement: el, appIcon: app.icon, isMinimized: true))
                }
            }
        }
        return result
    }

    func focusedWindowID() -> CGWindowID? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        guard let win = Self.axElement(appEl, kAXFocusedWindowAttribute) else { return nil }
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(win, &wid) == .success ? wid : nil
    }

    func focus(_ w: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: w.pid) else { return }
        let appEl = AXUIElementCreateApplication(w.pid)

        if w.isMinimized, let ax = w.axElement {
            AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        func raise() {
            guard let ax = w.axElement else { return }
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
        }
        raise()
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { raise() }
    }

    func minimize(_ w: WindowInfo) {
        guard let ax = w.axElement else { return }
        AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: - Menu bar geometry

    /// Marcos (coordenadas Quartz) de los iconos de la barra de menús (status items) de las apps dadas.
    /// Desde macOS 26 ya no aparecen en CGWindowList: se leen por Accesibilidad (AXExtrasMenuBar).
    /// Lento (una llamada AX por app): llamar fuera del hilo principal.
    static func statusItemFrames(pids: [pid_t]) -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        var frames: [CGRect] = []
        for pid in pids {
            let appEl = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appEl, 0.1)
            guard let bar = Self.axElement(appEl, "AXExtrasMenuBar") else { continue }
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &v) == .success,
                  let children = v as? [AXUIElement] else { continue }
            for child in children {
                guard let pos = Self.axPoint(child), let size = Self.axSize(child), size.width > 0 else { continue }
                frames.append(CGRect(origin: pos, size: size))
            }
        }
        return frames
    }

    /// Punto (coordenadas Quartz) donde terminan los menús de la app activa (Archivo, Edición…).
    func appMenusEnd() -> CGPoint? {
        guard isTrusted, let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        guard let bar = Self.axElement(appEl, kAXMenuBarAttribute) else { return nil }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &v) == .success,
              let children = v as? [AXUIElement], let last = children.last,
              let pos = Self.axPoint(last), let size = Self.axSize(last) else { return nil }
        return CGPoint(x: pos.x + size.width, y: pos.y + size.height / 2)
    }

    // MARK: - AX helpers

    private static func axPoint(_ el: AXUIElement) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func axSize(_ el: AXUIElement) -> CGSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    private func axWindows(pid: pid_t) -> [CGWindowID: AXUIElement] {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
              let arr = value as? [AXUIElement] else { return [:] }
        var map: [CGWindowID: AXUIElement] = [:]
        for el in arr {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(el, &wid) == .success { map[wid] = el }
        }
        return map
    }

    private func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return (v as? NSNumber)?.boolValue
    }

    private static func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    // MARK: - Screen helpers

    /// Quartz: origen arriba-izquierda del monitor principal. AppKit: abajo-izquierda.
    static func toAppKit(_ r: CGRect) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
    }

    /// Marco de una pantalla en coordenadas Quartz.
    static func cgFrame(of screen: NSScreen) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
    }

    static func bestScreen(for frame: CGRect) -> NSScreen? {
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        return NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
    }

    static func displayID(of screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Identificador estable de un monitor (sobrevive a reconexiones, a diferencia del CGDirectDisplayID).
    static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func displayUnderMouse() -> CGDirectDisplayID? {
        let p = NSEvent.mouseLocation
        return displayID(of: NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main)
    }
}
