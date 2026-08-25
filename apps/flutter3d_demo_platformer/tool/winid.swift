// Prints the CGWindowID of the first on-screen window owned by a named process.
//
// A full-screen `screencapture` catches whatever happens to be on top; capturing
// by window id catches the window even when something else has focus.
import CoreGraphics
import Foundation

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "platformer"
guard
  let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
else {
  FileHandle.standardError.write("no window list\n".data(using: .utf8)!)
  exit(1)
}

for window in windows {
  guard
    let owner = window[kCGWindowOwnerName as String] as? String,
    owner.localizedCaseInsensitiveContains(wanted),
    let number = window[kCGWindowNumber as String] as? Int
  else { continue }
  let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let width = (bounds["Width"] as? Double) ?? 0
  let height = (bounds["Height"] as? Double) ?? 0
  // Skip the tiny helper windows a Flutter app also owns.
  if width < 200 || height < 200 { continue }
  print("\(number) \(Int(width))x\(Int(height))")
  exit(0)
}

FileHandle.standardError.write("no window for \(wanted)\n".data(using: .utf8)!)
exit(2)
