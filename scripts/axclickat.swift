#!/usr/bin/swift
// Finds the first element (role-filtered) matching `match` and posts a real
// CGEvent mouse click at its screen-space center - for text fields, where a
// synthetic AXPress/AXFocused set doesn't reliably hand SwiftUI real
// keyboard focus the way an actual click does.
//
// Usage: swift scripts/axclickat.swift <app-name-or-pid> <match-substring> [role]

import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: axclickat.swift <app-name-or-pid> <match> [role]\n".data(using: .utf8)!)
    exit(1)
}

let target = CommandLine.arguments[1]
let match = CommandLine.arguments[2]
let role = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : (kAXTextFieldRole as String)

func findPID(_ target: String) -> pid_t? {
    if let pid = pid_t(target) { return pid }
    return NSWorkspace.shared.runningApplications
        .first { $0.localizedName == target }?
        .processIdentifier
}

func attribute(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
        let array = value as? [AXUIElement]
    else { return [] }
    return array
}

func frame(_ element: AXUIElement) -> CGRect? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
    else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetType(posValue as! AXValue) == .cgPoint, AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
        AXValueGetType(sizeValue as! AXValue) == .cgSize, AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else { return nil }
    return CGRect(origin: point, size: size)
}

func find(_ element: AXUIElement, role: String, match: String) -> AXUIElement? {
    let elementRole = attribute(element, kAXRoleAttribute as String) ?? ""
    if elementRole == role {
        let identifier = attribute(element, "AXIdentifier") ?? ""
        let description = attribute(element, kAXDescriptionAttribute as String) ?? ""
        let title = attribute(element, kAXTitleAttribute as String) ?? ""
        let value = attribute(element, kAXValueAttribute as String) ?? ""
        if match.isEmpty || identifier.contains(match) || description.contains(match) || title.contains(match) || value.contains(match) {
            return element
        }
    }
    for child in children(element) {
        if let found = find(child, role: role, match: match) {
            return found
        }
    }
    return nil
}

guard let pid = findPID(target) else {
    FileHandle.standardError.write("no running app matching '\(target)'\n".data(using: .utf8)!)
    exit(1)
}

let app = AXUIElementCreateApplication(pid)
var windowsValue: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
    let windows = windowsValue as? [AXUIElement], !windows.isEmpty
else {
    FileHandle.standardError.write("app pid \(pid) has zero windows\n".data(using: .utf8)!)
    exit(2)
}

for window in windows {
    guard let found = find(window, role: role, match: match), let rect = frame(found) else { continue }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(50_000)
    up?.post(tap: .cghidEventTap)
    print("clicked at \(center) for element matching '\(match)'")
    exit(0)
}
FileHandle.standardError.write("no element matching '\(match)' found\n".data(using: .utf8)!)
exit(4)
