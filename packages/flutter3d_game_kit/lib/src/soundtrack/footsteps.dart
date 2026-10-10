import 'package:vector_math/vector_math.dart';

/// Footsteps, paid for in metres walked on the ground.
///
/// **Distance rather than time**, which is the difference between a walk and
/// a sprint sounding like the same person at two speeds and sounding like two
/// different people. Only across the ground, and only while the feet are
/// down: someone crossing a gap covers ground and takes no steps, and hearing
/// footsteps in mid-air is the sort of thing nobody reports and everybody
/// notices.
///
/// ```dart
/// if (footsteps.walked(body.position, grounded: body.isGrounded)) {
///   out.add(Heard(Sounds.step, body.position));
/// }
/// ```
final class Footsteps {
  Footsteps({required this.stride});

  /// How far apart the steps are, in metres.
  final double stride;

  double _since = 0.0;
  final Vector3 _wasAt = Vector3.zero();
  bool _placed = false;

  /// Whether a step falls now that the walker is [at]. Called once a step.
  ///
  /// The first call only places the walker. Leaving the ground winds the
  /// count back to most of a stride, so the first step after a landing comes
  /// soon but not on the landing itself.
  bool walked(Vector3 at, {required bool grounded}) {
    if (!_placed) {
      _wasAt.setFrom(at);
      _placed = true;
      return false;
    }

    final moved = Vector3(at.x - _wasAt.x, 0.0, at.z - _wasAt.z).length;
    _wasAt.setFrom(at);

    if (!grounded) {
      _since = stride * 0.6;
      return false;
    }

    _since += moved;
    if (_since < stride) return false;
    _since = 0.0;
    return true;
  }

  /// For a level change or a restart: the next call places the walker anew.
  void reset() {
    _since = 0.0;
    _placed = false;
  }
}
