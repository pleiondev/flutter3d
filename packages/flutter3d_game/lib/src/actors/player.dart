/// Who the player's collider is.
///
/// ## The field this untangles
///
/// `Collider.userData` answers "who is this?" — a monster, a door, a pickup,
/// a brush. The player's collider answered something else: it carried the
/// player's `Inventory`, which is not who the collider is but what the body is
/// holding. One untyped field with two different relations in it, and the
/// consequences were two: every place that dealt damage had to test the
/// collider's *layer* for the player while testing `userData` for a monster,
/// and a locked door asking what keys the body holds worked only because
/// `Inventory` happened to be a `KeyHolder`.
///
/// A player is a body, and the body carries an inventory. Saying that directly
/// costs one class and removes both special cases: `userData` is the player,
/// the player is `Damageable`, and the player is a `KeyHolder` because the
/// person holding the keys is the person, not their pockets.
///
/// ## Where the player is looking
///
/// Yaw, pitch, the eye and the aim vector used to live in the application, and
/// the spherical-to-cartesian aim was written out three times there — once for
/// the use key, once for firing, once for the camera's look-at target. Three
/// copies of four lines of trigonometry, which is three chances for one of them
/// to disagree about which way is forward.
///
/// They are here now because they are facts about the pawn, not about the
/// screen. What is *not* here is anything about a camera: this class says where
/// the eye is and which way it points, and a renderer decides what that means
/// for a projection matrix.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../physics/layers.dart';
import '../world/collector.dart';
import '../world/inventory.dart';
import '../world/key_ring.dart';
import '../world/rider.dart';
import 'damageable.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';

final class Player with KeyHolder implements Collector, Damageable, Rider {
  Player({
    required this.body,
    Inventory? inventory,
    this.eyeOffset = 0.7,
    this.lookSensitivity = 0.0022,
  }) : inventory = inventory ?? Inventory() {
    // The one line that makes this worth having: from here on, "who is this
    // collider" has one answer for every collider in the world.
    body.collider.userData = this;
    body.collider.layer = CollisionLayers.player;
  }

  /// The capsule that walks, jumps and rides lifts.
  final CharacterController body;

  /// What is being carried: health, armour, weapons, keys, power-ups.
  ///
  /// Also the answer [Collector] asks for, which is how a pickup reaches it.
  @override
  final Inventory inventory;

  /// The keys the *person* holds.
  ///
  /// Forwarded rather than inherited from the inventory so that
  /// `MechanismWorld.activationBy` — which asks whether a collider's owner is a
  /// [KeyHolder] — keeps working unchanged. It used to find the inventory
  /// itself there, which was right by accident.
  @override
  Set<String> get keys => inventory.keys;

  /// What the player is standing on, so a lift can tell a passenger from
  /// somebody in the way. See [Rider].
  @override
  Collider? get carriedBy => body.groundBody;

  @override
  bool applyDamage(double amount) => inventory.damage(amount);

  bool get isAlive => inventory.health.isAlive;

  /// How far the eye sits above the centre of the body.
  final double eyeOffset;

  /// Radians of view movement per unit of pointer motion.
  ///
  /// A field with a default rather than a constant, because it is a user
  /// setting and settings belong to the application. The default is only what
  /// this repository's own game happens to use.
  double lookSensitivity;

  /// Which way the body faces, in radians. Zero looks along −Z.
  double yaw = 0.0;

  /// How far up or down, in radians, always within [pitchLimit].
  double get pitch => _pitch;
  set pitch(double value) => _pitch = value.clamp(-pitchLimit, pitchLimit);
  double _pitch = 0.0;

  /// Just short of straight up.
  ///
  /// **A mathematical invariant, not a matter of taste.** At exactly a right
  /// angle the forward vector becomes parallel to the world up axis, the cross
  /// product that builds the view basis is zero, and the camera's orientation
  /// stops being defined. Which is why the limit is on the pawn and not left to
  /// each caller to remember.
  static const double pitchLimit = math.pi / 2.0 - 0.01;

  Map<String, Object?> save() => <String, Object?>{
        'body': body.save(),
        'inventory': inventory.save(),
        'yaw': yaw,
        'pitch': _pitch,
      };

  void restore(Map<String, Object?> from) {
    final body = from['body'];
    if (body is Map) this.body.restore(body.cast<String, Object?>());
    final inventory = from['inventory'];
    if (inventory is Map) {
      this.inventory.restore(inventory.cast<String, Object?>());
    }
    yaw = (from['yaw'] as num?)?.toDouble() ?? yaw;
    // Through the setter, so a snapshot written by a build with a different
    // pitch limit cannot restore a camera with no orientation.
    pitch = (from['pitch'] as num?)?.toDouble() ?? _pitch;
  }

  /// Turns the view by a pointer delta, applying [lookSensitivity] and the
  /// pitch limit.
  void look(Vector2 delta) {
    yaw -= delta.x * lookSensitivity;
    pitch = _pitch - delta.y * lookSensitivity;
  }

  /// Where the eye is, from where the body simulated itself to be.
  void eye(Vector3 out) => eyeFrom(body.position, out);

  /// Where the eye is, given a body position.
  ///
  /// Exists for the camera, which must read the *interpolated* position rather
  /// than the simulated one: on a display faster than the step rate, several
  /// frames in a row would otherwise show the same place and then jump.
  ///
  /// Safe to call with [out] and [position] being the same vector.
  void eyeFrom(Vector3 position, Vector3 out) {
    out.setFrom(position);
    out.y += eyeOffset;
  }

  /// The unit vector the crosshair points along — a shot, a use ray, and what
  /// the camera looks at.
  void aim(Vector3 out) {
    final cosPitch = math.cos(_pitch);
    out.setValues(
      -math.sin(yaw) * cosPitch,
      math.sin(_pitch),
      -math.cos(yaw) * cosPitch,
    );
  }

  /// Where forward is on the ground, ignoring pitch.
  void forward(Vector3 out) =>
      out.setValues(-math.sin(yaw), 0.0, -math.cos(yaw));

  /// Where the right hand is on the ground, ignoring pitch.
  void right(Vector3 out) =>
      out.setValues(math.cos(yaw), 0.0, -math.sin(yaw));

  /// The direction to walk for a movement axis, from [InputState.moveAxis].
  ///
  /// **Yaw only, deliberately.** Walking forward while looking at the floor
  /// must not drive the player into it — that is what a fly camera does, and
  /// not what a first-person one should. The pitch is where you look, not where
  /// you go.
  ///
  /// Not normalised: an axis at half deflection is a request to walk at half
  /// speed, and normalising here would throw that away.
  void moveWish(Vector2 axis, Vector3 out) {
    final sin = math.sin(yaw);
    final cos = math.cos(yaw);
    out.setValues(
      -sin * axis.y + cos * axis.x,
      0.0,
      -cos * axis.y - sin * axis.x,
    );
  }
}
