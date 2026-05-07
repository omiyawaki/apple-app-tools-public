import AppKit
import Foundation

public enum ReviewSheetWriter {
    public static func write(iconset: URL, output: URL) throws {
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let width = 1540
        let height = 1180
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw BuildError("Could not allocate review sheet bitmap.")
        }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        color(245, 247, 246).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        color(28, 31, 35).setFill()
        NSRect(x: 0, y: 0, width: width, height: 570).fill()

        let entries: [(Int, String)] = [
            (512, "icon_512x512.png"),
            (256, "icon_256x256.png"),
            (128, "icon_128x128.png"),
            (64, "icon_32x32@2x.png"),
            (32, "icon_32x32.png")
        ]

        var x: CGFloat = 54
        for (size, file) in entries {
            let image = try iconImage(iconset: iconset, file: file)
            image.draw(
                in: NSRect(x: x, y: 626, width: CGFloat(size), height: CGFloat(size)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            image.draw(
                in: NSRect(x: x, y: 36, width: CGFloat(size), height: CGFloat(size)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            x += CGFloat(size) + 54
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw BuildError("Could not encode review sheet PNG.")
        }
        try png.write(to: output)
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    private static func iconImage(iconset: URL, file: String) throws -> NSImage {
        let url = iconset.appendingPathComponent(file)
        guard let image = NSImage(contentsOf: url) else {
            throw BuildError("Missing review icon image: \(url.path)")
        }
        return image
    }
}
