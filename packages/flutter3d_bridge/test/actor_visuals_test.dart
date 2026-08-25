/// Which way an actor's model faces, and how its animation ends.
///
///     flutter test test/actor_visuals_test.dart
///
/// **Both of these arrived with the models and neither could have arrived
/// before them**, which is what makes them worth a file. A capsule is round
/// about the axis it spins on, so it cannot face the wrong way; a capsule has
/// no clips, so it cannot loop the wrong one. Every monster in the crypt did
/// both from the moment it stopped being a capsule, and both were reported by
/// somebody playing rather than by anything here:
///
/// * "лягушка движется (и падает) спиной вперёд" — an actor's yaw points down
///   -Z and a glTF character faces +Z, half a turn apart.
/// * "почему анимация падения зациклена была?" — `AnimationPlayer.wrap`
///   defaults to looping, so a death clip restarted the instant it ended.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One actor with a body and health, in a world with nothing else in it.
Actor _actor({double health = 10.0}) {
  final world = CollisionWorld();
  final system = ActorSystem(world: world, random: GameRandom(1));
  return system.spawn(
    body: CharacterController(world: world),
    health: Health(health),
  );
}

void main() {
  group('what is drawn faces where the actor is going', () {
    test('a capsule is turned by the actor yaw and nothing else', () {
      // Round about the axis it spins on, so a capsule cannot show a facing
      // error — which is why this one arrived with the models.
      final actor = _actor();
      expect(ActorVisuals.yawFor(actor, model: false), equals(actor.yaw));
    });

    test('and a model is turned half a turn further', () {
      // Reported from play: "лягушка движется (и падает) спиной вперёд".
      // An actor's yaw points down -Z at nought and a glTF character faces +Z.
      //
      // Mutation: return `actor.yaw` for a model too — fails, and so does the
      // round trip below.
      final actor = _actor();
      final turned = ActorVisuals.yawFor(actor, model: true);

      expect(turned - actor.yaw, closeTo(math.pi, 1e-9));
    });

    test('and half a turn is exactly the wrong way round', () {
      // The property worth pinning rather than the number: what a model is
      // turned by must send its own forward to the actor's. Mutation: a
      // quarter turn — the dot product comes out nought and this fails, while
      // a test comparing against `pi` would only fail on the constant.
      final actor = _actor();
      final drawn = ActorVisuals.yawFor(actor, model: true);
      // Where the actor is going, and where the model's own +Z ends up.
      final going = Vector3(-math.sin(actor.yaw), 0.0, -math.cos(actor.yaw));
      final faces = Vector3(math.sin(drawn), 0.0, math.cos(drawn));

      expect(going.dot(faces), closeTo(1.0, 1e-9));
    });
  });

  group('an animation ends the way the actor did', () {
    test('a living actor loops', () {
      // Idle, walking and running all have to come round again; a monster that
      // held the last frame of its run would slide down the corridor in a pose.
      expect(ActorVisuals.wrapFor(_actor()), equals(AnimationWrap.loop));
    });

    test('and a dead one holds its final pose', () {
      // Mutation: return `AnimationWrap.loop` unconditionally, which is what
      // the default did and what the bug was — fails here and nowhere else.
      final actor = _actor();
      actor.health!.damage(999.0);

      expect(actor.isAlive, isFalse, reason: 'the fixture must actually die');
      expect(ActorVisuals.wrapFor(actor), equals(AnimationWrap.once));
    });

    test('and it is dying that decides it, not the clip it is playing', () {
      // The name belongs to the export — two of the crypt's three models spell
      // their hit clip differently. Mutation: switch on a clip named 'Death'
      // and this still passes, which is the point: nothing here mentions a
      // clip, so a fourth model whose artist called it `die` is covered too.
      final actor = _actor();
      final alive = ActorVisuals.wrapFor(actor);
      actor.health!.damage(999.0);

      expect(alive, isNot(equals(ActorVisuals.wrapFor(actor))));
    });
  });
}
