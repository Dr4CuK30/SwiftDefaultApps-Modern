// Draws the app icon (1024×1024 PNG) and builds Resources/AppIcon.icns.
// Usage: swift Scripts/make-icon.swift   (run from the repository root)
//
// Motif: a list of apps where one row is picked as the default (green check),
// on a blue macOS-style rounded square.

import AppKit

let size: CGFloat = 1024
let fileManager = FileManager.default

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background: macOS icon grid (824 pt square, 100 pt margin) with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0x2D5BE3).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x5AA2FF), ending: color(0x2440C8))!.draw(in: tilePath, angle: -90)

    // Three list rows; the middle one is the selected default.
    let rowWidth: CGFloat = 600, rowHeight: CGFloat = 150, gap: CGFloat = 40
    let rowX = (size - rowWidth) / 2
    let firstY = (size - (rowHeight * 3 + gap * 2)) / 2
    let appColors: [UInt32] = [0xFF9F0A, 0xAF52DE, 0x30B0C7] // bottom, middle, top

    for index in 0..<3 {
        let selected = index == 1
        let row = CGRect(x: rowX, y: firstY + CGFloat(index) * (rowHeight + gap), width: rowWidth, height: rowHeight)

        NSGraphicsContext.saveGraphicsState()
        if selected {
            let rowShadow = NSShadow()
            rowShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            rowShadow.shadowOffset = NSSize(width: 0, height: -8)
            rowShadow.shadowBlurRadius = 20
            rowShadow.set()
        }
        (selected ? NSColor.white : NSColor.white.withAlphaComponent(0.22)).setFill()
        roundedRect(row, 38).fill()
        NSGraphicsContext.restoreGraphicsState()

        // App "icon" inside the row.
        let appSide: CGFloat = 96
        let app = CGRect(x: row.minX + 27, y: row.midY - appSide / 2, width: appSide, height: appSide)
        NSGradient(starting: color(appColors[index]), ending: color(appColors[index]).blended(withFraction: 0.25, of: .black)!)!
            .draw(in: roundedRect(app, 24), angle: -90)

        // Two "text" lines.
        let textX = app.maxX + 28
        let lineColor = selected ? color(0x1C2B4A, 0.85) : NSColor.white.withAlphaComponent(0.75)
        let subColor = selected ? color(0x1C2B4A, 0.35) : NSColor.white.withAlphaComponent(0.4)
        lineColor.setFill()
        roundedRect(CGRect(x: textX, y: row.midY + 6, width: 230, height: 26), 13).fill()
        subColor.setFill()
        roundedRect(CGRect(x: textX, y: row.midY - 34, width: 150, height: 22), 11).fill()

        // Green check on the selected row.
        if selected {
            let radius: CGFloat = 46
            let center = CGPoint(x: row.maxX - 30 - radius, y: row.midY)
            color(0x34C759).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            let check = NSBezierPath()
            check.move(to: CGPoint(x: center.x - 21, y: center.y + 1))
            check.line(to: CGPoint(x: center.x - 6, y: center.y - 15))
            check.line(to: CGPoint(x: center.x + 22, y: center.y + 17))
            check.lineWidth = 13
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func run(_ tool: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try! process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "\(tool) failed")
}

let resources = URL(fileURLWithPath: "Resources", isDirectory: true)
try! fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
let master = resources.appendingPathComponent("AppIcon.png")
try! drawIcon().representation(using: .png, properties: [:])!.write(to: master)

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
try? fileManager.removeItem(at: iconset)
print("Wrote \(master.path) and Resources/AppIcon.icns")
