#!/usr/bin/swift
// Posts real keyboard events (CGEvent) to the frontmost application.
// Modeled on axclickat.swift's CGEvent approach: synthesized key events
// land wherever keyboard focus is, so focus the target first.
//
// Usage: swift scripts/axkey.swift <keycode-or-name> [count]
//   names: up down left right space return escape tab
//   e.g.:  swift scripts/axkey.swift right 3

import CoreGraphics
import Foundation

let names: [String: UInt16] = [
    "up": 126, "down": 125, "left": 123, "right": 124,
    "space": 49, "return": 36, "escape": 53, "tab": 48,
]

guard CommandLine.arguments.count >= 2,
    let key = names[CommandLine.arguments[1]] ?? UInt16(CommandLine.arguments[1])
else {
    FileHandle.standardError.write("usage: axkey.swift <keycode-or-name> [count]\n".data(using: .utf8)!)
    exit(1)
}
let count = CommandLine.arguments.count >= 3 ? Int(CommandLine.arguments[2]) ?? 1 : 1

for _ in 0..<count {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.12)
}
print("posted \(count) x \(CommandLine.arguments[1])")
