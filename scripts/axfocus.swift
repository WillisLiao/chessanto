#!/usr/bin/swift
// Sets AXFocused=true on the first AXTextField (or matching role) whose
// identifier/description/title/value contains `match` - use this before an
// osascript `keystroke` so real keystrokes land in the right field (direct
// AXValue writes don't drive SwiftUI's text binding the way real key events
// do).
//
// Usage: swift scripts/axfocus.swift <app-name-or-pid> <match-substring> [role]

import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: axfocus.swift <app-name-or-pid> <match> [role]\n".data(using: .utf8)!)
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
    if let found = find(window, role: role, match: match) {
        let result = AXUIElementSetAttributeValue(found, kAXFocusedAttribute as CFString, true as CFTypeRef)
        if result == .success {
            print("focused element matching '\(match)'")
            exit(0)
        } else {
            FileHandle.standardError.write("found element but focus failed: \(result.rawValue)\n".data(using: .utf8)!)
            exit(3)
        }
    }
}
FileHandle.standardError.write("no element matching '\(match)' found\n".data(using: .utf8)!)
exit(4)
