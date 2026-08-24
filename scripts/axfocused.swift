import ApplicationServices
import AppKit

// Prints the window's focused element: role, AXIdentifier, description, value.
// Usage: swift scripts/axfocused.swift <pid>

guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: axfocused.swift <pid>\n".data(using: .utf8)!)
    exit(1)
}

func attr(_ element: AXUIElement, _ name: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return "" }
    return value as? String ?? ""
}

let app = AXUIElementCreateApplication(pid)
var winRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winRef) == .success,
    let wins = winRef as? [AXUIElement], let win = wins.first
else {
    print("no window")
    exit(0)
}

var focusedRef: CFTypeRef?
let result = AXUIElementCopyAttributeValue(win, kAXFocusedUIElementAttribute as CFString, &focusedRef)
guard result == .success, let element = focusedRef else {
    print("no focused element (AXError \(result.rawValue))")
    exit(0)
}
let el = element as! AXUIElement
print("focused role=\(attr(el, kAXRoleAttribute as String)) id=\(attr(el, "AXIdentifier")) desc=\(attr(el, kAXDescriptionAttribute as String)) value=\(attr(el, kAXValueAttribute as String))")
