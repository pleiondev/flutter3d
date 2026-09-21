/// The entity store every simulation in the engine is built on, and the tool
/// that carries a save across a level that has since been edited.
///
/// Quoted by `ecs_world.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class _Position {
  const _Position(this.x);
  final double x;
}

final class EcsWorldDemo extends ShowcaseDemo {
  late final double? _goblinX;
  late final double? _trollX;

  int reload = 0;
  int _shown = -1;

  late final Map<String, Object?> _saved;
  late final List<MeshNode> _balls;
  late final List<BarGauge> _bars;
  late final List<MeshNode> _pedestals;

  /// The names the reloaded level offers, in slot order, for each choice.
  static const List<List<String?>> _levels = <List<String?>>[
    <String?>['goblin', 'ogre', 'troll'],
    <String?>['troll', 'goblin'],
    <String?>['goblin'],
    <String?>['ogre', 'goblin', 'ogre', 'troll'],
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.55
      ..yaw = 0.2;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    final (String _, double? goblinX, double? trollX) = _run();
    _goblinX = goblinX;
    _trollX = trollX;

    // The saved world, the same two entities `_run` saves.
    final EcsWorld world = _newWorld();
    final Entity goblin = world.spawn();
    final Entity troll = world.spawn();
    world
      ..set(goblin, const _Position(3.0))
      ..set(troll, const _Position(9.0));
    _saved = world.save();

    // Four slots is the most any choice below has: a pedestal, a ball that
    // sits on it and a bar that stands for the number stored there.
    const int slots = 4;
    _pedestals = <MeshNode>[];
    _balls = <MeshNode>[];
    _bars = <BarGauge>[];
    final List<SceneNode> nodes = <SceneNode>[
      floorNode(context, width: 16.0, depth: 8.0),
    ];
    for (var i = 0; i < slots; i++) {
      final double x = (i - (slots - 1) / 2) * 2.6;
      final MeshNode pedestal = blockNode(
        context,
        'slot $i',
        Vector3(1.8, 0.3, 1.8),
        Vector4(0.5, 0.42, 0.34, 1.0),
        at: Vector3(x, 0.15, 0.0),
      );
      final MeshNode ball = ballNode(
        context,
        'entity $i',
        0.5,
        Vector4(0.9, 0.9, 0.9, 1.0),
        at: Vector3(x, 0.8, 0.0),
      );
      final BarGauge bar = BarGauge(
        context,
        'value $i',
        Vector4(0.9, 0.75, 0.3, 1.0),
        Vector3(x, 0.3, 1.8),
        height: 2.5,
        width: 0.4,
        vertical: true,
      );
      _pedestals.add(pedestal);
      _balls.add(ball);
      _bars.add(bar);
      nodes
        ..add(pedestal)
        ..add(ball)
        ..addAll(bar.nodes);
    }
    return sceneOf(nodes);
  }

  EcsWorld _newWorld() => EcsWorld()
    ..register<_Position>(
      'position',
      encode: (_Position p) => p.x,
      decode: (Object? data) => _Position((data! as num).toDouble()),
    );

  /// The position stored in each slot of a level laid out as [names], or null
  /// for a slot nothing was saved into.
  List<double?> _reloadInto(List<String?> names) {
    // #region live
    // The same remap as above, for whichever level is chosen: each saved
    // entity finds its own name in the new layout, wherever that now is.
    final remap = remapEntitySave(
      _saved,
      oldNames: <String?>['goblin', 'troll'],
      newNames: names,
      newGenerations: List<int>.filled(names.length, 0),
      newFree: <int>[],
    );
    final EcsWorld reloaded = _newWorld();
    final List<Entity> ids = <Entity>[
      for (var i = 0; i < names.length; i++) reloaded.spawn(),
    ];
    reloaded.restore(remap.save);
    return <double?>[for (final Entity id in ids) reloaded.get<_Position>(id)?.x];
    // #endregion live
  }

  @override
  void update(DemoContext context, double dt) {
    if (reload == _shown) return;
    _shown = reload;
    final List<String?> names = _levels[reload];
    final List<double?> found = _reloadInto(names);
    for (var i = 0; i < _balls.length; i++) {
      final bool has = i < names.length;
      final double? x = has ? found[i] : null;
      _pedestals[i].visible = has;
      _balls[i].visible = x != null;
      for (final SceneNode n in _bars[i].nodes) {
        n.visible = x != null;
      }
      if (x == null) continue;
      // Whoever held 3 is the goblin and whoever held 9 the troll.
      _balls[i].material.baseColor.setFrom(
        x < 5.0 ? Vector4(0.5, 0.8, 0.35, 1.0) : Vector4(0.85, 0.35, 0.3, 1.0),
      );
      _bars[i].set(x / 9.0);
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'The level reloads as',
      options: const <String>[
        'goblin, ogre, troll',
        'troll, goblin',
        'goblin only',
        'ogre, goblin, ogre, troll',
      ],
      index: () => reload,
      onChanged: (int i) => reload = i,
    ),
  ];

  static (String, double?, double?) _run() {
    // #region world
    final world = EcsWorld()
      ..register<_Position>(
        'position',
        encode: (_Position p) => p.x,
        decode: (Object? data) => _Position((data! as num).toDouble()),
      );
    final goblin = world.spawn();
    final troll = world.spawn();
    world
      ..set(goblin, const _Position(3.0))
      ..set(troll, const _Position(9.0));
    final saved = world.save();
    // #endregion world

    // #region remap
    // The level is reloaded with the goblin's old slot now empty and a third
    // monster ahead of the troll, so the indices EcsWorld would otherwise
    // reuse no longer mean what they meant.
    final remap = remapEntitySave(
      saved,
      oldNames: <String?>['goblin', 'troll'],
      newNames: <String?>['goblin', 'ogre', 'troll'],
      newGenerations: <int>[0, 0, 0],
      newFree: <int>[],
    );
    final reloaded = EcsWorld()
      ..register<_Position>(
        'position',
        encode: (_Position p) => p.x,
        decode: (Object? data) => _Position((data! as num).toDouble()),
      );
    // Three spawns to give the world the same three slots `newNames` describes.
    final ids = <Entity>[for (var i = 0; i < 3; i++) reloaded.spawn()];
    reloaded.restore(remap.save);
    // #endregion remap

    // #region read
    final goblinX = reloaded.get<_Position>(ids[0])?.x;
    final trollX = reloaded.get<_Position>(ids[2])?.x;
    // #endregion read
    return (
      'goblin at x=$goblinX, troll at x=$trollX, dropped: ${remap.dropped}',
      goblinX,
      trollX,
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the entity marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: a double that
    // survives a JSON-shaped map on the way here is not guaranteed the type
    // inference a web backend needs to print it with its trailing `.0`, and
    // a compiled `3` failing a substring match against `'x=3.0'` would be
    // this check catching its own string, not the remap.
    if (_goblinX != 3.0 || _trollX != 9.0) {
      throw StateError('the remap should carry each position to its own name');
    }
  }
}
