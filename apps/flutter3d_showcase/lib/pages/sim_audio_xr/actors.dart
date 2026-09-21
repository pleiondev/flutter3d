/// Who a collider is, and the components that make an actor: health that can
/// run out, and a brain that has memory of its own.
///
/// Quoted by `actors.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

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
  late final double _currentHealth;
  late final bool _stillAlive;
  late final bool _rememberedBeingHurt;

  late final Actor _goblin;
  late final _WaryBrain _brain;
  late final MeshNode _body;
  late final MeshNode _bar;
  late final Material _skin;
  double _hitAsked = 0.0;
  bool _resetAsked = false;
  double _flash = 0.0;

  static const double _barWidth = 1.4;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.2
      ..pitch = 0.25
      ..yaw = 0.4;
    context.orbit.target.setValues(0.0, 0.6, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    final (
      String _,
      double currentHealth,
      bool stillAlive,
      bool rememberedBeingHurt,
    ) = _run();
    _currentHealth = currentHealth;
    _stillAlive = stillAlive;
    _rememberedBeingHurt = rememberedBeingHurt;

    _spawn();
    _skin = Material(name: 'goblin', baseColor: _healthy);
    _body = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 24).build()),
      _skin,
      name: 'goblin',
    );
    MeshNode block(String name, Vector3 size, Vector4 color) => MeshNode(
      DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
      Material(name: name, baseColor: color),
      name: name,
    );
    _bar = block('health', Vector3(_barWidth, 0.14, 0.14), Vector4(0.3, 0.8, 0.3, 1.0));
    return Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        block('floor', Vector3(6.0, 0.1, 6.0), Vector4(0.36, 0.4, 0.38, 1.0))
          ..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        block('bar back', Vector3(_barWidth + 0.08, 0.2, 0.1), Vector4(0.1, 0.1, 0.12, 1.0))
          ..setPosition(0.0, 1.5, -0.02),
      )
      ..add(_body)
      ..add(_bar)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static Vector4 get _healthy => Vector4(0.5, 0.7, 0.3, 1.0);
  static Vector4 get _wary => Vector4(0.85, 0.6, 0.25, 1.0);

  /// The goblin of the page, built the way the first step builds one.
  void _spawn() {
    // #region live
    final EcsWorld entities = EcsWorld();
    final entity = entities.spawn();
    _brain = _WaryBrain();
    entities
      ..set(entity, Vitality(Health(30.0)))
      ..set(entity, Thinking(_brain));
    _goblin = Actor(entities, entity, name: 'goblin');
    // #endregion live
  }

  @override
  void update(DemoContext context, double dt) {
    if (_resetAsked) {
      _resetAsked = false;
      _spawn();
      _flash = 0.0;
    }
    if (_hitAsked > 0.0) {
      // #region hit
      // The damage goes through `Health`; the brain hears of it separately.
      _goblin.applyDamage(_hitAsked);
      _brain.onHurt(Mind(_stubSystem()), _hitAsked);
      // #endregion hit
      _hitAsked = 0.0;
      _flash = 1.0;
    }
    _flash = math.max(0.0, _flash - dt * 3.0);

    final double fraction =
        (_goblin.health!.current / _goblin.health!.maximum).clamp(0.0, 1.0);
    // The bar shrinks towards its left end, and goes red as it does.
    _bar
      ..setScale(math.max(fraction, 0.001), 1.0, 1.0)
      ..setPosition(-(1.0 - fraction) * _barWidth / 2, 1.5, 0.05);
    _bar.material.baseColor.setValues(1.0 - fraction * 0.7, 0.2 + 0.6 * fraction, 0.2, 1.0);

    if (_goblin.isAlive) {
      // A hit squashes it, and a goblin that has been hurt stays wary.
      final double squash = 1.0 - 0.25 * _flash;
      _body
        ..setScale(1.0 + 0.2 * _flash, squash, 1.0 + 0.2 * _flash)
        ..setPosition(0.0, 0.5 * squash, 0.0);
      _skin.baseColor.setFrom(_brain.everHurt ? _wary : _healthy);
    } else {
      // Dead: flat on the floor and grey.
      _body
        ..setScale(1.2, 0.2, 1.2)
        ..setPosition(0.0, 0.1, 0.0);
      _skin.baseColor.setValues(0.35, 0.35, 0.37, 1.0);
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Hit it for 12',
      value: () => false,
      onChanged: (bool v) {
        if (v) _hitAsked = 12.0;
      },
    ),
    ToggleControl(
      'A fresh goblin',
      value: () => false,
      onChanged: (bool v) {
        if (v) _resetAsked = true;
      },
    ),
  ];

  static (String, double, bool, bool) _run() {
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

    final report =
        'a fresh goblin is alive: $aliveBefore, has ${goblin.health!.current} '
        'health of ${goblin.health!.maximum}\n'
        'after twelve damage: $currentHealth health, still alive: '
        '${goblin.isAlive}, its brain remembers being hurt: ${brain.everHurt}';
    return (report, currentHealth, goblin.isAlive, brain.everHurt);
  }

  /// A real `ActorSystem` needs a live level; `Brain.onHurt` only needs a
  /// `Mind`, and a `Mind` only needs a system to ask `focus` of, which this
  /// page never calls. A throwaway system is enough to build one.
  static ActorSystem _stubSystem() =>
      ActorSystem(world: CollisionWorld(), random: GameRandom(1));

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the goblin marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: a whole-number
    // double loses its trailing `.0` when a web backend formats it, and a
    // compiled `18` failing a substring match against `'18.0 health'` would
    // be this check catching its own string, not the damage arithmetic.
    if (_currentHealth != 18.0 || !_stillAlive) {
      throw StateError(
        'twelve damage on thirty health should leave the '
        'goblin alive at eighteen',
      );
    }
    if (!_rememberedBeingHurt) {
      throw StateError('the brain should remember being hurt');
    }
  }
}
