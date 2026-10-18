import 'package:vector_math/vector_math.dart';

/// Where something in the scene is, asked once a mix: a node's world matrix.
///
/// **A function rather than a node type**, because this package knows no
/// scene graph and must not: a listener follows `() => camera.worldMatrix`
/// and an emitter `() => torch.worldMatrix`, and a game with no scene graph
/// at all hands in a matrix it builds itself. The matrix is read as the
/// engine's frame: metres, Y up, right-handed, the node looking along its
/// own −Z.
typedef PoseSource = Matrix4 Function();

/// The translation of [world] into [position], in metres.
void poseTranslation(Matrix4 world, Vector3 position) {
  final s = world.storage;
  position.setValues(s[12], s[13], s[14]);
}

/// The direction [world] looks along, its −Z, into [forward], as a unit
/// vector; left unchanged when the matrix has no −Z to speak of.
void poseForward(Matrix4 world, Vector3 forward) {
  final s = world.storage;
  _unitInto(-s[8], -s[9], -s[10], forward);
}

/// The way up for [world], its +Y, into [up], as a unit vector; left
/// unchanged when the matrix has none.
void poseUp(Matrix4 world, Vector3 up) {
  final s = world.storage;
  _unitInto(s[4], s[5], s[6], up);
}

/// The velocity of something placed by hand, from where it was at one mix
/// and where it is at the next — what `placeAt` on the listener and on an
/// emitter feeds the doppler shift with.
///
/// **Per mix, not per call.** A game may place a thing several times between
/// two mixes, or not at all; what the ear hears is where it was when the last
/// mix ran and where it is now, so the difference is taken over the mix's own
/// seconds in [settle]. The rules:
///
/// * the first placement gives no velocity, since there is nothing to
///   measure from;
/// * a placement with `teleport: true` gives none either and starts measuring
///   again from there, so a respawn or a cut is not heard as a sonic boom;
/// * a placement with an explicit `velocity:` is taken as it is for that mix;
/// * a thing placed by hand that was not placed again before a mix has stood
///   still, and its velocity drops to nought;
/// * a mix of nought seconds measures nothing and changes nothing.
///
/// Not exported: the listener and the emitter each hold one.
final class HandMotion {
  final Vector3 _baseline = Vector3.zero();
  bool _hasBaseline = false;
  bool _active = false;
  bool _moved = false;
  bool _explicit = false;

  /// Records a placement by hand. [velocity] is the explicit one, if given;
  /// [teleport] drops the measurement. [out] is the velocity to write.
  void placed(Vector3 out, {Vector3? velocity, bool teleport = false}) {
    _active = true;
    _moved = true;
    if (velocity != null) {
      out.setFrom(velocity);
      _explicit = true;
    } else if (teleport) {
      out.setZero();
      _explicit = true;
    }
    if (teleport) _hasBaseline = false;
  }

  /// Stops measuring: the thing is moved by a node now, or a fresh start.
  void reset() {
    _active = false;
    _hasBaseline = false;
    _moved = false;
    _explicit = false;
  }

  /// Once a mix, [seconds] after the last: works [out] out from how far
  /// [position] moved since then, by the rules above.
  void settle(Vector3 position, Vector3 out, double seconds) {
    if (!_active || !(seconds > 0.0) || !seconds.isFinite) return;
    if (!_explicit) {
      if (_moved && _hasBaseline) {
        out
          ..setFrom(position)
          ..sub(_baseline)
          ..scale(1.0 / seconds);
      } else {
        out.setZero();
      }
    }
    _baseline.setFrom(position);
    _hasBaseline = true;
    _moved = false;
    _explicit = false;
  }
}

void _unitInto(double x, double y, double z, Vector3 out) {
  final length2 = x * x + y * y + z * z;
  // A node scaled to nothing has no direction; keeping the last good one is
  // better than a NaN reaching the panning.
  if (length2 < 1e-12) return;
  out
    ..setValues(x, y, z)
    ..normalize();
}
