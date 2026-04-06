import Foundation
import CoreGraphics

// Usage: scroll-at <x> <y> <lines>
// Sends a scroll wheel event at the given coordinates.
// Negative lines = scroll down, positive = scroll up.

guard CommandLine.arguments.count == 4,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]),
      let lines = Int32(CommandLine.arguments[3]) else {
    fputs("Usage: scroll-at <x> <y> <lines>\n", stderr)
    exit(1)
}

let point = CGPoint(x: x, y: y)
if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) {
    event.location = point
    event.post(tap: .cghidEventTap)
}
