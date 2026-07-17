#!/usr/bin/swift
// Presses the first AXButton (or any element) whose AXIdentifier or
// AXDescription contains `match`, via a direct AXUIElementPerformAction -
// sidesteps the System Events AppleScript bridge for the same reason
// axprobe.swift replaces it for reads (fact 10, M8 prep).
//
// Usage: swift scripts/axclick.swift <bundle-name-or-pid> <match-substring>

import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: axclick.swift <app-name-or-pid> <match>\n".data(using: .utf8)!)
    exit(1)
}

let target = CommandLine.arguments[1]
let match = CommandLine.arguments[2]

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

func find(_ element: AXUIElement, match: String) -> AXUIElement? {
    let identifier = attribute(element, "AXIdentifier") ?? ""
    let description = attribute(element, kAXDescriptionAttribute as String) ?? ""
    let title = attribute(element, kAXTitleAttribute as String) ?? ""
    if identifier.contains(match) || description.contains(match) || title.contains(match) {
        return element
    }
    for child in children(element) {
        if let found = find(child, match: match) {
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
    if let found = find(window, match: match) {
        let result = AXUIElementPerformAction(found, kAXPressAction as CFString)
        if result == .success {
            print("pressed element matching '\(match)'")
            exit(0)
        } else {
            FileHandle.standardError.write("found element but press failed: \(result.rawValue)\n".data(using: .utf8)!)
            exit(3)
        }
    }
}
FileHandle.standardError.write("no element matching '\(match)' found\n".data(using: .utf8)!)
exit(4)
