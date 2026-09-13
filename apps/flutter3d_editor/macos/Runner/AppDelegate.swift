import Cocoa
import FlutterMacOS

/// `rp-04`: the half of file association Dart cannot reach on its own — macOS
/// calls this, not the Flutter engine, when somebody double-clicks a
/// `.f3drun` in Finder or drags one onto the dock icon. Declared as owning
/// that type in `Info.plist`'s `CFBundleDocumentTypes`.
@main
class AppDelegate: FlutterAppDelegate {
  private static let channelName = "dev.pleion.flutter3d_editor/openRun"
  private var channel: FlutterMethodChannel?

  /// A path macOS handed over before `channel` existed to send it through —
  /// launched by double-click, which calls `application(_:open:)` before
  /// `applicationDidFinishLaunching` has stood up a `FlutterViewController`.
  private var pendingPaths: [String] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: AppDelegate.channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    self.channel = channel
    for path in pendingPaths {
      channel.invokeMethod("openRun", arguments: path)
    }
    pendingPaths.removeAll()
  }

  /// The modern replacement for `application(_:openFile:)` — one call for
  /// both "opened by double-click at launch" and "dropped on the dock icon
  /// while already running". Only `.f3drun` reaches this app at all, per
  /// `Info.plist`'s own declared type, so no extension check here.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let path = url.path
      if let channel = channel {
        channel.invokeMethod("openRun", arguments: path)
      } else {
        pendingPaths.append(path)
      }
    }
  }
}
