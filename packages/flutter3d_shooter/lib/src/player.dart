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

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'collector.dart';
import 'inventory.dart';


final class Player with KeyHolder implements Collector, Damageable, Rider {
  Player({
    required this.body,
    Inventory? inventory,
    this.eyeOffset = 0.7,
    this.lookSensitivity = 0.0022,
    this.crouchHeight = 0.55,
    this.crouchSpeed = 1.9,
  }) : inventory = inventory ?? Inventory() {
    _standing = body.collider.shape;
    _crouching = CollisionCapsule(
      radius: body.halfExtents.x,
      halfHeight: math.max(0.01, crouchHeight - body.halfExtents.x),
    );
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
  bool applyDamage(double amount, {Object? from}) =>
      inventory.damage(amount);

  bool get isAlive => inventory.health.isAlive;

  /// How far the eye sits above the centre of the body.
  final double eyeOffset;

  /// Half the height of the body while crouched, in metres.
  final double crouchHeight;

  /// How fast it walks while crouched.
  final double crouchSpeed;

  /// Whether the body is down.
  ///
  /// **Held, not toggled.** A toggle is one more piece of state a player has to
  /// track about themselves in a game where the interesting state is in front
  /// of them, and it is what makes somebody walk into a fight still crawling.
  bool get isCrouching => _crouched;
  bool _crouched = false;

  /// Set when a crouch could not be stood up out of, so the caller can say so —
  /// or simply so it is tried again next step.
  bool get wantsToStand => _wantsToStand;
  bool _wantsToStand = false;

  late final CollisionShape _standing;
  late final CollisionShape _crouching;

  /// Crouches or stands, as [held] asks and the ceiling allows.
  ///
  /// **Standing can be refused, and that is the whole reason this asks rather
  /// than sets.** A player who crouched into a crawlspace and let go of the key
  /// would otherwise stand up inside the rock and be ejected through it, which
  /// is the oldest bug in the genre. `tryResize` answers the question and
  /// changes nothing when the answer is no.
  void crouch({required bool held}) {
    if (held) {
      _wantsToStand = false;
      if (_crouched) return;
      // Shrinking never fails, and the feet stay where they are: a crouch that
      // dropped the whole body would sink it into the floor.
      if (body.tryResize(_crouching)) _crouched = true;
      return;
    }

    if (!_crouched) return;
    if (body.tryResize(_standing)) {
      _crouched = false;
      _wantsToStand = false;
    } else {
      // There is something overhead. Stay down, and try again next step.
      _wantsToStand = true;
    }
  }

  /// How much of the walking speed a crouched player gets, from nought to one.
  ///
  /// **Through the length of the wish rather than by swapping the tuning**, and
  /// the controller already says why it works: "the length of the request
  /// scales the target speed, so half a stick deflection means half speed". A
  /// second `MovementTuning` would be a second set of numbers to keep true, and
  /// the floor's own surface already swaps that one.
  ///
  /// There is no crouch-sprint: a player holding both gets the slow one,
  /// because that is what they asked for second and what the body is doing.
  double get crouchThrottle =>
      _crouched ? (crouchSpeed / body.tuning.walkSpeed).clamp(0.0, 1.0) : 1.0;

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
        // **Saved, and `CharacterController.save` says why it has to be here
        // rather than there**: a `CollisionShape` is not JSON, so a game that
        // crouches saves that it was crouching and asks for the volume again on
        // the way back. One that forgets restores a standing body inside a
        // crawlspace and is thrown out of it on the first step.
        'crouching': _crouched,
      };

  void restore(Map<String, Object?> from) {
    final body = from['body'];
    if (body is Map) this.body.restore(body.cast<String, Object?>());
    final inventory = from['inventory'];
    if (inventory is Map) {
      this.inventory.restore(inventory.cast<String, Object?>());
    }
    yaw = (from['yaw'] as num?)?.toDouble() ?? yaw;
    // Through the same call the key does, so the body ends up the size the save
    // says it was — and if the room has changed under it, the resize refuses
    // and it stays standing rather than being wedged into rock.
    _crouched = false;
    crouch(held: from['crouching'] == true);
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
    // Scaled by how tall the body is now, so a crouch lowers the view rather
    // than leaving the eye floating where the head used to be. The offset is
    // authored against the standing body, which is what `eyeOffset` means.
    out.y += _crouched
        ? eyeOffset * (body.halfExtents.y / _standingHalfHeight)
        : eyeOffset;
  }

  /// Half the height of the standing body, kept because the eye is a fraction
  /// of it and the body's own is whatever it is right now.
  late final double _standingHalfHeight = _standing.boundsHalfExtents.y;

  /// The unit vector the crosshair points along — a shot, a use ray, and what
  /// the camera looks at.
  ///
  /// Includes [recoilPitch], which is why firing moves where the bullets go
  /// rather than only what the screen shows.
  void aim(Vector3 out) {
    final pitch = (_pitch + recoilPitch).clamp(-pitchLimit, pitchLimit);
    final cosPitch = math.cos(pitch);
    out.setValues(
      -math.sin(yaw) * cosPitch,
      math.sin(pitch),
      -math.cos(yaw) * cosPitch,
    );
  }

  /// How far the sight has been kicked above where it is being held, in
  /// radians.
  ///
  /// **Separate from [pitch], and that is the design rather than an
  /// implementation detail.** Adding recoil into the player's own aim would
  /// mean the game silently moving the thing the player is holding: they let go
  /// of the trigger and are left looking at the ceiling, having never asked to.
  /// This is added on top and eased back to nothing, so a burst climbs while it
  /// is held and the sight returns to where they were pointing.
  double recoilPitch = 0.0;

  /// Kicks the sight up by [radians].
  void kick(double radians) {
    if (radians <= 0.0) return;
    recoilPitch += radians;
  }

  /// Eases the kick away at [perSecond].
  ///
  /// Frame-rate independent, through the same `easeFactor` every camera in this
  /// repository uses: a weapon that climbed differently at thirty and at a
  /// hundred and forty-four frames would be a different weapon on two machines.
  void settleRecoil(double dt, {double perSecond = 7.0}) {
    if (recoilPitch <= 0.0) return;
    recoilPitch -= recoilPitch * easeFactor(perSecond, dt);
    if (recoilPitch < 1e-5) recoilPitch = 0.0;
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
