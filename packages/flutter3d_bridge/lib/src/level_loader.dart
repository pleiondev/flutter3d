import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
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
    Map<String, TextureHandle?>? materialTextures,
  }) : materialTextures = materialTextures ?? const <String, TextureHandle?>{};

  final Level level;
  final Scene scene;
  final CollisionWorld collision;

  /// What the validator said. Errors stop the load before this exists, so
  /// anything here is a warning worth showing rather than acting on.
  final List<LevelIssue> issues;

  /// One per material, which is what the brush geometry merges down to.
  final int drawCallCount;

  /// Every map this level loaded, by asset path.
  ///
  /// Kept so anything built after the load — a door, a lift — can be given the
  /// same texture object rather than uploading a second copy of the same file.
  final Map<String, TextureHandle?> materialTextures;
}

/// Reads a level asset and turns it into something playable.
///
/// The oldest half of the bridge, and still the clearest statement of what the
/// bridge is for: everything above it is simulation and everything below is
/// rendering, and the whole binding is the interleaving in [_toMeshData] —
/// about twenty lines, which is the price of keeping the two packages
/// independent and worth paying.
///
/// Nothing here knows what game it is loading. A level is brushes, materials,
/// lights and entities; which entity means what is the game's business, and it
/// is settled elsewhere.
final class LevelLoader {
  const LevelLoader();

  /// [registry] is the game's vocabulary, and it is required for the same
  /// reason `LevelValidator`'s is: this package binds a renderer to a
  /// simulation and has no business deciding what a level may contain. The
  /// loader used to validate against a roster that named torches and this
  /// repository's own monsters.
  Future<LoadedLevel> load(
    String assetPath, {
    required GraphicsDevice device,
    required EntityRegistry registry,
    List<LevelRule> rules = const <LevelRule>[],
  }) async {
    final text = await rootBundle.loadString(assetPath);
    final level = Level.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );

    // Errors throw with every one listed, because a level with a door whose key
    // is in no room is a level that cannot be finished, and finding that out
    // twenty minutes in is worse than not starting.
    final validator = LevelValidator(registry: registry, rules: rules);
    validator.assertValid(level);

    final scene = Scene();
    final collision = CollisionWorld();
    level.addTo(collision);

    // Every map the level names, loaded once and shared. A wall texture used
    // by four surfaces is one upload, not four — and the cache belongs to this
    // load rather than to the process, so two levels never share a GPU
    // resource that one of them will outlive.
    final textures = <String, TextureHandle?>{};
    for (final source in level.materials.values) {
      for (final path in <String?>[source.albedo, source.normal, source.orm]) {
        if (path == null || textures.containsKey(path)) continue;
        textures[path] = await _upload(device, path);
      }
    }

    final surfaces = const BrushGeometry().build(level);
    for (final surface in surfaces) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(device, _toMeshData(surface)),
          LevelLoader.materialFrom(
            level.materials[surface.material] ?? LevelMaterial(),
            textures,
            name: surface.material,
          ),
          name: surface.material,
        )
          // Brushes are the level: they never move, so their shadow is baked
          // once rather than redrawn six times a frame.
          ..shadowIsStatic = true
          // A fence is not architecture. See `Brush.castsShadow` — and note
          // that this is why surfaces are batched by that answer as well as by
          // material: a batch is the smallest thing that can be left out.
          ..castsShadow = surface.castsShadow,
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
      materialTextures: textures,
    );
  }

  /// Builds an engine material from a level material and the loaded maps.
  ///
  /// A free function rather than a method on either type: [LevelMaterial] lives
  /// in the game package, which must not know that textures exist, and
  /// [Material] lives in the renderer, which must not know that levels do. This
  /// is the seam, and it is the only place that knows both.
  static Material materialFrom(
    LevelMaterial source,
    Map<String, TextureHandle?> textures, {
    String? name,
  }) {
    final material = Material(
      name: name,
      baseColor: source.baseColor,
      roughness: source.roughness,
      metallic: source.metallic,
    );
    if (!source.hasMaps) return material;

    material
      ..albedo = textures[source.albedo]
      ..normal = textures[source.normal]
      // The same image in both slots. glTF packs occlusion, roughness and
      // metallic into one texture; the renderer reads red from the occlusion
      // slot and green and blue from the metallic-roughness slot, so binding
      // it twice is not waste — it is what the two slots are for.
      ..metallicRoughness = textures[source.orm]
      ..occlusion = textures[source.orm]
      ..albedoSampler = _tiling
      ..normalSampler = _tiling
      ..metallicRoughnessSampler = _tiling
      ..occlusionSampler = _tiling;
    return material;
  }

  static Future<TextureHandle?> _upload(
    GraphicsDevice device,
    String path,
  ) async {
    try {
      final bytes = await rootBundle.load(path);
      // Mipmapped: a level's walls and floors are the surfaces most often seen
      // small and at a glancing angle, which is exactly where a single level
      // crawls as the camera moves.
      return await uploadEncodedImage(
        device,
        bytes.buffer.asUint8List(),
        sampling: const TextureSampling(),
      );
    } catch (error) {
      // A missing texture leaves the material flat rather than stopping the
      // level. Losing a wall texture should not cost the play-test.
      debugPrint('level: could not load "$path": $error');
      return null;
    }
  }

  /// Repeat, not clamp.
  ///
  /// A wall fourteen metres wide at half a metre per tile has texture
  /// coordinates running from zero to twenty-eight, and clamping would stretch
  /// the atlas's last texel across the whole thing.
  /// Trilinear, so the chain built at upload is blended rather than merely
  /// allocated: with `MipFilter.nearest` — the default — the levels are there
  /// and the picture is the one that has no levels at all.
  static const SamplerOptions _tiling = SamplerOptions.trilinearRepeat;

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
      // The second place this flag was dropped. It travels from the document
      // to LevelLight and stopped here, so a light marked as a caster in the
      // level has never been one in the scene.
      castsShadow: light.castsShadow,
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
