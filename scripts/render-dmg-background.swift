import AppKit
import Foundation

/// Draws the FlowMod disk-image background at 1x so Finder maps it onto the
/// window without scaling. Icon positions are set separately; this image only
/// supplies the arrow and the instruction between them.
///
/// Usage: swift scripts/render-dmg-background.swift <output.png> <width> <height>

guard CommandLine.arguments.count == 4,
      let width = Int(CommandLine.arguments[2]),
      let height = Int(CommandLine.arguments[3]),
      width > 0, height > 0 else {
    fputs("Usage: render-dmg-background.swift <output.png> <width> <height>\n", stderr)
    exit(1)
}

let pointSize = NSSize(width: width, height: height)
let image = NSImage(size: pointSize, flipped: false) { _ in
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(origin: .zero, size: pointSize).fill()

    // Finder icon positions are measured from the top of the window.
    // The app and Applications icons sit at y = 175.
    let iconCenterFromTop: CGFloat = 175
    let arrowY = CGFloat(height) - iconCenterFromTop
    let arrowColor = NSColor(calibratedWhite: 0.38, alpha: 1)

    // One filled shape, so the head and shaft share a center line.
    let shaftHalf: CGFloat = 7
    let headHalf: CGFloat = 15
    let tailX: CGFloat = 252
    let headBaseX: CGFloat = 378
    let tipX: CGFloat = 408
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: tailX + shaftHalf, y: arrowY + shaftHalf))
    arrow.line(to: NSPoint(x: headBaseX, y: arrowY + shaftHalf))
    arrow.line(to: NSPoint(x: headBaseX, y: arrowY + headHalf))
    arrow.line(to: NSPoint(x: tipX, y: arrowY))
    arrow.line(to: NSPoint(x: headBaseX, y: arrowY - headHalf))
    arrow.line(to: NSPoint(x: headBaseX, y: arrowY - shaftHalf))
    arrow.line(to: NSPoint(x: tailX + shaftHalf, y: arrowY - shaftHalf))
    arrow.appendArc(
        withCenter: NSPoint(x: tailX + shaftHalf, y: arrowY),
        radius: shaftHalf,
        startAngle: 270,
        endAngle: 90,
        clockwise: true
    )
    arrow.close()
    arrowColor.setFill()
    arrow.fill()

    let caption = "Drag FlowMod to Applications" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.32, alpha: 1)
    ]
    let captionSize = caption.size(withAttributes: attributes)
    let captionTop: CGFloat = 310
    let captionRect = NSRect(
        x: (CGFloat(width) - captionSize.width) / 2,
        y: CGFloat(height) - captionTop - captionSize.height,
        width: captionSize.width,
        height: captionSize.height
    )
    caption.draw(in: captionRect, withAttributes: attributes)
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the disk-image background.\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fputs("Could not write the disk-image background: \(error.localizedDescription)\n", stderr)
    exit(1)
}
