/// Locks the mouse pointer in place and reports its motion as relative deltas.
///
/// Flutter exposes no pointer lock on any desktop platform, which makes a
/// first-person camera impossible out of the box: the cursor reaches the edge of
/// the window and the view stops turning.
///
/// ## Pull, not push
///
/// The delta is drained with [MouseCapture.takeDelta] rather than delivered by a
/// stream. That is the shape a game wants. A simulation running on a fixed
/// timestep asks "how far did the mouse move since the last step" once per step;
/// handing it a stream of individual mouse events only moves the accumulation
/// into every caller, and each of them has to get it right.
library;

import 'dart:async';
import 'dart:ui' show Offset;

import 'src/mouse_capture_platform_interface.dart';

export 'src/mouse_capture_platform_interface.dart'
    show CaptureState, MouseCapturePlatform;

/// Pointer capture, and the motion accumulated while it is held.
final class MouseCapture {
  /// Takes a platform so tests can supply a fake one; production code should use
  /// [instance].
  MouseCapture({MouseCapturePlatform? platform})
      : _platform = platform ?? MouseCapturePlatform.instance {
    _stateSubscription = _platform.stateChanges.listen(_onStateChanged);

    // Fired and not awaited, on purpose, and this is the whole reason `reset`
    // exists: after a hot restart the native side may still be holding the
    // pointer with the cursor hidden, and nothing else will ever ask for it
    // back. Failures are swallowed because a platform without an implementation
    // has nothing to reset.
    if (_platform.isSupported) {
      unawaited(_platform.reset().catchError((Object _) {}));
    }
  }

  /// The instance the application uses.
  static final MouseCapture instance = MouseCapture();

  final MouseCapturePlatform _platform;

  StreamSubscription<Offset>? _deltaSubscription;
  late final StreamSubscription<CaptureState> _stateSubscription;
  final StreamController<CaptureState> _stateController =
      StreamController<CaptureState>.broadcast();

  double _dx = 0.0;
  double _dy = 0.0;
  bool _isCaptured = false;

  /// False where there is no pointer to capture, so a caller can offer another
  /// control scheme instead of discovering the gap at the first call.
  bool get isSupported => _platform.isSupported;

  bool get isCaptured => _isCaptured;

  /// Capture and release, including releases the application did not ask for.
  ///
  /// Losing window focus drops the capture — anything else would leave a hidden
  /// cursor over another application, which the user cannot recover from. A game
  /// should treat an unrequested [CaptureState.released] as a reason to pause.
  Stream<CaptureState> get onStateChanged => _stateController.stream;

  /// Holds the pointer in place and starts accumulating motion.
  ///
  /// Does nothing where [isSupported] is false, rather than throwing: a caller
  /// that has already checked should not have to check twice, and one that has
  /// not is better served by a camera that does not turn than by a crash.
  Future<void> capture() async {
    if (!_platform.isSupported || _isCaptured) return;

    // Whatever moved the pointer before the capture belongs to the cursor, not
    // to the camera. Keeping it would snap the view on the first frame.
    _dx = 0.0;
    _dy = 0.0;

    _deltaSubscription ??= _platform.deltas.listen(_accumulate);
    await _platform.capture();
  }

  /// Releases the pointer. Motion accumulated but not yet taken is kept, so a
  /// release between two simulation steps does not lose the last fragment.
  Future<void> release() async {
    if (!_platform.isSupported || !_isCaptured) return;
    await _platform.release();
    _setCaptured(false);
  }

  /// Returns the motion accumulated since the last call and resets it.
  ///
  /// Synchronous by design: it is called from inside the simulation step, where
  /// awaiting anything would mean the step no longer sees a consistent snapshot
  /// of its inputs.
  Offset takeDelta() {
    final delta = Offset(_dx, _dy);
    _dx = 0.0;
    _dy = 0.0;
    return delta;
  }

  void _accumulate(Offset delta) {
    _dx += delta.dx;
    _dy += delta.dy;
  }

  void _onStateChanged(CaptureState state) {
    _setCaptured(state == CaptureState.captured);
  }

  void _setCaptured(bool value) {
    if (_isCaptured == value) return;
    _isCaptured = value;
    _stateController
        .add(value ? CaptureState.captured : CaptureState.released);
  }

  Future<void> dispose() async {
    await _deltaSubscription?.cancel();
    await _stateSubscription.cancel();
    await _stateController.close();
  }
}
