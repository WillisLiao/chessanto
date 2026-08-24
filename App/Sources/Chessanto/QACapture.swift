import AppKit

/// QA-only offscreen capture harness.
///
/// Screen Recording permission is denied for this agent environment, so
/// `screencapture` and ScreenCaptureKit cannot composite Chessanto's windows
/// (both verified TCC-refused). An app can still render its own view
/// hierarchies: when `CHESSANTO_QA_DIR` is set, this polls that directory for
/// trigger files named `capture-<label>` and writes `<label>.png`, compositing
/// every visible window of the app at its on-screen position. Each window is
/// rasterized with `cacheDisplay` (software path - renders SwiftUI List
/// content that `layer.render` misses on this OS) and the tiles are drawn
/// into a union canvas. Does nothing unless the variable is set.
enum QACapture {
    static func startIfEnabled() {
        guard let dir = ProcessInfo.processInfo.environment["CHESSANTO_QA_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !dir.isEmpty
        else { return }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data("ok\n".utf8).write(to: root.appendingPathComponent("qa-ready"))
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in drainTriggers(root: root) }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func drainTriggers(root: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for entry in entries.sorted() where entry == "capture" || entry.hasPrefix("capture-") {
            let label = entry == "capture" ? "shot" : String(entry.dropFirst("capture-".count))
            // Remove the trigger first so a capture failure cannot loop forever.
            try? FileManager.default.removeItem(at: root.appendingPathComponent(entry))
            // Next runloop tick so pending UI state settles before rendering.
            DispatchQueue.main.async { capture(label: label, root: root) }
        }
    }

    private static func capture(label: String, root: URL) {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width >= 200 && $0.frame.height >= 120 }
        guard !windows.isEmpty else {
            try? Data("no visible windows\n".utf8).write(to: root.appendingPathComponent("error-\(label)"))
            return
        }

        let frames = windows.map { flippedFrame(of: $0) }
        var union = CGRect.null
        for f in frames { union = union.union(f) }

        let scale = windows.first?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(union.width * scale)),
            pixelsHigh: max(1, Int(union.height * scale)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        canvas.size = CGSize(width: union.width, height: union.height)

        // Rasterize each window separately, back-to-front, then tile.
        let tiles: [(NSImage, CGRect)] = zip(windows, frames)
            .sorted(by: { $0.0.orderedIndex < $1.0.orderedIndex })
            .compactMap { window, frame in
                guard let view = rootView(of: window) else { return nil }
                guard let image = rasterizeView(view, scale: scale) else { return nil }
                return (image, frame)
            }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { return }
        NSGraphicsContext.current = context
        for (image, frame) in tiles {
            let topOffset = frame.minY - union.minY
            let drawRect = NSRect(
                x: frame.minX - union.minX,
                y: union.height - topOffset - frame.height,
                width: frame.width,
                height: frame.height
            )
            // The tile image is top-down; NSImage.draw resolves orientation.
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        guard let png = canvas.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: root.appendingPathComponent("\(label).png"))
    }

    /// Top-left-origin frame for screen-coordinate math.
    private static func flippedFrame(of window: NSWindow) -> CGRect {
        let screenHeight = window.screen?.frame.maxY ?? NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let frame = window.frame
        return CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The outermost renderable view: contentView's parent covers the
    /// title bar and toolbar, which are part of what visual QA needs to see.
    private static func rootView(of window: NSWindow) -> NSView? {
        guard var view = window.contentView else { return nil }
        while let parent = view.superview, parent.window === window, parent !== view {
            view = parent
        }
        return view
    }

    private static func rasterizeView(_ view: NSView, scale: CGFloat) -> NSImage? {
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        guard size.width > 0 && size.height > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(size.width * scale)),
            pixelsHigh: max(1, Int(size.height * scale)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size

        view.cacheDisplay(in: view.bounds, to: rep)

        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            renderLayerTree(view: view, in: context.cgContext, rootBounds: view.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let cgImage = rep.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    private static func renderLayerTree(view: NSView, in context: CGContext, rootBounds: CGRect) {
        if view.wantsLayer, let layer = view.layer {
            let rectInRoot = view.convert(view.bounds, to: view.window?.contentView?.superview ?? view)
            context.saveGState()
            context.translateBy(x: rectInRoot.minX, y: rectInRoot.minY)
            layer.render(in: context)
            context.restoreGState()
        }
        for subview in view.subviews {
            renderLayerTree(view: subview, in: context, rootBounds: rootBounds)
        }
    }
}
