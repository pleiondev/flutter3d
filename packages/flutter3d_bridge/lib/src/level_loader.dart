import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'loaded_level.dart';
import 'visibility_culler.dart';

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
/// Takes the engine's [AssetRequest] rather than a bare path, and takes the
/// engine's rather than one of its own: a game reading a texture and a decoder
/// reading a sibling file are the same question asked one level apart, and two
/// request types would be two places to add the same field to.
typedef AssetBytes = Future<ByteData> Function(AssetRequest request);

/// How a level's own document is found.
///
/// The same asymmetry as [AssetBytes], one level up: a game's level document
/// lives in its bundle, and an editor's lives on disk next to the textures
/// [AssetBytes] already lets it reach. Without this, [LevelLoader.load] is
/// only ever the bundle, and anything else has to skip it and call
/// [LevelLoader.build] with a document it decoded itself.
typedef DocumentText = Future<String> Function(AssetRequest request);

/// The Flutter asset bundle as a [DocumentText]. The default when a caller
/// names none — an adapter rather than `rootBundle.loadString` directly,
/// because the callback carries a request now and the bundle takes a string.
Future<String> _bundleDocument(AssetRequest request) =>
    rootBundle.loadString(request.uri);

/// The Flutter asset bundle as an [AssetBytes]. See [_bundleDocument].
Future<ByteData> _bundleAsset(AssetRequest request) =>
    rootBundle.load(request.uri);

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
  }) async {
    final read = readDocument ?? _bundleDocument;
    final level = Level.fromJson(
      jsonDecode(await read(AssetRequest(assetPath))) as Map<String, Object?>,
    );
    final (visibility, issue) = await _sidecarVisibility(assetPath, read);
    final (lightmap, lightmapIssue) = await _sidecarLightmap(
      assetPath,
      readAsset ?? _bundleAsset,
    );
    return build(
      level,
      device: device,
      registry: registry,
      rules: rules,
      readAsset: readAsset,
      visibility: visibility,
      lightmap: lightmap,
      issues: <LevelIssue>[?issue, ?lightmapIssue],
    );
  }

  /// The lightmap beside a level, or null when there is none — and a word
  /// when there is one that will not read.
  ///
  /// `<level>.lightmap.bin`, baked by `dart run flutter3d_sim:bake_lightmap`.
  /// The same contract as the visibility sidecar: absent is a level without
  /// one, unreadable is said out loud and the level plays without it.
  static Future<(Lightmap?, LevelIssue?)> _sidecarLightmap(
    String assetPath,
    AssetBytes read,
  ) async {
    final path = assetPath.endsWith('.json')
        ? '${assetPath.substring(0, assetPath.length - 5)}.lightmap.bin'
        : '$assetPath.lightmap.bin';
    final ByteData bytes;
    try {
      bytes = await read(AssetRequest(path));
    } catch (_) {
      return (null, null);
    }
    try {
      return (Lightmap.fromBytes(bytes.buffer.asUint8List()), null);
    } catch (error) {
      return (
        null,
        LevelIssue(
          LevelIssueSeverity.warning,
          'the lightmap beside the level could not be read and is ignored: '
          '$error',
          where: path,
        ),
      );
    }
  }

  /// The visibility table beside a level, or null when there is none — and
  /// a word when there is one that will not read.
  ///
  /// `<level>.visibility.json`, baked by `dart run flutter3d_sim:bake_visibility`
  /// and kept beside the document because the document is generated and the
  /// table would not survive its regeneration. A missing sidecar is a level
  /// without one — every level had none until now — and a sidecar that will
  /// not read is said out loud through the issues rather than swallowed,
  /// since the level plays either way and the person who wrote a table that
  /// does not parse is the one who wants to hear it.
  static Future<(LevelVisibility?, LevelIssue?)> _sidecarVisibility(
    String assetPath,
    DocumentText read,
  ) async {
    final path = assetPath.endsWith('.json')
        ? '${assetPath.substring(0, assetPath.length - 5)}.visibility.json'
        : '$assetPath.visibility.json';
    final String text;
    try {
      text = await read(AssetRequest(path));
    } catch (_) {
      return (null, null);
    }
    try {
      return (
        LevelVisibility.fromJson(jsonDecode(text) as Map<String, Object?>),
        null,
      );
    } catch (error) {
      return (
        null,
        LevelIssue(
          LevelIssueSeverity.warning,
          'the visibility table beside the level could not be read and is '
          'ignored: $error',
          where: path,
        ),
      );
    }
  }

  /// The engine's shadow mode for the one a level document asked for.
  ///
  /// **Case by case rather than by name**, though the four words are spelled
  /// the same on both sides: `flutter3d_sim` may not import the engine, so the
  /// two enums are two enums, and a `switch` with no default is the thing that
  /// makes the compiler point at this line the day either of them grows a
  /// fifth answer. Matching on `name` would compile and quietly fall back.
  static ShadowCastingMode shadowModeOf(ShadowCasting casting) =>
      switch (casting) {
        ShadowCasting.on => ShadowCastingMode.on,
        ShadowCasting.off => ShadowCastingMode.off,
        ShadowCasting.doubleSided => ShadowCastingMode.doubleSided,
        ShadowCasting.shadowsOnly => ShadowCastingMode.shadowsOnly,
      };

  /// Draws the level's walls again from [brushes], which are no longer the
  /// document's — a blast has cut some of them.
  ///
  /// Every batch is rebuilt rather than the ones a hole touched, because a
  /// batch is a material's worth of the whole level, or a cell's worth when
  /// there was a visibility table, and a hole is in one of them either way;
  /// finding which would cost more thought than the crypt's eleven batches
  /// cost to build. The visibility table is dropped with the old batches:
  /// it was baked from walls without holes in them, and a hole is a line of
  /// sight it does not know about. Textures are the ones the level loaded
  /// with, so nothing is fetched.
  ///
  /// **The baked light is not dropped with them, and [origins] is the price.**
  /// A rebuild without it hands every vertex the neutral texel, so one rocket
  /// into one wall takes the bake off every wall in the level — in the crypt,
  /// the light in every room changing at once because a corridor lost a metre
  /// of stone. The layout cannot simply be passed through: it is keyed by
  /// *brush index*, and a breach puts up to six pieces where one brush was, so
  /// every index past the hole shifts and the surviving faces would read
  /// somebody else's texels. `Breaches.origins` is the way back — which brush
  /// each piece was cut out of — and `BrushGeometry.build` measures each
  /// piece's face inside the planned face it is part of. Without [origins] the
  /// rebuild is what it was: no lightmap, flat ambient, level-wide.
  void rebuildBrushes(
    LoadedLevel loaded, {
    required GraphicsDevice device,
    required List<Brush> brushes,
    List<int>? origins,
  }) {
    for (final node in loaded.brushNodes) {
      node.removeFromParent();
    }
    loaded.brushNodes.clear();
    for (final mesh in loaded.brushMeshes) {
      device.releaseGeometry(mesh.vertices);
      device.releaseGeometry(mesh.indices);
    }
    loaded.culler?.showAll();
    loaded.culler = null;

    final level = loaded.level;
    final cut = Level(
      name: level.name,
      brushes: brushes,
      materials: level.materials,
    );
    // The atlas the level loaded with, and only when there are origins to find
    // a piece's place in it. A layout with no way back to the authored brushes
    // is worse than none: every face past the hole would sample a stranger's
    // texels, which reads as scrambled light rather than as a missing bake.
    final lightmapTexture = loaded.lightmap;
    final layout = origins == null ? null : loaded.lightmapLayout;
    final surfaces = const BrushGeometry().build(
      cut,
      lightmap: lightmapTexture == null ? null : layout,
      origins: origins,
    );
    final tiling = tilingSamplerFor(device);
    final meshes = <DeviceMesh>[];
    for (final surface in surfaces) {
      final mesh = DeviceMesh.upload(device, _toMeshData(surface));
      meshes.add(mesh);
      final node =
          MeshNode(
              mesh,
              materialFrom(
                  level.materials[surface.material] ?? LevelMaterial(),
                  loaded.materialTextures,
                  name: surface.material,
                  tiling: tiling,
                )
                ..lightmap = surface.lightmapUvs == null
                    ? null
                    : lightmapTexture,
              name: surface.material,
            )
            ..lightmapped = surface.lightmapUvs != null
            ..shadowIsStatic = true
            ..shadowCasting = shadowModeOf(surface.shadowCasting);
      loaded.scene.add(node);
      loaded.brushNodes.add(node);
    }
    loaded.brushMeshes = meshes;
    // The static half of the point shadows was drawn from walls that are no
    // longer there; without this a hole keeps casting the wall's shadow.
    loaded.scene.invalidateStaticShadows();
    // And so were the probes: a kept probe holds the wall the rocket went
    // through. Redrawn with every batch showing, since the culler went with
    // the old batches above.
    for (final probe in loaded.probes) {
      probe.invalidate();
    }
  }

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
    LevelVisibility? visibility,
    Lightmap? lightmap,
    List<LevelIssue> issues = const <LevelIssue>[],
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
    final loadIssues = <LevelIssue>[...issues];
    for (final source in level.materials.values) {
      for (final path in <String?>[source.albedo, source.normal, source.orm]) {
        if (path == null || textures.containsKey(path)) continue;
        textures[path] = await _upload(
          device,
          path,
          readAsset ?? _bundleAsset,
          loadIssues,
        );
      }
    }

    // A table baked from other brushes describes other walls. Refused with a
    // word rather than applied: a stale table hides rooms that are there.
    if (visibility != null && visibility.isStaleFor(level)) {
      loadIssues.add(
        const LevelIssue(
          LevelIssueSeverity.warning,
          'the visibility table was baked from different brushes and is '
          'ignored; run bake_visibility again',
        ),
      );
      visibility = null;
    }
    // The same refusal for a lightmap: one baked from other walls or other
    // lamps lights rooms that are not there.
    if (lightmap != null && lightmap.isStaleFor(level)) {
      loadIssues.add(
        const LevelIssue(
          LevelIssueSeverity.warning,
          'the lightmap was baked from different brushes or lights and is '
          'ignored; run bake_lightmap again',
        ),
      );
      lightmap = null;
    }
    // Planned here the same way the baker planned it, from the level and the
    // map's own density; the map carries pixels and a hash, not a table.
    var layout = lightmap == null
        ? null
        : LightmapLayout.plan(level, texelsPerMetre: lightmap.texelsPerMetre);
    // And then checked against the map, which is the one thing the hash
    // cannot do for us: it says the level is the level the bake read, not
    // that this build's packer puts the faces where that build's packer put
    // them. An atlas of a different size is proof they disagree — a changed
    // planner, or a density that did not survive the sidecar's float32 — and
    // every face would then sample somebody else's texels, which reads as
    // scrambled light rather than as a stale map. Cheap enough to do every
    // load: two integers.
    if (layout != null &&
        lightmap != null &&
        (layout.width != lightmap.width || layout.height != lightmap.height)) {
      loadIssues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'the lightmap is ${lightmap.width}x${lightmap.height} and this '
          'build plans ${layout.width}x${layout.height} for the same level, '
          'so it is ignored; run bake_lightmap again',
        ),
      );
      lightmap = null;
      layout = null;
    }
    final lightmapTexture = lightmap == null
        ? null
        : device.createTextureFromPixels(
            width: lightmap.width,
            height: lightmap.height,
            format: TextureFormat.r8g8b8a8UNormInt,
            pixels: ByteData.sublistView(lightmap.pixels),
          );
    if (lightmap != null && lightmapTexture == null) {
      loadIssues.add(
        const LevelIssue(
          LevelIssueSeverity.warning,
          'the lightmap could not be uploaded and is ignored',
        ),
      );
    }
    final surfaces = const BrushGeometry().build(
      level,
      visibility: visibility,
      lightmap: lightmapTexture == null ? null : layout,
    );
    // Remembered on the way in, so `LoadedLevel.dispose` can release exactly
    // what this loop uploaded and nothing else.
    final brushMeshes = <DeviceMesh>[];
    // And with their boxes, so the culler can ask which of them a cell sees.
    final batches = <VisibilityBatch>[];
    final brushNodes = <MeshNode>[];
    // Once per level, as `tilingSamplerFor` promises: one object, shared by
    // every brush surface below.
    final tiling = tilingSamplerFor(device);
    for (final surface in surfaces) {
      final mesh = DeviceMesh.upload(device, _toMeshData(surface));
      brushMeshes.add(mesh);
      final node =
          MeshNode(
              mesh,
              LevelLoader.materialFrom(
                  level.materials[surface.material] ?? LevelMaterial(),
                  textures,
                  name: surface.material,
                  tiling: tiling,
                )
                ..lightmap = surface.lightmapUvs == null
                    ? null
                    : lightmapTexture,
              name: surface.material,
            )
            ..lightmapped = surface.lightmapUvs != null
            // Brushes are the level: they never move, so their shadow is baked
            // once rather than redrawn six times a frame.
            ..shadowIsStatic = true
            // A fence is not architecture, and a wall one brush thick casts
            // from both faces. See `Brush.shadowCasting` — and note that this
            // is why surfaces are batched by that answer as well as by
            // material: a batch is the smallest thing that can answer it.
            ..shadowCasting = shadowModeOf(surface.shadowCasting);
      scene.add(node);
      batches.add((node: node, bounds: surface.bounds));
      brushNodes.add(node);
    }

    for (final light in level.lights) {
      scene.add(_toLightNode(light));
    }

    // A probe wherever the document asks for one, built the way the lights
    // are rather than spawned: it is a scene node and the simulation has no
    // use for it. The kind that validates the entity is the game's to speak
    // — see `ReflectionProbeKind` — and by now it has.
    final probes = <ReflectionProbeNode>[
      for (final entity in level.ofType(EntityTypes.reflectionProbe))
        _toProbeNode(entity),
    ];
    for (final probe in probes) {
      scene.add(probe);
    }

    return LoadedLevel(
        level: level,
        scene: scene,
        collision: collision,
        issues: <LevelIssue>[...validator.validate(level), ...loadIssues],
        drawCallCount: surfaces.length,
        materialTextures: textures,
        brushMeshes: brushMeshes,
        probes: probes,
        culler: visibility == null
            ? null
            : VisibilityCuller(visibility, batches),
      )
      ..brushNodes.addAll(brushNodes)
      ..lightmap = lightmapTexture
      // Kept for the rebuild after a breach, which has to plan nothing: the
      // atlas is a pure function of the authored level, and this is that
      // function's answer for the level that was actually loaded.
      ..lightmapLayout = lightmapTexture == null ? null : layout;
  }

  /// A kept probe at the entity's position, with the document's numbers
  /// where it gave any and the probe's own defaults where it did not.
  ///
  /// The defaults are restated rather than reached for because the node's
  /// are constructor defaults, and a document that says nothing means those.
  /// Kept, never rolling: a level's rooms do not move, and a probe that
  /// redrew a face a frame would spend a view of the level on a picture it
  /// already has.
  static ReflectionProbeNode _toProbeNode(EntityDef entity) =>
      ReflectionProbeNode(
        name: entity.name,
        radius: entity.number('radius') ?? 0.0,
        intensity: entity.number('intensity') ?? 1.0,
        faceSize: entity.integer('faceSize') ?? 64,
        levels: entity.integer('levels') ?? 4,
        near: entity.number('near') ?? 0.05,
        far: entity.number('far') ?? 200.0,
      )..setPositionFrom(entity.position);

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
    SamplerOptions tiling = _tiling,
  }) {
    final material = Material(
      name: name,
      baseColor: source.baseColor,
      roughness: source.roughness,
      metallic: source.metallic,
      // A level material's `emissive` is a strength, not a colour: the surface
      // glows in the base colour it already has, that much. A separate
      // emissive colour would be a second value an author has to keep in step
      // with the first, and everything that has reached for the key so far —
      // the platformer's hazard "lit from inside", its checkpoints, its exit —
      // wanted exactly the tint it had already written.
      emissive: Vector3(
        source.baseColor.x,
        source.baseColor.y,
        source.baseColor.z,
      ),
      emissiveStrength: source.emissive,
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
      ..albedoSampler = tiling
      ..normalSampler = tiling
      ..metallicRoughnessSampler = tiling
      ..occlusionSampler = tiling;
    return material;
  }

  /// How far the filter may reach across a brush surface at a grazing angle.
  ///
  /// Eight, not sixteen. Sixteen is what the hardware offers and eight is where
  /// a corridor floor stops visibly improving; past it the taps cost fill rate
  /// on a phone for a difference nobody has pointed at. Clamped to what the
  /// device answers, so a device without the filter gets the sampler it always
  /// had and the software rasteriser — which answers one — draws its own set.
  static const int tilingAnisotropy = 8;

  /// [_tiling] with the taps this [device] can take, up to
  /// [tilingAnisotropy].
  ///
  /// Decided once per level rather than per bind: the renderer's own
  /// `RenderSettings.anisotropy` leaves a sampler that already carries a
  /// level alone, so a level's walls are not turned up twice, and a game that
  /// turns the setting down for a slower phone still has the level's floors
  /// filtered — which is deliberate, because a brush floor seen along its
  /// length is the surface the filter is for.
  static SamplerOptions tilingSamplerFor(GraphicsDevice device) =>
      _tiling.withAnisotropy(math.min(tilingAnisotropy, device.maxAnisotropy));

  static Future<TextureHandle?> _upload(
    GraphicsDevice device,
    String path,
    AssetBytes read,
    List<LevelIssue> issues,
  ) async {
    try {
      final bytes = await read(AssetRequest(path));
      // Mipmapped: a level's walls and floors are the surfaces most often seen
      // small and at a glancing angle, which is exactly where a single level
      // crawls as the camera moves.
      return await uploadEncodedImage(
        device,
        bytes.buffer.asUint8List(),
        sampling: const TextureSampling(),
        // A KTX2 the device does not sample, or a feature of one the reader
        // does not have, is a flat wall with a sentence beside it — the same
        // treatment a missing file gets below.
        report: (message) => issues.add(
          LevelIssue(LevelIssueSeverity.warning, message, where: path),
        ),
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
  ///
  /// Isotropic here, which is the default a caller of [materialFrom] gets
  /// with no device to ask; a level loaded through this class gets
  /// [tilingSamplerFor] instead.
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
      // Vertex colour multiplies the material's, so white leaves it alone —
      // unless the level has a lightmap, when the lightmapped vertex stage
      // reads the first two channels as the vertex's place in it and holds
      // the tint at white itself. See `mesh_lightmapped.vert`.
      final lightmapUvs = surface.lightmapUvs;
      vertices[out + 12] = lightmapUvs?[i * 2] ?? 1.0;
      vertices[out + 13] = lightmapUvs?[i * 2 + 1] ?? 1.0;
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
