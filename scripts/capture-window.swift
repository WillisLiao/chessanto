#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        "usage: capture-window.swift <application-name> <output.png>\n".data(using: .utf8)!
    )
    exit(2)
}

let applicationName = CommandLine.arguments[1]
let outputPath = URL(fileURLWithPath: CommandLine.arguments[2]).standardized.path

guard let application = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == applicationName
}) else {
    FileHandle.standardError.write(
        "application '\(applicationName)' is not running\n".data(using: .utf8)!
    )
    exit(1)
}

guard application.activate() else {
    FileHandle.standardError.write(
        "could not activate '\(applicationName)'\n".data(using: .utf8)!
    )
    exit(1)
}

RunLoop.current.run(until: Date().addingTimeInterval(0.4))

guard
    let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]]
else {
    FileHandle.standardError.write("could not read the window list\n".data(using: .utf8)!)
    exit(1)
}

let candidates = windowInfo.compactMap { info -> (id: CGWindowID, area: CGFloat, title: String)? in
    guard
        info[kCGWindowOwnerPID as String] as? pid_t == application.processIdentifier,
        info[kCGWindowLayer as String] as? Int == 0,
        let id = info[kCGWindowNumber as String] as? CGWindowID,
        let boundsValue = info[kCGWindowBounds as String],
        let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary),
        bounds.width >= 300,
        bounds.height >= 300
    else {
        return nil
    }

    return (
        id: id,
        area: bounds.width * bounds.height,
        title: info[kCGWindowName as String] as? String ?? ""
    )
}

guard let window = candidates.max(by: { $0.area < $1.area }) else {
    FileHandle.standardError.write(
        "no capturable '\(applicationName)' window was found\n".data(using: .utf8)!
    )
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l\(window.id)", outputPath]
try capture.run()
capture.waitUntilExit()

guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: outputPath) else {
    FileHandle.standardError.write("window capture failed\n".data(using: .utf8)!)
    exit(1)
}

print("captured \(applicationName) window \(window.id) \(window.title) -> \(outputPath)")
