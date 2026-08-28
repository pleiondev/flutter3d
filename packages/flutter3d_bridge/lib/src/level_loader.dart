import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import 'loaded_level.dart';

export 'loaded_level.dart';

/// Reads a level asset and turns it into something playable.
///
/// The oldest half of the bridge, and still the clearest statement of what the
/// bridge is for: everything above it is simulation and everything below is
/// rendering, and the whole binding is the interleaving in `_toMeshData` —
/// about twenty lines, which is the price of keeping the two packages
/// independent and worth paying.
///
/// Nothing here knows what game it is loading. A level is brushes, materials,
/// lights and entities; which entity means what is the game's business, and it
/// is settled elsewhere.
/// How a level's own files are found.
///
/// **A level belongs to an application, and it is not always the one running.**
/// A game reads its textures out of its own bundle, which is why this was
/// `rootBundle.load` written into the loader — and an editor opens a document
/// belonging to a *different* application, whose textures are on the disk
/// beside it and in nobody's bundle. Without this the crypt draws in flat grey
/// in the one program whose whole job is to show somebody what their level
/// looks like.
typedef AssetBytes = Future<ByteData> Function(String path);

/// How a level's own document is found.
///
/// The same asymmetry as [AssetBytes], one level up: a game's level document
/// lives in its bundle, and an editor's lives on disk next to the textures
/// [AssetBytes] already lets it reach. Without this, [LevelLoader.load] is
/// only ever the bundle, and anything else has to skip it and call
/// [LevelLoader.build] with a document it decoded itself.
typedef DocumentText = Future<String> Function(String path);

final class LevelLoader {
  const LevelLoader();

  /// [registry] is the game's vocabulary, and it is required for the same
  /// reason `LevelValidator`'s is: this package binds a renderer to a
  /// simulation and has no business deciding what a level may contain. The
  /// loader used to validate against a roster that named torches and this
  /// repository's own monsters.
  ///
  /// [readDocument] finds the level document itself, defaulting to
  /// `rootBundle.loadString` so the games that only ever load their own
  /// bundled levels are unaffected. [readAsset] governs the textures a level
  /// names, and is passed straight through to [build].
  Future<LoadedLevel> load(
    String assetPath, {
    required GraphicsDevice device,
    required EntityRegistry registry,
    List<LevelRule> rules = const <LevelRule>[],
    AssetBytes? readAsset,
    DocumentText? readDocument,
  }) async => build(
    Level.fromJson(
      jsonDecode(await (readDocument ?? rootBundle.loadString)(assetPath))
          as Map<String, Object?>,
    ),
    device: device,
    registry: registry,
    rules: rules,
    readAsset: readAsset,
  );

  /// Everything [load] does except finding the document.
  ///
  /// **The read and the build were one method, and a level had to be an asset
  /// to be drawn at all.** A game only ever has bundled levels, so nothing
  /// noticed — but an editor holds a document it has just changed and has no
  /// asset to point at, and a test that wants to draw a level it built in
  /// memory had the same problem. Splitting them costs one call and gives both.
  Future<LoadedLevel> build(
    Level level, {
    required GraphicsDevice device,
    required EntityRegistry registry,
    List<LevelRule> rules = const <LevelRule>[],
    AssetBytes? readAsset,
  }) async {
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
    // **A map that will not load is now a warning rather than a line in a
    // console.** `LoadedLevel` has carried `issues` since the validator did,
    // and this is the same kind of fact: the level plays, a wall is flat, and
    // the person who renamed the file is the one who wants to hear about it.
    final loadIssues = <LevelIssue>[];
    for (final source in level.materials.values) {
      for (final path in <String?>[source.albedo, source.normal, source.orm]) {
        if (path == null || textures.containsKey(path)) continue;
        textures[path] = await _upload(
          device,
          path,
          readAsset ?? rootBundle.load,
          loadIssues,
        );
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
      issues: <LevelIssue>[...validator.validate(level), ...loadIssues],
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
    AssetBytes read,
    List<LevelIssue> issues,
  ) async {
    try {
      final bytes = await read(path);
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
      // level. Losing a wall texture should not cost the play-test — but it is
      // said out loud now, because a flat wall and a wall that is meant to be
      // flat look the same, and the difference is a file somebody renamed.
      issues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'could not be loaded, so the surface is untextured: $error',
          where: 'texture "$path"',
        ),
      );
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
