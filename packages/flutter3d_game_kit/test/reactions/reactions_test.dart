/// Reactions: a table keyed by event type, the plugin that hears it on the
/// bus's frame channel, the camera's three verbs and the fading flash.
///
///     flutter test test/reactions_test.dart
///
/// Each test was written against the mutation named in it: the change to the
/// package that would let it pass while the package was wrong.
library;

import 'package:flutter3d_camera/flutter3d_camera.dart' show CameraRig;
import 'package:flutter3d_game_kit/reactions.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Landed extends BusEvent {
  const _Landed(this.at, {this.hard = false});

  final Vector3 at;
  final bool hard;

  /// A step event is declared with its codec.
  static final EventCodec<_Landed> codec = EventCodec<_Landed>.of(
    encode: (event) => <Object?>[
      event.at.x,
      event.at.y,
      event.at.z,
      event.hard,
    ],
    decode: (data, _) => switch (data) {
      [final num x, final num y, final num z, final bool hard] => _Landed(
        Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
        hard: hard,
      ),
      _ => null,
    },
  );

  @override
  String get name => 'test.landed';
}

final class _Blast extends BusEvent {
  const _Blast(this.at);

  final Vector3 at;

  @override
  String get name => 'test.blast';
}

final class _Quiet extends BusEvent {
  const _Quiet();

  @override
  String get name => 'test.quiet';
}

final ParticleEffect _dust = ParticleEffect(
  count: 4,
  emitter: const SphereEmitter(speed: Range.exact(0.0)),
  lifetime: const Range.exact(0.5),
  size: const Range.exact(0.1),
  color: Vector4(1.0, 1.0, 1.0, 1.0),
);

ReactionTable _table() => ReactionTable()
  ..on<_Landed>((e, out) {
    out.bursts.add(Shown(_dust, e.at));
    if (e.hard) out.jolts.add(Felt.kick(Vector3(0.0, -0.2, 0.0)));
  })
  ..on<_Blast>((e, out) {
    out.flash = true;
    out.lingering.add(
      Lingering(Object(), _dust, e.at, perSecond: 30.0, seconds: 0.8),
    );
    out.haptics.add(Haptic.heavy);
  });

void main() {
  test('a table hands each event to the rules for its type, in order', () {
    // Mutation: run every rule on every event without the type check. The
    // landing's dust would come out of the blast too.
    final reaction = _table().react(<BusEvent>[
      _Landed(Vector3(1.0, 0.0, 0.0)),
      _Blast(Vector3(2.0, 0.0, 0.0)),
      _Landed(Vector3(3.0, 0.0, 0.0), hard: true),
      const _Quiet(),
    ]);
    expect(reaction.bursts.map((s) => s.at.x), <double>[1.0, 3.0]);
    expect(reaction.lingering.single.at.x, 2.0);
    expect(reaction.jolts.single.jolt, Jolt.kick);
    expect(reaction.haptics, <Haptic>[Haptic.heavy]);
    expect(reaction.flash, isTrue);
  });

  test('an event nobody named shows nothing', () {
    // Mutation: make `Reaction.isEmpty` ignore the flash. A step that only
    // flashed would read as a step that did nothing.
    expect(_table().react(const <BusEvent>[_Quiet()]).isEmpty, isTrue);
    expect(Reaction.none.isEmpty, isTrue);
    expect(const Reaction(flash: true).isEmpty, isFalse);
    expect(_table().types, <Type>[_Landed, _Blast]);
  });

  test('a felt jolt is performed on the camera rig, by its verb', () {
    // Mutation: apply a shake as a widening. The view would breathe where it
    // should rattle.
    final kicked = CameraRig(world: CollisionWorld());
    Felt.kick(Vector3(0.0, -1.0, 0.0)).applyTo(kicked);
    final widened = CameraRig(world: CollisionWorld());
    const Felt.widen(0.2).applyTo(widened);
    expect(widened.extraFovY, greaterThan(0.0));
    expect(kicked.extraFovY, 0.0);

    final shaken = CameraRig(world: CollisionWorld());
    const Felt.shake(0.5, seconds: 0.4).applyTo(shaken);
    expect(shaken.extraFovY, 0.0, reason: 'a shake is not a widening');
    expect(const Felt.shake(0.5).jolt, Jolt.shake);
    expect(Jolt.widen.toString(), 'widen');
  });

  test('a reaction bursts and lingers into a particle system', () {
    // Mutation: drop the lingering half of `showIn`. A blast's smoke would
    // never start.
    final particles = ParticleSystem(seed: 1);
    _table()
        .react(<BusEvent>[_Blast(Vector3.zero()), _Landed(Vector3.zero())])
        .showIn(particles);
    expect(particles.aliveCount, greaterThan(0));
  });

  test('the flash fades at its own rate, from the player\'s amount', () {
    // Mutation: fade by the frame rather than by `dt`. A flash would last
    // half as long at 120 Hz.
    final flash = ScreenFlash(fadePerSecond: 4.0)..fire(0.8);
    expect(flash.value, 0.8);
    flash.fade(0.1);
    expect(flash.value, closeTo(0.4, 1e-9));
    flash.fade(1.0);
    expect(flash.value, 0.0);
    flash
      ..fire(0.0)
      ..fade(0.1);
    expect(flash.value, 0.0, reason: 'a player who turned flashes off');
  });

  test('the plugin hears the frame channel and hands each event out once', () {
    // Mutation: subscribe on the step channel. The plugin would be refused as
    // a view plugin, or run again inside a rollback.
    final reactions = ReactionsPlugin(_table());
    expect(reactions.manifest.touches, PluginTouches.view);
    expect(reactions.manifest.idProblem, isNull);

    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[reactions],
    );
    loop.events.declare<_Landed>('test.landed', codec: _Landed.codec);
    var published = false;
    loop.addSystem('land once', LoopPhase.rules, (c) {
      if (published) return;
      published = true;
      c.publish(_Landed(Vector3(5.0, 0.0, 0.0), hard: true));
    });
    loop.frame(1.0 / 60.0);

    final first = reactions.drain();
    expect(first.bursts.single.at.x, 5.0);
    expect(first.jolts.single.jolt, Jolt.kick);
    // Mutation: forget to clear in `take`. The landing would burst every
    // frame from then on.
    loop.frame(1.0 / 60.0);
    expect(reactions.drain().isEmpty, isTrue);
  });
}
