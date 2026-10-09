import AppKit
import Foundation

/// Writes the disk-image icon: FlowMod.app's icon as Finder draws it.
///
/// The asset catalog artwork is square. macOS clips it to the app shape only
/// when it draws an application bundle, so this bakes that shape in.
/// Sizes stop at 256 px, like the app's own AppIcon.icns, to keep the file small.
///
/// Usage: swift scripts/render-dmg-icon.swift <FlowMod.app> <output.icns>

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: render-dmg-icon.swift <FlowMod.app> <output.icns>\n", stderr)
    exit(1)
}

let appPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard appPath.hasSuffix(".app"), FileManager.default.fileExists(atPath: appPath) else {
    fputs("Not an application bundle: \(appPath)\n", stderr)
    exit(1)
}

let source = NSWorkspace.shared.icon(forFile: appPath)
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256)
]

let iconset = NSTemporaryDirectory() + "flowmod-\(UUID().uuidString).iconset"
defer { try? FileManager.default.removeItem(atPath: iconset) }

do {
    try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    for (name, pixels) in sizes {
        let image = NSImage(size: NSSize(width: pixels, height: pixels), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Could not encode \(name).\n", stderr)
            exit(1)
        }
        try png.write(to: URL(fileURLWithPath: iconset + "/" + name))
    }
} catch {
    fputs("Could not write the iconset: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", outputPath]
do {
    try iconutil.run()
} catch {
    fputs("Could not run iconutil: \(error.localizedDescription)\n", stderr)
    exit(1)
}
iconutil.waitUntilExit()
if iconutil.terminationStatus != 0 {
    fputs("iconutil could not write \(outputPath)\n", stderr)
    exit(1)
}
