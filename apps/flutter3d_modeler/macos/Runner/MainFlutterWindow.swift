import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    if let requested = MainFlutterWindow.requestedSize(from: ProcessInfo.processInfo.environment) {
      windowFrame = NSRect(origin: windowFrame.origin, size: requested)
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWindowChannel(flutterViewController)

    super.awakeFromNib()
  }

  /// `ux-30`: the window takes its name from the open document, and the dot
  /// in its close button from whether that document has unsaved work.
  ///
  /// **Flutter's own `Title` widget does not reach an `NSWindow`.** It sets
  /// `SystemChrome.setApplicationSwitcherDescription`, which a browser turns
  /// into a tab label and this platform ignores — so the window kept the name
  /// the xib gave it for the whole session, and three of them looked alike.
  /// `isDocumentEdited` has no cross-platform equivalent at all: it is what
  /// macOS reads to draw the dot, to warn on a Quit, and to know a window has
  /// work worth restoring.
  private func registerWindowChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "flutter3d/window",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      if let title = arguments["title"] as? String {
        self?.title = title
      }
      if let edited = arguments["edited"] as? Bool {
        self?.isDocumentEdited = edited
      }
      result(nil)
    }
  }

  /// `tool/tutorial/shoot.dart`'s own door: a `FLUTTER3D_WINDOW=WIDTHxHEIGHT`
  /// environment variable (`FLUTTER3D_WINDOW=1440x900 flutter run -d macos`)
  /// picks the size a driven screenshot is taken at, so every case lands at
  /// the same pixel dimensions regardless of whatever window a developer
  /// happened to leave open.
  ///
  /// **An environment variable, not a `--window=` launch argument — confirmed
  /// the hard way on 2026-09-15.** `flutter run -d macos -a --window=…`'s own
  /// `-a`/`--dart-entrypoint-args` hands its value to *Dart*'s own
  /// `main(List<String> args)` (`flutter run --help`'s own text says so
  /// outright: "Pass a list of arguments to the Dart entrypoint"), which
  /// `awakeFromNib` here has no way to read before the window it sizes
  /// already exists — `CommandLine.arguments` never carried it, so this
  /// window silently kept its nib-given default every real run, and a real
  /// run's own screenshots landed at whatever size that default happened to
  /// be (800×632, on the machine that found this) rather than a size wide
  /// enough for the desktop-class properties dock a screenshot usually wants
  /// to show. A plain environment variable is inherited by this process the
  /// ordinary Unix way regardless of how `flutter run` itself forwards its
  /// own command-line flags, which is what actually reaches native code here.
  ///
  /// Returns nil — leaving `awakeFromNib`'s own `windowFrame` exactly the
  /// size the xib gave it — when the variable is unset, empty, or names a
  /// width/height that is not a positive number. Zero behaviour change is
  /// the point: this only ever narrows what a normal `flutter run`/
  /// double-click launch already did.
  static func requestedSize(from environment: [String: String]) -> NSSize? {
    guard let value = environment["FLUTTER3D_WINDOW"], !value.isEmpty else {
      return nil
    }
    let parts = value.split(separator: "x", maxSplits: 1)
    guard parts.count == 2,
      let width = Double(parts[0]),
      let height = Double(parts[1]),
      width > 0, height > 0
    else { return nil }
    return NSSize(width: width, height: height)
  }
}
