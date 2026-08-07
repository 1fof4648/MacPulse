import CoreGraphics
import Foundation

// Print the window id of the on-screen MacPulse panel, for `screencapture -l`.
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for w in list {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "MacPulse",
          let num = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: Any],
          let width = b["Width"] as? Double, width > 100,
          let height = b["Height"] as? Double,
          let x = b["X"] as? Double, let y = b["Y"] as? Double else { continue }
    print("\(num) \(Int(x)) \(Int(y)) \(Int(width)) \(Int(height))")
    exit(0)
}
exit(1)
