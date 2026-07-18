#!/usr/bin/swift
// Dumps role/identifier/AXDescription for a running app's window tree via
// the raw Accessibility API (AXUIElementCopyAttributeValue), not the
// System Events AppleScript bridge.
//
// M8 prep found the bridge (`name of`/`description of` in `osascript`)
// cannot read the `AXDescription`s SwiftUI actually sets, while this direct
// API call can - chat rows, report key moments, and lines-panel adopt
// buttons all expose full text this way, which was the whole M5/M7 "AX
// gap" that never needed an app-side fix.
//
// Usage: swift scripts/axprobe.swift <bundle-name-or-pid> [filter-substring]
//   swift scripts/axprobe.swift Chessanto
//   swift scripts/axprobe.swift Chessanto square-e4
//
// Requires the caller (Terminal/whatever runs this) to have Accessibility
// permission for the target app; no Screen Recording permission needed.

import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: axprobe.swift <app-name-or-pid> [filter]\n".data(using: .utf8)!)
    exit(1)
}

let target = CommandLine.arguments[1]
let filter = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : nil

func findPID(_ target: String) -> pid_t? {
    if let pid = pid_t(target) { return pid }
    return NSWorkspace.shared.runningApplications
        .first { $0.localizedName == target }?
        .processIdentifier
}

func attribute(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    if let s = value as? String { return s }
    return nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
        let array = value as? [AXUIElement]
    else { return [] }
    return array
}

func valueAttribute(_ element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
    if let s = value as? String { return s }
    return nil
}

func sizeAttribute(_ element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success else { return nil }
    var size = CGSize.zero
    guard AXValueGetType(value as! AXValue) == .cgSize, AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

func walk(_ element: AXUIElement, depth: Int, filter: String?) {
    let role = attribute(element, kAXRoleAttribute as String) ?? ""
    let identifier = attribute(element, "AXIdentifier") ?? ""
    let description = attribute(element, kAXDescriptionAttribute as String) ?? ""
    let title = attribute(element, kAXTitleAttribute as String) ?? ""
    let value = valueAttribute(element) ?? ""
    var enabledValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue)
    let enabled = (enabledValue as? Bool).map(String.init) ?? "?"
    let size = sizeAttribute(element).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"

    let line = "\(String(repeating: "  ", count: depth))[\(role)] id=\(identifier) title=\(title) desc=\(description) value=\(value) enabled=\(enabled) size=\(size)"
    if let filter, !identifier.contains(filter), !description.contains(filter), !title.contains(filter), !value.contains(filter) {
        // still recurse into children, just don't print this node
    } else {
        print(line)
    }
    for child in children(element) {
        walk(child, depth: depth + 1, filter: filter)
    }
}

guard let pid = findPID(target) else {
    FileHandle.standardError.write("no running app matching '\(target)'\n".data(using: .utf8)!)
    exit(1)
}

let app = AXUIElementCreateApplication(pid)
guard let windows = { () -> [AXUIElement]? in
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
    return value as? [AXUIElement]
}(), !windows.isEmpty else {
    FileHandle.standardError.write("app pid \(pid) has zero windows\n".data(using: .utf8)!)
    exit(2)
}

for window in windows {
    walk(window, depth: 0, filter: filter)
}
