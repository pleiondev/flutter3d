/// The entity store every simulation in the engine is built on, and the tool
/// that carries a save across a level that has since been edited.
///
/// Quoted by `ecs_world.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class _Position {
  const _Position(this.x);
  final double x;
}

final class EcsWorldDemo extends ShowcaseDemo {
  late final String _report;
  late final double? _goblinX;
  late final double? _trollX;

  @override
  Scene build(DemoContext context) {
    final (String report, double? goblinX, double? trollX) = _run();
    _report = report;
    _goblinX = goblinX;
    _trollX = trollX;
    final material = Material(
      name: 'entity',
      baseColor: Vector4(0.4, 0.7, 0.9, 1.0),
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
  Widget? customBody(
    BuildContext buildContext,
    DemoContext context,
  ) => Container(
    color: const Color(0xFF14161A),
    padding: const EdgeInsets.all(24),
    alignment: Alignment.topLeft,
    child: DefaultTextStyle(
      style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
      child: Text(
        'Two monsters were saved by name, then a third was inserted ahead of '
        'the troll before the level reloaded.\n\n$_report',
      ),
    ),
  );

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
