import 'dart:math' as math;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show WorldPosition;
import 'package:vector_math/vector_math.dart';

import 'pose.dart';

/// Where the ears are.
///
/// Position and a basis rather than a matrix, because that is what the two
/// calculations need — a distance and a left-right dot product — and because a
/// game that has a yaw and no camera object should not have to build a matrix
/// to be heard from.
///
/// ## A component of the scene
///
/// A game with a scene graph does not place the listener at all: it hands
/// it the camera node with [follow], and each mix reads the node's world
/// matrix — position, the way it looks, the way up — and the velocity from
/// how far it moved. Placed by hand ([aimAt], [aimAlong], [placeFrom]) is the
/// same listener for a game without one.
///
/// ## Positions are relative to an origin
///
/// [position], like every [AudioEmitter]'s, is a float32 offset in metres
/// from an origin the game names: the scene's origin, which a scene graph
/// keeps near the camera. A camera's world matrix is already in that
/// space, so [follow] and [placeFrom] need nothing more. A place in the
/// world, a [WorldPosition] in doubles, comes in through [placeAt] with
/// that origin; the subtraction is done in doubles and only the small
/// difference narrowed, as the units contract asks.
///
/// Units: metres, metres per second, the engine's Y-up right-handed frame.
final class AudioListener {
  AudioListener({Vector3? position, Vector3? forward, Vector3? up})
    : position = position?.clone() ?? Vector3.zero(),
      forward = forward?.clone() ?? Vector3(0.0, 0.0, -1.0),
      up = up?.clone() ?? Vector3(0.0, 1.0, 0.0) {
    _refreshRight();
  }

  /// Where the ears are, in metres.
  final Vector3 position;

  /// The way the ears face, a unit vector.
  final Vector3 forward;

  /// The way up for the ears, a unit vector.
  final Vector3 up;

  /// How fast the ears are moving, in metres per second: what a doppler
  /// shift is computed from. Derived while the mix is given its seconds
  /// (`AudioScene.update(dt:)`): from the node while [follow]ing one, and
  /// from successive [placeAt] calls otherwise. Set by hand for a listener
  /// placed only with [aimAt], [aimAlong] or [placeFrom].
  final Vector3 velocity = Vector3.zero();

  PoseSource? _pose;
  bool _placed = false;
  final Vector3 _was = Vector3.zero();
  final HandMotion _hand = HandMotion();

  /// The node this listener follows, or null when it is placed by hand.
  PoseSource? get following => _pose;

  /// Follows [pose] from the next mix on — usually `() => camera.worldMatrix`
  /// — or stops following with null, leaving the listener where it was.
  void follow(PoseSource? pose) {
    _pose = pose;
    _placed = false;
    _hand.reset();
  }

  /// Places the listener at [world]'s translation, facing its −Z with its
  /// +Y up: a camera's world matrix, read the way the renderer reads it.
  ///
  /// The whole orientation, pitch included, unlike [aimAt]: the pan reads
  /// only the listener's right, which a camera looking at the floor keeps
  /// level, and a binaural renderer wants to know which way is up.
  void placeFrom(Matrix4 world) {
    poseTranslation(world, position);
    poseForward(world, forward);
    poseUp(world, up);
    _refreshRight();
  }

  /// Places the listener at [at] in the world, facing [forward], with [up]
  /// (+Y by default) as the way up: [position] becomes [at]'s offset from
  /// [origin], worked out in doubles.
  ///
  /// [origin] is the one [position] is relative to, the scene's origin for a
  /// game that draws one; every emitter's position has to be relative to the
  /// same one. **Required, with no default**: the world's origin as a default
  /// was right only until the loop moved its own, and then every sound was
  /// heard from where the camera had been kilometres ago. This is the shape
  /// `Flutter3dView.onListenerMoved` hands over in its `ListenerPose`:
  ///
  /// ```dart
  /// onListenerMoved: (ears) => listener.placeAt(
  ///   ears.position,
  ///   ears.forward,
  ///   origin: ears.origin,
  ///   up: ears.up,
  /// ),
  /// ```
  ///
  /// The whole orientation, as [placeFrom]. A listener that [follow]s a node
  /// is moved by the node on the next mix.
  ///
  /// **The velocity comes from the placements.** At each mix it is how far
  /// the listener moved since the last one over the mix's seconds, which is
  /// what doppler hears (`EqualPowerPanner.dopplerFactor`). The first
  /// placement measures nothing; [teleport] says this placement is a jump —
  /// a respawn, a camera cut — and the velocity is nought for it and measured
  /// again from here; [velocity] gives it outright for this mix, for a game
  /// that knows it better (from its physics) than a difference would. A
  /// listener not placed again before a mix has stood still.
  void placeAt(
    WorldPosition at,
    Vector3 forward, {
    required WorldPosition origin,
    Vector3? up,
    Vector3? velocity,
    bool teleport = false,
  }) {
    _hand.placed(this.velocity, velocity: velocity, teleport: teleport);
    final offset = at.relativeTo(origin);
    position.setValues(offset.x, offset.y, offset.z);
    this.forward.setFrom(forward);
    if (this.forward.length2 < 1e-12) {
      this.forward.setValues(0.0, 0.0, -1.0);
    } else {
      this.forward.normalize();
    }
    if (up == null) {
      this.up.setValues(0.0, 1.0, 0.0);
    } else {
      this.up
        ..setFrom(up)
        ..normalize();
    }
    _refreshRight();
  }

  /// Reads the node [follow] was given, if any, and the velocity from how
  /// far it moved in [seconds] — or, placed by hand, how far the [placeAt]
  /// calls moved it. Called by `AudioScene.update` once a mix; nought
  /// seconds places it and leaves the velocity as it was.
  void syncPose(double seconds) {
    final pose = _pose;
    if (pose == null) {
      _hand.settle(position, velocity, seconds);
      return;
    }
    _was.setFrom(position);
    placeFrom(pose());
    if (_placed && seconds > 0.0 && seconds.isFinite) {
      velocity
        ..setFrom(position)
        ..sub(_was)
        ..scale(1.0 / seconds);
    }
    _placed = true;
  }

  /// Derived, and the only one the panning uses.
  Vector3 get right => _right;
  final Vector3 _right = Vector3(1.0, 0.0, 0.0);

  /// Points the listener the way a first-person camera looks.
  ///
  /// Yaw only. Pitch is deliberately ignored: tilting your head back does not
  /// swap left and right, and feeding pitch into a stereo pan makes a sound
  /// swing across the field when the player looks at the floor.
  void aimAt(Vector3 at, double yaw) {
    position.setFrom(at);
    forward.setValues(-math.sin(yaw), 0.0, -math.cos(yaw));
    up.setValues(0.0, 1.0, 0.0);
    _refreshRight();
  }

  /// Points the listener along a direction, whatever produced it.
  ///
  /// [aimAt] takes a yaw and reads it as a first-person camera's: forward is
  /// `(-sin, 0, -cos)`, which is one game's convention baked into the audio
  /// package. A third-person camera whose forward is `(sin, 0, cos)` has to
  /// pass `yaw + pi` and hope, which is how a listener ends up mirrored and
  /// every sound is panned to the wrong ear.
  ///
  /// So a caller that already has a direction hands it over instead of
  /// re-encoding it as an angle for this to decode again.
  void aimAlong(Vector3 at, Vector3 direction) {
    position.setFrom(at);
    forward.setFrom(direction);
    forward.y = 0.0;
    if (forward.length2 < 1e-8) {
      forward.setValues(0.0, 0.0, -1.0);
    } else {
      forward.normalize();
    }
    up.setValues(0.0, 1.0, 0.0);
    _refreshRight();
  }

  void _refreshRight() {
    _right
      ..setFrom(forward)
      ..crossInto(up, _right);
    // A listener looking straight up has no right; keep the last good one
    // rather than dividing by zero and panning everything hard left.
    if (_right.length2 > 1e-12) _right.normalize();
  }
}
