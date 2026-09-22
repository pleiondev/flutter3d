#!/usr/bin/env swift
// tool/tutorial/window_id.swift
//
// Finds the window id of a running app's on-screen window, by the app's own
// process name — the id `tool/tutorial/shoot.dart` hands to
// `screencapture -l <id>` so a driven screenshot catches the right window
// even when other apps sit on top of it. `CGWindowListCopyWindowInfo`
// already does the finding; this is the few lines that turn its answer into
// one printed integer. No external dependencies, on purpose — see
// `doc/model-editor-plan.md`'s `tut-00` row.
//
// Usage:
//
//     swift tool/tutorial/window_id.swift <processName>
//
// Prints the window id (an unsigned integer, `CGWindowID`'s own width) to
// stdout and exits 0 on a match; prints a one-line reason to stderr and
// exits 1 otherwise.
//
// Pure-logic self-test, run with no macOS window list involved at all — the
// part `tutorial/test/window_id_test.dart` shells out to:
//
//     swift tool/tutorial/window_id.swift --self-test

import CoreGraphics
import Foundation

/// One window, read out of `CGWindowListCopyWindowInfo`'s own dictionary
/// shape — just the three fields [bestWindowNumber] needs, so its matching
/// rule is a plain value type a test can build by hand instead of a real
/// window list only a running WindowServer can produce.
struct WindowInfo {
  let ownerName: String
  let windowNumber: Int
  /// `kCGWindowLayer`: `0` is an ordinary on-screen window; anything else is
  /// a status item, a menu, a tooltip — never the window a screenshot wants.
  let layer: Int
}

/// The window [ownerName] owns, among [windows] — the pure rule
/// `window_id.swift`'s own `main()` feeds a real window list through, and
/// `--self-test` exercises directly.
///
/// Filters to `layer == 0` (an ordinary window, never a status item or a
/// tooltip sharing the same owner) and an exact, case-sensitive match on
/// [ownerName] (`CGWindowOwnerName`, which is the process name macOS
/// already reports — `flutter3d_modeler` for this app, matching `PRODUCT_NAME`
/// in `Configs/AppInfo.xcconfig`). When more than one ordinary window
/// belongs to that owner, the smallest window number wins — window numbers
/// are assigned in creation order, so this is deterministic and, for the
/// one-window app this tool exists for, picks the only candidate there is.
func bestWindowNumber(ownerName: String, windows: [WindowInfo]) -> Int? {
  windows
    .filter { $0.ownerName == ownerName && $0.layer == 0 }
    .map { $0.windowNumber }
    .min()
}

/// Reads the live, on-screen window list through `CGWindowListCopyWindowInfo`
/// and turns each entry into a [WindowInfo] — the one function in this file
/// `--self-test` never calls, since nothing here can fake a WindowServer.
func liveWindows() -> [WindowInfo] {
  let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  guard
    let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
      as? [[String: AnyObject]]
  else { return [] }
  return raw.compactMap { entry in
    guard
      let ownerName = entry[kCGWindowOwnerName as String] as? String,
      let windowNumber = entry[kCGWindowNumber as String] as? Int,
      let layer = entry[kCGWindowLayer as String] as? Int
    else { return nil }
    return WindowInfo(ownerName: ownerName, windowNumber: windowNumber, layer: layer)
  }
}

// --------------------------------------------------------------- self-test

func runSelfTest() -> Bool {
  var failures: [String] = []

  func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if !condition() { failures.append(name) }
  }

  check(
    "matches the one ordinary window an owner has",
    bestWindowNumber(
      ownerName: "flutter3d_modeler",
      windows: [
        WindowInfo(ownerName: "flutter3d_modeler", windowNumber: 42, layer: 0)
      ]
    ) == 42
  )

  check(
    "returns nil for an owner with no window at all",
    bestWindowNumber(
      ownerName: "flutter3d_modeler",
      windows: [
        WindowInfo(ownerName: "Finder", windowNumber: 7, layer: 0)
      ]
    ) == nil
  )

  check(
    "a non-zero layer (a status item, a tooltip) is never the match",
    bestWindowNumber(
      ownerName: "flutter3d_modeler",
      windows: [
        WindowInfo(ownerName: "flutter3d_modeler", windowNumber: 9, layer: 25)
      ]
    ) == nil
  )

  check(
    "of two ordinary windows the same owner has, the smaller number wins",
    bestWindowNumber(
      ownerName: "flutter3d_modeler",
      windows: [
        WindowInfo(ownerName: "flutter3d_modeler", windowNumber: 99, layer: 0),
        WindowInfo(ownerName: "flutter3d_modeler", windowNumber: 12, layer: 0),
      ]
    ) == 12
  )

  check(
    "the owner name match is exact, not a substring",
    bestWindowNumber(
      ownerName: "flutter3d_modeler",
      windows: [
        WindowInfo(ownerName: "flutter3d_modeler_helper", windowNumber: 3, layer: 0)
      ]
    ) == nil
  )

  check(
    "an empty window list matches nothing",
    bestWindowNumber(ownerName: "flutter3d_modeler", windows: []) == nil
  )

  if failures.isEmpty {
    print("ok — \(6) self-tests")
    return true
  } else {
    for failure in failures { FileHandle.standardError.write("FAIL: \(failure)\n".data(using: .utf8)!) }
    return false
  }
}

// --------------------------------------------------------------------- CLI

let arguments = CommandLine.arguments

if arguments.count == 2 && arguments[1] == "--self-test" {
  exit(runSelfTest() ? 0 : 1)
}

guard arguments.count == 2 else {
  FileHandle.standardError.write(
    "usage: swift window_id.swift <processName>\n".data(using: .utf8)!
  )
  exit(2)
}

let processName = arguments[1]
if let windowNumber = bestWindowNumber(ownerName: processName, windows: liveWindows()) {
  print(windowNumber)
  exit(0)
} else {
  FileHandle.standardError.write(
    "no on-screen window owned by \"\(processName)\"\n".data(using: .utf8)!
  )
  exit(1)
}
