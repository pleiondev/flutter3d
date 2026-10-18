import Flutter
import GameController
import ObjectiveC
import UIKit

/// Locks the pointer on an iPad with a mouse or a trackpad, and reports its
/// motion as relative deltas.
///
/// ## The technique
///
/// iPadOS 14 gave games exactly this: a view controller that answers
/// `prefersPointerLocked` with true has the pointer hidden and held while its
/// scene is full screen, and `GCMouse` reports the motion as deltas that do not
/// stop at the screen's edge. The scene says when the lock is actually held,
/// through `UIPointerLockState`, and that is what Dart is told: a scene in Split
/// View or Slide Over is refused the lock, and the state stays released instead
/// of pretending it succeeded.
///
/// ## The answer UIKit asks the controller for
///
/// The controller is Flutter's, and an application should not have to subclass
/// it for a plugin. So the getter is added to the controller's class at run
/// time, the way a category would, answering true only for a controller this
/// plugin is holding the pointer for and deferring to the class's own answer
/// otherwise. The controller has to be the root of its window, or a container
/// above it has to name it in `childViewControllerForPointerLock`, which is
/// UIKit's rule rather than this plugin's.
///
/// ## Supported only while a mouse is connected
///
/// An iPhone has no pointer lock and an iPad without a mouse has nothing to
/// lock, and a game there shows its touch controls. So the answer is sent to
/// Dart as a `bool` on the event channel when the stream is listened to and
/// whenever a mouse comes or goes.
///
/// ## Coalesced per run loop turn
///
/// The motion is summed here and sent once per turn of the main run loop, so a
/// mouse polled at 1000 Hz does not cost a channel message per count.
public class Flutter3dPointerLockPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  public static let methodChannelName = "dev.flutter3d/flutter3d_pointer_lock"
  public static let eventChannelName = "dev.flutter3d/flutter3d_pointer_lock/events"

  /// State codes shared with the Dart side, as on every other platform.
  public static let stateReleased = 0
  public static let stateCaptured = 1

  /// Whether this device can lock a pointer at all.
  public static func supports(isPad: Bool, mice: Int) -> Bool {
    isPad && mice > 0
  }

  /// A `GCMouse` delta in the screen's convention: GameController counts y
  /// upwards, Flutter and every other platform here count it down.
  public static func screenDelta(x: Float, y: Float) -> [Double] {
    [Double(x), -Double(y)]
  }

  /// The controllers holding the pointer, read by the added getter.
  private static let locking = NSHashTable<UIViewController>.weakObjects()
  private static var patchedClasses = Set<ObjectIdentifier>()

  private weak var registrar: FlutterPluginRegistrar?
  private var sink: FlutterEventSink?
  private var captured = false
  private weak var controller: UIViewController?

  private var pendingX = 0.0
  private var pendingY = 0.0
  private var flushScheduled = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = Flutter3dPointerLockPlugin()
    instance.registrar = registrar

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)

    instance.observe()
  }

  // MARK: - Method channel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      capture()
      result(nil)
    case "release", "reset":
      // Reset is called by Dart on first use, and after a hot restart it is
      // what gives the pointer back.
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
    // A new listener is a new Dart side: whatever the old one locked is
    // nobody's now.
    release(notify: false)
    reportSupport()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    release(notify: false)
    sink = nil
    return nil
  }

  // MARK: - Capture

  private var isSupported: Bool {
    Flutter3dPointerLockPlugin.supports(
      isPad: UIDevice.current.userInterfaceIdiom == .pad,
      mice: GCMouse.mice().count
    )
  }

  private func flutterController() -> UIViewController? {
    if let controller = registrar?.viewController { return controller }
    return UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
      .first?.rootViewController
  }

  private func capture() {
    guard !captured, controller == nil, isSupported,
      let controller = flutterController()
    else { return }
    self.controller = controller
    pendingX = 0
    pendingY = 0
    Flutter3dPointerLockPlugin.patch(type(of: controller))
    Flutter3dPointerLockPlugin.locking.add(controller)
    for mouse in GCMouse.mice() { listen(to: mouse) }
    controller.setNeedsUpdateOfPrefersPointerLocked()
    // Granted at once on a full-screen scene that already has the pointer;
    // otherwise the scene's notification says so later.
    lockStateChanged()
  }

  /// - Parameter notify: whether Dart is told. False when Dart asked for the
  ///   release itself and already knows; true when the system took it away.
  private func release(notify: Bool) {
    for mouse in GCMouse.mice() { mouse.mouseInput?.mouseMovedHandler = nil }
    if let controller {
      Flutter3dPointerLockPlugin.locking.remove(controller)
      controller.setNeedsUpdateOfPrefersPointerLocked()
    }
    controller = nil
    // Motion summed but not yet sent goes before the state, so a release
    // between two steps does not lose the last fragment.
    flush()
    let wasCaptured = captured
    captured = false
    if notify && wasCaptured {
      sink?(Flutter3dPointerLockPlugin.stateReleased)
    }
  }

  private func listen(to mouse: GCMouse) {
    mouse.mouseInput?.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
      DispatchQueue.main.async { self?.accumulate(x: deltaX, y: deltaY) }
    }
  }

  @objc private func lockStateChanged() {
    guard let controller else { return }
    let locked = controller.view.window?.windowScene?.pointerLockState?.isLocked ?? false
    if locked && !captured {
      captured = true
      sink?(Flutter3dPointerLockPlugin.stateCaptured)
    } else if !locked && captured {
      // The scene let go without being asked: Split View, Slide Over, or the
      // system taking the pointer back.
      release(notify: true)
    }
  }

  // MARK: - Motion

  private func accumulate(x: Float, y: Float) {
    guard captured else { return }
    let delta = Flutter3dPointerLockPlugin.screenDelta(x: x, y: y)
    pendingX += delta[0]
    pendingY += delta[1]
    if !flushScheduled {
      flushScheduled = true
      DispatchQueue.main.async { [weak self] in self?.flush() }
    }
  }

  private func flush() {
    flushScheduled = false
    guard pendingX != 0 || pendingY != 0 else { return }
    var values = [pendingX, pendingY]
    pendingX = 0
    pendingY = 0
    guard let sink else { return }
    // Binary rather than a map, as on the desktops: a two-element Float64List
    // is the cheapest thing the standard codec carries.
    let data = values.withUnsafeMutableBufferPointer { Data(buffer: $0) }
    sink(FlutterStandardTypedData(float64: data))
  }

  // MARK: - Observers

  private func observe() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(focusLost),
      name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(lockStateChanged),
      name: UIPointerLockState.didChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(mouseConnected(_:)),
      name: .GCMouseDidConnect, object: nil)
    center.addObserver(
      self, selector: #selector(mouseDisconnected),
      name: .GCMouseDidDisconnect, object: nil)
  }

  @objc private func focusLost() {
    // Release rather than pause: a pointer held for an application the user
    // has left is one the user cannot get back.
    release(notify: true)
  }

  @objc private func mouseConnected(_ notification: Notification) {
    if controller != nil, let mouse = notification.object as? GCMouse {
      listen(to: mouse)
    }
    reportSupport()
  }

  @objc private func mouseDisconnected() {
    reportSupport()
    if captured && GCMouse.mice().isEmpty { release(notify: true) }
  }

  private func reportSupport() {
    sink?(isSupported)
  }

  // MARK: - The getter UIKit asks

  /// Adds `prefersPointerLocked` to [cls], answering true for a controller in
  /// [locking] and the class's own answer for any other.
  private static func patch(_ cls: AnyClass) {
    let key = ObjectIdentifier(cls)
    guard !patchedClasses.contains(key) else { return }
    patchedClasses.insert(key)

    let selector = #selector(getter: UIViewController.prefersPointerLocked)
    guard let method = class_getInstanceMethod(cls, selector) else { return }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
    let inherited = unsafeBitCast(method_getImplementation(method), to: Getter.self)
    let answer: @convention(block) (UIViewController) -> Bool = { controller in
      locking.contains(controller) || inherited(controller, selector)
    }
    let implementation = imp_implementationWithBlock(answer)
    // Added to the class itself when only a superclass answers, so the
    // superclass keeps its own answer for every other class; replaced in place
    // when the class already has one, which [inherited] then calls.
    if !class_addMethod(cls, selector, implementation, method_getTypeEncoding(method)) {
      method_setImplementation(method, implementation)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    release(notify: false)
  }
}
