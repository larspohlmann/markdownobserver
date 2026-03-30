import Foundation

func abbreviatePathWithTilde(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home {
        return "~"
    } else if path.hasPrefix(home + "/") {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
