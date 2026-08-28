/// Getting down, and standing up when there is room.
///
///     flutter test test/crouch_test.dart
///
/// **The shooter could not crouch.** The platformer has been able to since it
/// was written — it slides, drops through floors and fits under things — and
/// the first-person game, which is the one with corridors and crawlspaces in
/// it, had one height and one speed.
///
/// The machinery is the engine's and was already there: `tryResize` swaps a
/// body's volume, keeps its feet where they are, and **refuses when the new
/// shape does not fit**. What is this game's is when to ask, what it costs in
/// speed, and where the eye goes.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A floor, and a player standing on it.
({CollisionWorld world, Player player}) _room() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
    ..update();
  return (
    world: world,
    player: Player(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    ),
  );
}

void main() {
  test('crouching makes the body shorter and the eye lower', () {
    final it = _room();
    final standing = it.player.body.halfExtents.y;
    final eye = Vector3.zero();
    it.player.eye(eye);
    final standingEye = eye.y;

    it.player.crouch(held: true);

    expect(it.player.isCrouching, isTrue);
    expect(it.player.body.halfExtents.y, lessThan(standing));
    it.player.eye(eye);
    expect(
      eye.y,
      lessThan(standingEye),
      reason: 'the view stayed where the head used to be',
    );

    // **The claim that a mutation asked for.** Dropping the body alone lowers
    // the eye a little, because the feet stay put and the centre comes down —
    // so "lower than before" passes even when the offset is not scaled at all,
    // and leaves the view floating above a crouched head. What has to be true
    // is that the eye is inside the body it belongs to.
    final crown = it.player.body.position.y + it.player.body.halfExtents.y;
    expect(
      eye.y,
      lessThanOrEqualTo(crown),
      reason: 'the eye is above the head it is in',
    );
  });

  test('and the feet stay on the floor', () {
    // A crouch that dropped the whole body would sink it into the ground and
    // be depenetrated back out, which reads as a hop.
    final it = _room();
    final feet = it.player.body.position.y - it.player.body.halfExtents.y;

    it.player.crouch(held: true);

    final after = it.player.body.position.y - it.player.body.halfExtents.y;
    expect(after, closeTo(feet, 1e-6));
  });

  test('and letting go stands back up', () {
    final it = _room();
    final standing = it.player.body.halfExtents.y;
    it.player.crouch(held: true);

    it.player.crouch(held: false);

    expect(it.player.isCrouching, isFalse);
    expect(it.player.body.halfExtents.y, closeTo(standing, 1e-6));
    expect(it.player.wantsToStand, isFalse);
  });

  test('and a ceiling refuses it, which is the whole point', () {
    // **The oldest bug in the genre.** A player who crouched into a crawlspace
    // and let go would otherwise stand up inside the rock and be thrown through
    // it. `tryResize` answers the question and changes nothing when the answer
    // is no.
    final it = _room();
    it.player.crouch(held: true);
    // A slab just above the crouched head, well below where a standing one
    // would be.
    final crouched = it.player.body.position.y + it.player.body.halfExtents.y;
    it.world
      ..addBox(Vector3(0.0, crouched + 0.35, 0.0), Vector3(6.0, 0.5, 6.0))
      ..update();

    it.player.crouch(held: false);

    expect(it.player.isCrouching, isTrue, reason: 'it stood up into the rock');
    expect(
      it.player.wantsToStand,
      isTrue,
      reason: 'nothing recorded that it is still trying',
    );
  });

  test('and it keeps trying, so the crawlspace lets go at the far end', () {
    final it = _room();
    it.player.crouch(held: true);
    final crouched = it.player.body.position.y + it.player.body.halfExtents.y;
    final ceiling = it.world.add(
      Collider(
        shape: CollisionBox(Vector3(3.0, 0.25, 3.0)),
        position: Vector3(0.0, crouched + 0.35, 0.0),
      ),
    );
    it.world.update();
    it.player.crouch(held: false);
    expect(it.player.isCrouching, isTrue);

    // Out from under it: the same call, one step later.
    it.world
      ..remove(ceiling)
      ..update();
    it.player.crouch(held: false);

    expect(it.player.isCrouching, isFalse);
  });

  test('and a crouched player walks slower than a walking one', () {
    final it = _room();
    expect(it.player.crouchThrottle, 1.0);

    it.player.crouch(held: true);

    expect(it.player.crouchThrottle, lessThan(1.0));
    expect(
      it.player.crouchThrottle,
      greaterThan(0.0),
      reason: 'a crouch that cannot move at all is a stop, not a crouch',
    );
  });

  test('and a save remembers it', () {
    // `CharacterController.save` says why this has to be the game's job: a
    // `CollisionShape` is not JSON, so a game that crouches saves that it was
    // crouching and asks for the volume again on the way back.
    final it = _room();
    it.player.crouch(held: true);
    final saved = it.player.save();

    final loaded = _room().player..restore(saved);

    expect(loaded.isCrouching, isTrue);
    expect(
      loaded.body.halfExtents.y,
      closeTo(it.player.body.halfExtents.y, 1e-6),
    );
  });
}
