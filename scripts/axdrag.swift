#!/usr/bin/swift
// Drags with a real left mouse button from the centre of one accessibility
// element to the centre of another, matched by AXIdentifier substring.
//
// Drag is the one board interaction no unit test can prove and no
// AXPress can simulate, so QA needs real CGEvents - the same reason
// scripts/axclickat.swift exists for clicks.
//
// Usage: swift scripts/axdrag.swift <app-name> <from-identifier> <to-identifier>

import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write("usage: axdrag.swift <app> <from-id> <to-id>\n".data(using: .utf8)!)
    exit(1)
}
let appName = CommandLine.arguments[1]
let fromMatch = CommandLine.arguments[2]
let toMatch = CommandLine.arguments[3]

guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    FileHandle.standardError.write("app not running\n".data(using: .utf8)!)
    exit(1)
}
let app = AXUIElementCreateApplication(runningApp.processIdentifier)

func children(_ e: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success,
        let a = v as? [AXUIElement] else { return [] }
    return a
}
func identifier(_ e: AXUIElement) -> String {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, "AXIdentifier" as CFString, &v)
    return (v as? String) ?? ""
}
func centre(_ e: AXUIElement) -> CGPoint? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &posValue) == .success,
        AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeValue) == .success
    else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
}
func find(_ e: AXUIElement, _ match: String) -> AXUIElement? {
    if identifier(e).contains(match) { return e }
    for c in children(e) {
        if let f = find(c, match) { return f }
    }
    return nil
}

guard let fromElement = find(app, fromMatch), let fromPoint = centre(fromElement) else {
    FileHandle.standardError.write("from element not found\n".data(using: .utf8)!)
    exit(1)
}
guard let toElement = find(app, toMatch), let toPoint = centre(toElement) else {
    FileHandle.standardError.write("to element not found\n".data(using: .utf8)!)
    exit(1)
}

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
}

post(.mouseMoved, fromPoint)
post(.leftMouseDown, fromPoint)
// Several intermediate steps: the board only treats a press as a drag once
// it has travelled past its own threshold.
for step in 1...8 {
    let t = CGFloat(step) / 8
    post(.leftMouseDragged, CGPoint(x: fromPoint.x + (toPoint.x - fromPoint.x) * t,
                                    y: fromPoint.y + (toPoint.y - fromPoint.y) * t))
}
post(.leftMouseUp, toPoint)
print("dragged \(fromMatch) -> \(toMatch)  (\(Int(fromPoint.x)),\(Int(fromPoint.y)) -> \(Int(toPoint.x)),\(Int(toPoint.y)))")
