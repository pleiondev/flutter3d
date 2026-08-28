import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'pad_snapshot.dart';
import 'platform_default.dart';

/// Whether a pad is attached.
///
/// Two states rather than a bool, for the reason `pointer_lock`'s
/// `CaptureState` has two: the interesting part is *which way* it changed. A
/// game that sees `disconnected` has to release whatever the pad was holding,
/// and a game that sees `connected` may want to say so on screen.
enum PadConnection { disconnected, connected }

/// The platform side of a gamepad.
///
/// Split out so everything above it — the dead zone, the button vocabulary, the
/// translation into a game's actions — can be tested without a device. That
/// matters more here than anywhere else in this repository: the specification
/// records that an earlier gamepad stub was **deleted rather than finished**,
/// because a backend written without a controller in hand is wrong in a way no
/// test shows. What a fake platform can prove is everything on this side of the
/// channel, and that is most of the code.
abstract base class GamepadPlatform extends PlatformInterface {
  GamepadPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Chosen at compile time — see `platform_default.dart`. The browser gets a
  /// real implementation; everything else gets [UnsupportedGamepad] until a
  /// native backend is written with a controller in hand.
  static GamepadPlatform _instance = defaultGamepadPlatform();

  static GamepadPlatform get instance => _instance;

  static set instance(GamepadPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// False where this package has no implementation.
  ///
  /// A **whitelist**, never try-and-see: asking the channel and catching the
  /// failure means every unsupported platform pays a `MissingPluginException`
  /// at first use, and a listener that has already been attached cannot be
  /// un-attached. `pointer_lock` learnt this and says so.
  bool get isSupported;

  /// Attaching and detaching, as it happens.
  Stream<PadConnection> get connectionChanges;

  /// Fills [out] with what the pad is doing now.
  ///
  /// Synchronous, because it is read inside the frame that uses it. An
  /// asynchronous read would be a value that is stale by an unknown amount,
  /// which is the one thing a fixed-step simulation cannot work with.
  void read(PadSnapshot out);

  /// Stops listening. Called when the last owner goes away.
  Future<void> dispose() async {}
}

/// The platform for a build with no gamepad implementation.
///
/// Public because a test in another package wants a pad that is honestly
/// absent, which is not the same as the default instance — on the web the
/// default is a real implementation.
///
/// Answers "no pad, ever" without opening a channel, so a game on a platform
/// this package does not serve behaves exactly as it did before the package
/// existed. There is no `MissingPluginException` to catch because nothing is
/// called.
final class UnsupportedGamepad extends GamepadPlatform {
  @override
  bool get isSupported => false;

  @override
  Stream<PadConnection> get connectionChanges =>
      const Stream<PadConnection>.empty();

  @override
  void read(PadSnapshot out) => out.disconnect();
}
