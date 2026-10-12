/// A level as the playground draws it: the level's own scene, a marker for
/// every entity, and a sun when the level brought no light.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_level_scene/flutter3d_level_scene.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// [level] on [device]. **Entities are drawn as markers**, a small box each,
/// coloured by type: what an entity looks like is a game's vocabulary, and
/// the playground has none, so it shows where they are and how many.
Scene playgroundScene(Level level, GraphicsDevice device) {
  final parts = const LevelScene().build(level, device: device);
  final scene = parts.scene;
  if (level.entities.isNotEmpty) {
    final marker = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(0.4)).build(),
    );
    final materials = <String, RenderMaterial>{};
    for (final entity in level.entities) {
      scene.add(
        MeshNode(
          marker,
          materials.putIfAbsent(
            entity.type,
            () => RenderMaterial(
              name: entity.type,
              baseColor: markerColor(entity.type),
              roughness: 0.5,
            ),
          ),
          name: entity.name ?? entity.type,
        )..setPosition(
          entity.position.x,
          entity.position.y + 0.2,
          entity.position.z,
        ),
      );
    }
  }
  if (parts.lights.isEmpty) {
    scene.add(
      LightNode(name: 'sun', intensity: 3.0 * LightNode.defaultIntensity)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );
  }
  return scene;
}

/// One colour per entity type, the same on every visit: a hue from the
/// type's characters, at a brightness that reads on the dark background.
LinearColor markerColor(String type) {
  final hue = type.codeUnits.fold(7, (int h, int c) => (h * 31 + c) % 360);
  final (r, g, b) = _hueToRgb(hue / 360.0);
  return LinearColor.fromSrgb(r, g, b, 1.0);
}

(double, double, double) _hueToRgb(double hue) {
  double channel(double offset) {
    final t = (hue + offset) % 1.0;
    final v = (t * 6.0 - 3.0).abs() - 1.0;
    return 0.25 + 0.65 * v.clamp(0.0, 1.0);
  }

  return (channel(0.0), channel(2.0 / 3.0), channel(1.0 / 3.0));
}
