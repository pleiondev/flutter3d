/// Who a collider is, and the components that make an actor: health that can
/// run out, and a brain that has memory of its own.
///
/// Quoted by `actors.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region brain
/// A brain with one bit of memory: whether it has ever been hurt.
final class _WaryBrain extends Brain {
  bool everHurt = false;

  @override
  void onHurt(Mind it, double amount) => everHurt = true;

  @override
  Map<String, Object?> save() => <String, Object?>{'everHurt': everHurt};

  @override
  void restore(Map<String, Object?> from) =>
      everHurt = from['everHurt'] == true;
}
// #endregion brain

final class ActorsDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'goblin',
      baseColor: Vector4(0.5, 0.7, 0.3, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static String _run() {
    // #region actor
    final entities = EcsWorld();
    final entity = entities.spawn();
    entities
      ..set(entity, Vitality(Health(30.0)))
      ..set(entity, Thinking(_WaryBrain()));
    final goblin = Actor(entities, entity, name: 'goblin');
    // #endregion actor

    final aliveBefore = goblin.isAlive;

    // #region hurt
    final brain = goblin.brain! as _WaryBrain;
    goblin.applyDamage(12.0);
    brain.onHurt(Mind(_stubSystem()), 12.0);
    final currentHealth = goblin.health!.current;
    // #endregion hurt

    return 'a fresh goblin is alive: $aliveBefore, has ${goblin.health!.current} '
        'health of ${goblin.health!.maximum}\n'
        'after twelve damage: $currentHealth health, still alive: '
        '${goblin.isAlive}, its brain remembers being hurt: ${brain.everHurt}';
  }

  /// A real `ActorSystem` needs a live level; `Brain.onHurt` only needs a
  /// `Mind`, and a `Mind` only needs a system to ask `focus` of, which this
  /// page never calls. A throwaway system is enough to build one.
  static ActorSystem _stubSystem() =>
      ActorSystem(world: CollisionWorld(), random: GameRandom(1));

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the goblin marker was not drawn');
    }
    if (!_report.contains('18.0 health') ||
        !_report.contains('still alive: true')) {
      throw StateError(
        'twelve damage on thirty health should leave the '
        'goblin alive at eighteen',
      );
    }
    if (!_report.contains('remembers being hurt: true')) {
      throw StateError('the brain should remember being hurt');
    }
  }
}
