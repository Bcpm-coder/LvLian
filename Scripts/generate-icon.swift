import AppKit
import ImageIO
import UniformTypeIdentifiers

// Draw the app's original vector mark at icon resolution; no external assets.
let size = 1024
let bitmapContext = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 0.93, green: 0.97, blue: 0.94, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
NSColor(srgbRed: 0.06, green: 0.43, blue: 0.38, alpha: 1).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 174, y: 174, width: 676, height: 676))
ring.lineWidth = 35
ring.stroke()
let breath = NSBezierPath()
breath.move(to: NSPoint(x: 294, y: 432))
breath.curve(to: NSPoint(x: 512, y: 665), controlPoint1: NSPoint(x: 415, y: 432), controlPoint2: NSPoint(x: 390, y: 665))
breath.curve(to: NSPoint(x: 730, y: 432), controlPoint1: NSPoint(x: 634, y: 665), controlPoint2: NSPoint(x: 610, y: 432))
breath.lineWidth = 48
breath.lineCapStyle = .round
breath.stroke()
let lower = NSBezierPath()
lower.move(to: NSPoint(x: 375, y: 365))
lower.curve(to: NSPoint(x: 649, y: 365), controlPoint1: NSPoint(x: 450, y: 315), controlPoint2: NSPoint(x: 574, y: 315))
lower.lineWidth = 32
lower.lineCapStyle = .round
lower.stroke()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmapContext.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
