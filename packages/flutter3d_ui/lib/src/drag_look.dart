import 'package:flutter/gestures.dart';
import 'package:vector_math/vector_math.dart';

/// Looking around by dragging, where there is no pointer to lock.
///
/// **Two games had written this**, identically: a `Vector2`, a `bool`, three
/// pointer callbacks and a drain. It is what the browser and the phone use
/// instead of a captured pointer — on the web there is nothing to capture until
/// the player has clicked, and on a phone there is nothing to capture at all.
///
/// **The drag is drained rather than read**, and that is the part worth keeping
/// in one place. The motion cannot go through `InputState` like the captured
/// pointer's does, because `endStep` clears that at the end of every simulation
/// step — so on a frame where the loop ran twice, or none, the camera would
/// find the drag already thrown away. Whoever turns the view takes it from
/// here, once, and gets everything that arrived since they last asked.
final class DragLook {
  /// Whether a finger or a button is down.
  ///
  /// Motion with nothing down is a mouse crossing the window, which is not a
  /// player looking anywhere.
  bool get isDragging => _dragging;
  bool _dragging = false;

  void begin() => _dragging = true;

  /// Ends the drag. Also the answer for a cancelled pointer — a drag the system
  /// took away is a drag that ended, and a game that only listened for "up"
  /// kept turning after a notification slid down over it.
  void end() => _dragging = false;

  /// Adds a pointer's movement, if one is down.
  void moved(Offset delta) {
    if (!_dragging) return;
    _pending.add(Vector2(delta.dx, delta.dy));
  }

  /// Takes everything accumulated since the last call, into [out].
  void drainInto(Vector2 out) {
    out.setFrom(_pending);
    _pending.setZero();
  }

  /// The same, for a caller that has nowhere to put it.
  Vector2 take() {
    final taken = _pending.clone();
    _pending.setZero();
    return taken;
  }

  final Vector2 _pending = Vector2.zero();
}
