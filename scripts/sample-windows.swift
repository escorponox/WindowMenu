#!/usr/bin/env swift
// Diagnóstico: muestrea CGWindowList cada 20 ms e imprime cada cambio de monitor o tamaño de las ventanas,
// con su estado minimizado según Accesibilidad. Sirve para ver qué ve WindowMenu durante animaciones
// (p. ej. al minimizar, la ventana sigue en pantalla ~300 ms encogiéndose sobre el monitor del Dock).
//
// Uso:  swift scripts/sample-windows.swift [segundos]   (por defecto 8)
// Sin permiso de Accesibilidad para la terminal, el estado minimizado sale como "ax?".
import AppKit

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

func axMinimized(pid: pid_t, wid: CGWindowID) -> String {
    let app = AXUIElementCreateApplication(pid)
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return "ax?" }
    for el in arr {
        var w: CGWindowID = 0
        guard _AXUIElementGetWindow(el, &w) == .success, w == wid else { continue }
        var m: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXMinimizedAttribute as CFString, &m)
        return "min=\((m as? NSNumber)?.boolValue.description ?? "?")"
    }
    return "ax-notfound"
}

func screenName(_ r: CGRect) -> String {
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let appKit = CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
    func area(_ x: CGRect) -> CGFloat { x.isNull ? 0 : x.width * x.height }
    return NSScreen.screens.max { area($0.frame.intersection(appKit)) < area($1.frame.intersection(appKit)) }?
        .localizedName ?? "?"
}

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "8") ?? 8
let start = Date()
func elapsed() -> String { String(format: "%.3f", Date().timeIntervalSince(start)) }

print("Monitores:", NSScreen.screens.map(\.localizedName), "Accesibilidad:", AXIsProcessTrusted())
var last: [CGWindowID: String] = [:]
while Date().timeIntervalSince(start) < seconds {
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                           kCGNullWindowID) as? [[String: Any]]) ?? []
    var seen = Set<CGWindowID>()
    for info in list {
        guard (info[kCGWindowLayer as String] as? Int) == 0,
              let wid = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { continue }
        let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
        if alpha <= 0 || bounds.width < 40 || bounds.height < 40 { continue }   // mismos filtros que la app
        seen.insert(wid)
        let screen = screenName(bounds)
        let key = "\(screen)|\(bounds.size)"
        if last[wid] != key {
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            print(elapsed(), wid, owner, screen, bounds, axMinimized(pid: pid, wid: wid))
            last[wid] = key
        }
    }
    for wid in last.keys where !seen.contains(wid) {
        print(elapsed(), wid, "DESAPARECE")
        last[wid] = nil
    }
    usleep(20_000)
}
