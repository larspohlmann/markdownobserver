import CoreGraphics
import Foundation

let targetName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MarkdownObserver"

guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

for w in windows {
    guard let owner = w["kCGWindowOwnerName"] as? String, owner == targetName,
          let layer = w["kCGWindowLayer"] as? Int, layer == 0,
          let id = w["kCGWindowNumber"] as? Int else { continue }
    print(id)
    exit(0)
}

exit(1)
