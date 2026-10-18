#!/usr/bin/env swift
/// MusicPlayer 菜单栏模板图标：18pt，线宽 1.5pt，与 NotchTerm 一致。
/// 输出 TrayIconTemplate.png / @2x / @3x，黑色绘在透明底上，运行时标成 template。

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources"

let pointSize: CGFloat = 18
let strokePt: CGFloat = 1.5

func drawTray(scale: CGFloat) -> NSBitmapImageRep {
    let px = Int((pointSize * scale).rounded())
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("bitmap")
    }
    rep.size = NSSize(width: pointSize, height: pointSize)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("context")
    }
    nsCtx.imageInterpolation = .high
    nsCtx.shouldAntialias = true
    NSGraphicsContext.current = nsCtx

    let cg = nsCtx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
    NSColor.black.setStroke()
    NSColor.black.setFill()

    // 和 NotchTerm 一样留出约 2.35pt，避免比旁边的菜单栏图标更大。
    let inset: CGFloat = 2.35
    let body = NSRect(
        x: inset,
        y: inset,
        width: pointSize - inset * 2,
        height: pointSize - inset * 2
    )

    let head = NSRect(x: body.minX + 0.15, y: body.minY + 0.55, width: 6.3, height: 4.15)
    let oval = NSBezierPath(ovalIn: head)
    oval.lineWidth = strokePt
    oval.stroke()

    let stemX = head.maxX - strokePt * 0.35
    let stemTop = body.maxY - 0.15
    let stem = NSBezierPath()
    stem.lineWidth = strokePt
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: stemX, y: head.midY + 0.4))
    stem.line(to: NSPoint(x: stemX, y: stemTop))
    stem.stroke()

    let flag = NSBezierPath()
    flag.lineWidth = strokePt
    flag.lineCapStyle = .round
    flag.lineJoinStyle = .round
    flag.move(to: NSPoint(x: stemX, y: stemTop))
    flag.curve(
        to: NSPoint(x: stemX + 0.35, y: stemTop - 5.1),
        controlPoint1: NSPoint(x: body.maxX + 1.35, y: stemTop - 0.1),
        controlPoint2: NSPoint(x: body.maxX + 0.55, y: stemTop - 3.7)
    )
    flag.stroke()

    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String, dpi: Double) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = ["-s", "dpiWidth", "\(dpi)", "-s", "dpiHeight", "\(dpi)", path]
    try? proc.run()
    proc.waitUntilExit()
    print("wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (scale, name, dpi) in [
    (CGFloat(1), "TrayIconTemplate.png", 72.0),
    (CGFloat(2), "TrayIconTemplate@2x.png", 144.0),
    (CGFloat(3), "TrayIconTemplate@3x.png", 216.0),
] as [(CGFloat, String, Double)] {
    writePNG(drawTray(scale: scale), to: "\(outDir)/\(name)", dpi: dpi)
}
