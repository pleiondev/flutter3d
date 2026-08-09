import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// A loaded level, in the two forms the game needs it.
///
/// One authored document produces both, which is the point: geometry the player
/// can see and geometry the player can walk into are generated from the same
/// brushes, so they cannot drift apart. Deriving colliders from the rendered
/// triangles instead would work until the first time somebody added a visual
/// detail and made it solid by accident.
final class LoadedLevel {
  LoadedLevel({
    required this.level,
    required this.scene,
    required this.collision,
    required this.issues,
    required this.drawCallCount,
  });

  final Level level;
  final Scene scene;
  final CollisionWorld collision;

  /// What the validator said. Errors stop the load before this exists, so
  /// anything here is a warning worth showing rather than acting on.
  final List<LevelIssue> issues;

  /// One per material, which is what the brush geometry merges down to.
  final int drawCallCount;
}

/// Reads a level asset and turns it into something playable.
///
/// The only place `flutter3d` and `flutter3d_game` meet. Everything above it is
/// simulation and everything below is rendering, and the whole bridge is the
/// interleaving in [_toMeshData] — about twenty lines, which is the price of
/// keeping the two packages independent and worth paying.
final class LevelLoader {
  const LevelLoader();

  Future<LoadedLevel> load(String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    final level = Level.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );

    // Errors throw with every one listed, because a level with a door whose key
    // is in no room is a level that cannot be finished, and finding that out
    // twenty minutes in is worse than not starting.
    const validator = LevelValidator();
    validator.assertValid(level);

    final scene = Scene();
    final collision = CollisionWorld();
    level.addTo(collision);

    final surfaces = const BrushGeometry().build(level);
    for (final surface in surfaces) {
      final source = level.materials[surface.material] ?? LevelMaterial();
      scene.add(
        MeshNode(
          GpuMesh.upload(_toMeshData(surface)),
          Material(
            name: surface.material,
            baseColor: source.baseColor,
            roughness: source.roughness,
            metallic: source.metallic,
          ),
          name: surface.material,
        ),
      );
    }

    for (final light in level.lights) {
      scene.add(_toLightNode(light));
    }

    return LoadedLevel(
      level: level,
      scene: scene,
      collision: collision,
      issues: validator.validate(level),
      drawCallCount: surfaces.length,
    );
  }

  /// Interleaves the level package's plain arrays into the engine's layout.
  ///
  /// The level package deliberately does not know what a vertex layout is, so
  /// the two halves meet here and nowhere else.
  ///
  /// It has to be [VertexLayout.standard] and not a shorter one. flutter_gpu
  /// takes the layout from the vertex shader's `in` declarations, and
  /// `mesh.vert` declares position, normal, texcoord, tangent **and** colour —
  /// sixteen floats. Supplying eight does not fail: the GPU keeps reading at
  /// the stride the shader expects and assembles each vertex from two of the
  /// ones actually written, which draws a convincing field of garbage
  /// triangles and no error anywhere.
  static MeshData _toMeshData(BrushSurface surface) {
    const layout = VertexLayout.standard;
    final stride = layout.floatsPerVertex;
    final vertices = Float32List(surface.vertexCount * stride);

    for (var i = 0; i < surface.vertexCount; i++) {
      final out = i * stride;
      vertices[out] = surface.positions[i * 3];
      vertices[out + 1] = surface.positions[i * 3 + 1];
      vertices[out + 2] = surface.positions[i * 3 + 2];
      vertices[out + 3] = surface.normals[i * 3];
      vertices[out + 4] = surface.normals[i * 3 + 1];
      vertices[out + 5] = surface.normals[i * 3 + 2];
      vertices[out + 6] = surface.texcoords[i * 2];
      vertices[out + 7] = surface.texcoords[i * 2 + 1];
      vertices[out + 8] = surface.tangents[i * 4];
      vertices[out + 9] = surface.tangents[i * 4 + 1];
      vertices[out + 10] = surface.tangents[i * 4 + 2];
      vertices[out + 11] = surface.tangents[i * 4 + 3];
      // Vertex colour multiplies the material's, so white leaves it alone.
      vertices[out + 12] = 1.0;
      vertices[out + 13] = 1.0;
      vertices[out + 14] = 1.0;
      vertices[out + 15] = 1.0;
    }

    return MeshData(
      layout: layout,
      vertices: vertices,
      indices: surface.indices,
    );
  }

  static LightNode _toLightNode(LevelLight light) {
    final node = LightNode(
      type: switch (light.type) {
        LevelLightType.directional => LightType.directional,
        LevelLightType.point => LightType.point,
        LevelLightType.spot => LightType.spot,
      },
      color: light.color,
      intensity: light.intensity,
      range: light.range,
      name: light.name,
    )..setPositionFrom(light.position);

    if (light.type != LevelLightType.point) {
      // A light aims along its node's local -Z, the same forward axis a camera
      // uses, so it is pointed rather than given a vector.
      node.lookAt(light.position + light.direction);
    }
    return node;
  }
}
