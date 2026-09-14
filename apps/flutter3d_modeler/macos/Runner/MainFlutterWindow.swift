import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    if let requested = MainFlutterWindow.requestedSize(from: CommandLine.arguments) {
      windowFrame = NSRect(origin: windowFrame.origin, size: requested)
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// `tool/tutorial/shoot.dart`'s own door: a `--window=WIDTHxHEIGHT` launch
  /// argument (`flutter run -d macos -a --window=1440x900`, matching
  /// `--dart-entrypoint-args`, which the macOS embedder forwards as plain
  /// process arguments) picks the size a driven screenshot is taken at, so
  /// every case lands at the same pixel dimensions regardless of whatever
  /// window a developer happened to leave open.
  ///
  /// Returns nil — leaving `awakeFromNib`'s own `windowFrame` exactly the
  /// size the xib gave it — for every launch that never passes the
  /// argument, for one spelled wrong, or for one whose width or height is
  /// not a positive number. Zero behaviour change is the point: this only
  /// ever narrows what a normal `flutter run`/double-click launch already
  /// did.
  static func requestedSize(from arguments: [String]) -> NSSize? {
    let prefix = "--window="
    for argument in arguments {
      guard argument.hasPrefix(prefix) else { continue }
      let value = argument.dropFirst(prefix.count)
      let parts = value.split(separator: "x", maxSplits: 1)
      guard parts.count == 2,
        let width = Double(parts[0]),
        let height = Double(parts[1]),
        width > 0, height > 0
      else { return nil }
      return NSSize(width: width, height: height)
    }
    return nil
  }
}
