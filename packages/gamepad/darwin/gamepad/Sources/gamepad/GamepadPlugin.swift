import GameController

#if os(macOS)
import FlutterMacOS
#else
import Flutter
import UIKit
#endif

/// Reads a controller through `GameController.framework` and forwards what it
/// says.
///
/// ## One source for macOS and iOS
///
/// The framework is the same framework on both, down to the property names, so
/// two copies of this file would be two copies to fix. `sharedDarwinSource` in
/// the pubspec is what lets one serve both; the only differences are which
/// Flutter module to import and which notification means "the player has gone
/// away", and both are three lines.
///
/// ## What is deliberately not here
///
/// **No arithmetic and no decisions**, the same rule the Android side follows.
/// The values go out in a fixed order and `lib/src/darwin_mapping.dart` decides
/// what they mean — including the one thing Apple does differently from
/// everybody else, which is that a stick's y is positive *upwards*. Flipping it
/// here would put it where no test could see it.
///
/// The order below is the order that file reads: six axes, then one value per
/// button in `PadButton.known`'s order. That list and `GCExtendedGamepad` agree
/// because both are the physical layout of a controller, and a test on the Dart
/// side checks the count.
public class GamepadPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let eventChannelName = "dev.flutter3d/gamepad/events"

  /// Six axes and seventeen buttons — see the class doc on the order.
  private static let axisCount = 6

  private var sink: FlutterEventSink?
  private weak var controller: GCController?
  private var observers: [NSObjectProtocol] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = GamepadPlugin()
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let channel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    channel.setStreamHandler(instance)
  }

  // MARK: - Listening

  public func onListen(
    withArguments _: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    observe()
    // Whatever is already paired. A controller connected before the game started
    // produces no notification and would otherwise stay invisible until the
    // player turned it off and on again.
    adopt(GCController.controllers().first)
    return nil
  }

  public func onCancel(withArguments _: Any?) -> FlutterError? {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
    controller?.extendedGamepad?.valueChangedHandler = nil
    controller = nil
    sink = nil
    return nil
  }

  private func observe() {
    let centre = NotificationCenter.default
    observers.append(
      centre.addObserver(
        forName: .GCControllerDidConnect, object: nil, queue: .main
      ) { [weak self] note in
        self?.adopt(note.object as? GCController)
      })

    observers.append(
      centre.addObserver(
        forName: .GCControllerDidDisconnect, object: nil, queue: .main
      ) { [weak self] note in
        guard let self, (note.object as? GCController) === self.controller else { return }
        self.controller = nil
        // The Dart side zeroes before it passes the news on, so a controller
        // whose battery dies mid-corner cannot leave the throttle where it was.
        self.sink?(["event": "disconnected"])
        // Another pad may still be paired. Taking it is what makes swapping
        // controllers work without a relaunch.
        self.adopt(GCController.controllers().first)
      })

    // Losing the player, which is not the same as losing the pad. Handled
    // natively, as `MouseCapturePlugin` handles focus loss and for its reason:
    // the last values before the window went away are the ones the pad would
    // otherwise stay in, and a stick left half over keeps walking behind
    // whatever is now on screen.
    #if os(macOS)
      let away = NSApplication.didResignActiveNotification
    #else
      let away = UIApplication.willResignActiveNotification
    #endif
    observers.append(
      centre.addObserver(forName: away, object: nil, queue: .main) { [weak self] _ in
        self?.sink?(["event": "relaxed"])
      })
  }

  // MARK: - The controller

  private func adopt(_ candidate: GCController?) {
    guard let candidate, let pad = candidate.extendedGamepad else { return }
    guard candidate !== controller else { return }

    controller?.extendedGamepad?.valueChangedHandler = nil
    controller = candidate
    sink?([
      "event": "connected",
      "name": candidate.vendorName ?? "",
    ])

    pad.valueChangedHandler = { [weak self] pad, _ in
      self?.forward(pad)
    }
    // Once immediately: the handler fires on change, and a stick already held
    // when the game started has not changed since.
    forward(pad)
  }

  private func forward(_ pad: GCExtendedGamepad) {
    guard let sink else { return }

    // Fixed order, and the Dart side reads it by index. Sticks first, then the
    // triggers as travel, then a value per button.
    var sample: [Double] = [
      Double(pad.leftThumbstick.xAxis.value),
      Double(pad.leftThumbstick.yAxis.value),
      Double(pad.rightThumbstick.xAxis.value),
      Double(pad.rightThumbstick.yAxis.value),
      Double(pad.leftTrigger.value),
      Double(pad.rightTrigger.value),
    ]
    sample.reserveCapacity(GamepadPlugin.axisCount + 17)

    // `PadButton.known`'s order, which is the physical layout: the four face
    // buttons by position, the d-pad, the shoulders, the triggers, the stick
    // clicks, then menu, options and home.
    let buttons: [GCControllerButtonInput?] = [
      pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
      pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right,
      pad.leftShoulder, pad.rightShoulder,
      pad.leftTrigger, pad.rightTrigger,
      pad.leftThumbstickButton, pad.rightThumbstickButton,
      pad.buttonMenu, pad.buttonOptions, pad.buttonHome,
    ]
    for button in buttons {
      guard let button else {
        // A control this pad does not have — plenty have no home button and
        // older ones have no clickable sticks. Nought rather than a gap, so the
        // indices stay where the Dart side expects them.
        sample.append(0.0)
        continue
      }
      // A bit, and only a bit — the framework's own `isPressed`, so nobody here
      // decides what counts as pressed. A trigger's travel is already in the
      // axes above and does not need sending twice.
      sample.append(button.isPressed ? 1.0 : 0.0)
    }

    sink(FlutterStandardTypedData(float64: Data(bytes: sample, count: sample.count * 8)))
  }
}
