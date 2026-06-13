#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first
    ?? "Sources/MacSVNWorkbench/Resources/MacTortoiseSVNIcon.png"
let outputURL = URL(fileURLWithPath: outputPath)
let canvasSize = NSSize(width: 1024, height: 1024)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func oval(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: width, height: height))
}

func drawLine(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: start)
    path.line(to: end)
    color.setStroke()
    path.stroke()
}

func turtleAppleBodyPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 518, y: 176))
    path.curve(
        to: NSPoint(x: 294, y: 246),
        controlPoint1: NSPoint(x: 432, y: 154),
        controlPoint2: NSPoint(x: 338, y: 176)
    )
    path.curve(
        to: NSPoint(x: 194, y: 500),
        controlPoint1: NSPoint(x: 236, y: 338),
        controlPoint2: NSPoint(x: 194, y: 410)
    )
    path.curve(
        to: NSPoint(x: 284, y: 762),
        controlPoint1: NSPoint(x: 194, y: 624),
        controlPoint2: NSPoint(x: 228, y: 706)
    )
    path.curve(
        to: NSPoint(x: 436, y: 806),
        controlPoint1: NSPoint(x: 330, y: 808),
        controlPoint2: NSPoint(x: 386, y: 820)
    )
    path.curve(
        to: NSPoint(x: 516, y: 780),
        controlPoint1: NSPoint(x: 466, y: 798),
        controlPoint2: NSPoint(x: 492, y: 786)
    )
    path.curve(
        to: NSPoint(x: 626, y: 806),
        controlPoint1: NSPoint(x: 548, y: 796),
        controlPoint2: NSPoint(x: 586, y: 816)
    )
    path.curve(
        to: NSPoint(x: 774, y: 688),
        controlPoint1: NSPoint(x: 690, y: 790),
        controlPoint2: NSPoint(x: 738, y: 744)
    )
    path.curve(
        to: NSPoint(x: 830, y: 486),
        controlPoint1: NSPoint(x: 812, y: 628),
        controlPoint2: NSPoint(x: 830, y: 558)
    )
    path.curve(
        to: NSPoint(x: 750, y: 270),
        controlPoint1: NSPoint(x: 830, y: 382),
        controlPoint2: NSPoint(x: 802, y: 310)
    )
    path.curve(
        to: NSPoint(x: 600, y: 176),
        controlPoint1: NSPoint(x: 708, y: 218),
        controlPoint2: NSPoint(x: 650, y: 188)
    )
    path.curve(
        to: NSPoint(x: 518, y: 176),
        controlPoint1: NSPoint(x: 570, y: 168),
        controlPoint2: NSPoint(x: 544, y: 168)
    )
    path.close()
    return path
}

func bitePath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 780, y: 618))
    path.curve(
        to: NSPoint(x: 896, y: 548),
        controlPoint1: NSPoint(x: 830, y: 620),
        controlPoint2: NSPoint(x: 874, y: 594)
    )
    path.curve(
        to: NSPoint(x: 802, y: 454),
        controlPoint1: NSPoint(x: 880, y: 498),
        controlPoint2: NSPoint(x: 842, y: 468)
    )
    path.curve(
        to: NSPoint(x: 750, y: 520),
        controlPoint1: NSPoint(x: 758, y: 442),
        controlPoint2: NSPoint(x: 730, y: 478)
    )
    path.curve(
        to: NSPoint(x: 780, y: 618),
        controlPoint1: NSPoint(x: 766, y: 554),
        controlPoint2: NSPoint(x: 778, y: 584)
    )
    path.close()
    return path
}

func leafPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 584, y: 820))
    path.curve(
        to: NSPoint(x: 760, y: 908),
        controlPoint1: NSPoint(x: 620, y: 900),
        controlPoint2: NSPoint(x: 692, y: 928)
    )
    path.curve(
        to: NSPoint(x: 642, y: 770),
        controlPoint1: NSPoint(x: 748, y: 826),
        controlPoint2: NSPoint(x: 704, y: 782)
    )
    path.curve(
        to: NSPoint(x: 584, y: 820),
        controlPoint1: NSPoint(x: 620, y: 766),
        controlPoint2: NSPoint(x: 598, y: 786)
    )
    path.close()
    return path
}

func shellScutePath(points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    return path
}

let image = NSImage(size: canvasSize)
image.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let shadow = NSShadow()
shadow.shadowBlurRadius = 48
shadow.shadowOffset = NSSize(width: 0, height: -24)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)

let bodyPath = turtleAppleBodyPath()
let bite = bitePath()
bodyPath.append(bite.reversed)

NSGraphicsContext.saveGraphicsState()
shadow.set()
NSGradient(colors: [
    color(43, 180, 104),
    color(50, 142, 82),
    color(20, 96, 66),
])?.draw(in: bodyPath, angle: 128)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.26),
    NSColor.white.withAlphaComponent(0.02),
])?.draw(in: oval(252, 548, 438, 236), angle: 104)
NSGraphicsContext.restoreGraphicsState()

let shellPath = NSBezierPath()
shellPath.appendOval(in: NSRect(x: 288, y: 248, width: 468, height: 438))
NSGradient(colors: [
    color(105, 205, 122),
    color(38, 138, 78),
    color(21, 96, 71),
])?.draw(in: shellPath, angle: 116)

color(9, 74, 60, 0.42).setStroke()
shellPath.lineWidth = 14
shellPath.stroke()

let shellLines = [
    (NSPoint(x: 522, y: 268), NSPoint(x: 522, y: 676)),
    (NSPoint(x: 332, y: 426), NSPoint(x: 710, y: 426)),
    (NSPoint(x: 382, y: 566), NSPoint(x: 664, y: 312)),
    (NSPoint(x: 374, y: 310), NSPoint(x: 676, y: 578)),
]
for (start, end) in shellLines {
    drawLine(from: start, to: end, width: 12, color: color(222, 248, 202, 0.46))
}

let centerScute = shellScutePath(points: [
    NSPoint(x: 522, y: 610),
    NSPoint(x: 632, y: 520),
    NSPoint(x: 602, y: 384),
    NSPoint(x: 522, y: 316),
    NSPoint(x: 442, y: 384),
    NSPoint(x: 410, y: 520),
])
color(190, 235, 121, 0.22).setFill()
centerScute.fill()
color(232, 255, 207, 0.55).setStroke()
centerScute.lineWidth = 10
centerScute.stroke()

let headPath = oval(706, 354, 176, 150)
NSGradient(colors: [
    color(121, 218, 118),
    color(42, 142, 78),
])?.draw(in: headPath, angle: 132)
color(13, 83, 64, 0.34).setStroke()
headPath.lineWidth = 10
headPath.stroke()

let eye = oval(808, 428, 22, 22)
color(18, 51, 43).setFill()
eye.fill()
oval(815, 438, 7, 7).fill()

let smile = NSBezierPath()
smile.lineWidth = 6
smile.lineCapStyle = .round
smile.move(to: NSPoint(x: 806, y: 394))
smile.curve(
    to: NSPoint(x: 842, y: 396),
    controlPoint1: NSPoint(x: 818, y: 382),
    controlPoint2: NSPoint(x: 834, y: 384)
)
color(18, 65, 52, 0.72).setStroke()
smile.stroke()

let limbs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (246, 452, 96, 62, -18),
    (320, 168, 112, 68, -24),
    (626, 166, 108, 66, 24),
    (238, 274, 96, 60, 20),
]
for (x, y, width, height, rotation) in limbs {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x + width / 2, yBy: y + height / 2)
    transform.rotate(byDegrees: rotation)
    transform.translateX(by: -(x + width / 2), yBy: -(y + height / 2))
    transform.concat()
    let limb = oval(x, y, width, height)
    NSGradient(colors: [color(118, 213, 111), color(35, 134, 76)])?.draw(in: limb, angle: 110)
    color(12, 80, 58, 0.24).setStroke()
    limb.lineWidth = 8
    limb.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

let tail = NSBezierPath()
tail.move(to: NSPoint(x: 288, y: 338))
tail.curve(
    to: NSPoint(x: 190, y: 362),
    controlPoint1: NSPoint(x: 250, y: 316),
    controlPoint2: NSPoint(x: 214, y: 326)
)
tail.curve(
    to: NSPoint(x: 292, y: 404),
    controlPoint1: NSPoint(x: 224, y: 380),
    controlPoint2: NSPoint(x: 258, y: 394)
)
tail.close()
color(39, 142, 79).setFill()
tail.fill()
color(13, 82, 58, 0.25).setStroke()
tail.lineWidth = 8
tail.stroke()

let leaf = leafPath()
NSGradient(colors: [
    color(151, 228, 95),
    color(46, 149, 73),
])?.draw(in: leaf, angle: 118)
color(15, 93, 55, 0.28).setStroke()
leaf.lineWidth = 8
leaf.stroke()
drawLine(
    from: NSPoint(x: 624, y: 810),
    to: NSPoint(x: 724, y: 882),
    width: 7,
    color: color(230, 255, 190, 0.50)
)

let stem = NSBezierPath()
stem.lineWidth = 22
stem.lineCapStyle = .round
stem.move(to: NSPoint(x: 526, y: 784))
stem.curve(
    to: NSPoint(x: 574, y: 864),
    controlPoint1: NSPoint(x: 536, y: 812),
    controlPoint2: NSPoint(x: 550, y: 842)
)
color(96, 72, 41).setStroke()
stem.stroke()

let svnText = "svn" as NSString
let textAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 52, weight: .black),
    .foregroundColor: NSColor.white.withAlphaComponent(0.82),
    .kern: 0.4,
]
svnText.draw(at: NSPoint(x: 442, y: 456), withAttributes: textAttributes)

drawLine(
    from: NSPoint(x: 452, y: 390),
    to: NSPoint(x: 592, y: 390),
    width: 12,
    color: NSColor.white.withAlphaComponent(0.58)
)
for point in [NSPoint(x: 452, y: 390), NSPoint(x: 592, y: 390)] {
    let node = oval(point.x - 17, point.y - 17, 34, 34)
    color(205, 245, 142).setFill()
    node.fill()
    NSColor.white.withAlphaComponent(0.76).setStroke()
    node.lineWidth = 5
    node.stroke()
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not encode icon PNG.")
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
print("Generated \(outputURL.path)")
