import Cocoa
import FlutterMacOS

/// Locks the pointer in place and reports its motion as relative deltas.
///
/// The technique is the one AppKit intends for this: turning off the association
/// between the physical mouse and the on-screen cursor leaves the cursor frozen
/// while `mouseMoved` events keep arriving with their deltas intact. There is no
/// other supported way — warping the cursor back to a fixed point every frame
/// works, but it fights the window server and shows as jitter.
///
/// ## Why this object holds state
///
/// Everything below survives a Dart hot restart, because the plugin instance is
/// owned by the engine's registrar rather than by the Dart isolate. That is not
/// incidental — it is the only reason `reset` can put the cursor back. After a
/// hot restart the Dart side has forgotten that it ever captured the pointer,
/// and without native state to consult, a developer would be left with no cursor
/// and no way to ask for it back.
public class MouseCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "dev.flutter3d/mouse_capture"
  private static let eventChannelName = "dev.flutter3d/mouse_capture/events"

  /// State codes shared with the Dart side. Kept in sync by hand; there are two.
  private static let stateReleased = 0
  private static let stateCaptured = 1

  private var monitor: Any?
  private var sink: FlutterEventSink?
  private var captured = false
  private var cursorHidden = false

  /// Restored on release, because a window that reports mouse motion when the
  /// application did not ask for it is a change we made and should undo.
  private var restoreAcceptsMouseMoved: Bool?
  private weak var capturedWindow: NSWindow?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MouseCapturePlugin()

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger
    )
    eventChannel.setStreamHandler(instance)

    instance.observeFocusLoss()
  }

  // MARK: - Method channel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      capture()
      result(nil)
    case "release":
      release(notify: false)
      result(nil)
    case "reset":
      // Called by Dart on first use. Idempotent, and the whole point is that it
      // does something after a hot restart left the pointer captured.
      release(notify: false)
      result(nil)
    case "isCaptured":
      result(captured)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Event channel

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    // Losing the stream means the Dart side is gone or reloading. Holding the
    // pointer past that point strands the cursor.
    release(notify: false)
    sink = nil
    return nil
  }

  // MARK: - Capture

  private func capture() {
    guard !captured else { return }

    let window = NSApplication.shared.keyWindow
    capturedWindow = window
    if let window, !window.acceptsMouseMovedEvents {
      restoreAcceptsMouseMoved = false
      window.acceptsMouseMovedEvents = true
    } else {
      restoreAcceptsMouseMoved = nil
    }

    CGAssociateMouseAndMouseCursorPosition(0)
    if !cursorHidden {
      NSCursor.hide()
      cursorHidden = true
    }

    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    ) { [weak self] event in
      self?.emit(dx: event.deltaX, dy: event.deltaY)
      return event
    }

    captured = true
    emit(state: MouseCapturePlugin.stateCaptured)
  }

  /// - Parameter notify: whether Dart is told. False when Dart asked for the
  ///   release itself and already knows; true when the system took it away.
  private func release(notify: Bool) {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil

    if let window = capturedWindow, let restore = restoreAcceptsMouseMoved {
      window.acceptsMouseMovedEvents = restore
    }
    restoreAcceptsMouseMoved = nil
    capturedWindow = nil

    CGAssociateMouseAndMouseCursorPosition(1)

    // Hide and unhide are counted, so unhiding without having hidden would leave
    // the count negative and quietly break the next hide. The flag is what makes
    // this safe to call unconditionally.
    if cursorHidden {
      NSCursor.unhide()
      cursorHidden = false
    }

    let wasCaptured = captured
    captured = false
    if notify && wasCaptured {
      emit(state: MouseCapturePlugin.stateReleased)
    }
  }

  // MARK: - Focus

  private func observeFocusLoss() {
    let center = NotificationCenter.default
    // Both, and not just one: the application deactivates on Cmd+Tab, while the
    // window alone resigns key when another window of ours takes focus. Either
    // leaves a captured pointer stranded.
    center.addObserver(
      self,
      selector: #selector(focusLost),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(focusLost),
      name: NSWindow.didResignKeyNotification,
      object: nil
    )
  }

  @objc private func focusLost() {
    // Release rather than pause: the alternative is a hidden cursor over another
    // application's window, which the user cannot recover from.
    release(notify: true)
  }

  // MARK: - Emitting

  private func emit(dx: CGFloat, dy: CGFloat) {
    guard let sink else { return }
    // Sent as binary rather than a map: at a 1000 Hz polling rate this is the
    // hot path, and a two-element Float64List is the cheapest thing the standard
    // codec can carry.
    var values = [Double(dx), Double(dy)]
    let data = values.withUnsafeMutableBufferPointer { Data(buffer: $0) }
    sink(FlutterStandardTypedData(float64: data))
  }

  private func emit(state: Int) {
    sink?(state)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    release(notify: false)
  }
}
