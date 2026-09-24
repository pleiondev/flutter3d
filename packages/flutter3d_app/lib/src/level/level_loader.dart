import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show LevelBatching, LevelScene;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'loaded_level.dart';
import 'visibility_culler.dart';

export 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show LevelBatching;
export 'loaded_level.dart';

/// How a level's own files are found.
///
/// **A level belongs to an application, and it is not always the one running.**
/// A game reads its textures out of its own bundle, which is why this was
/// `rootBundle.load` written into the loader — and an editor opens a document
/// belonging to a *different* application, whose textures are on the disk
/// beside it and in nobody's bundle. Without this the crypt draws in flat grey
/// in the one program whose whole job is to show somebody what their level
/// looks like.
///
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

/// A level's `.fmat` as something [loadMaterialDocument] will read.
///
/// **Why the engine asks for a source and not for bytes**, and why closing over
/// a callback is allowed here: an `AssetSource` is a sendable description
/// because a *model* decode crosses to a background isolate, where a closure
/// cannot follow. A material decode does not — it is a few hundred bytes of
/// JSON read on this isolate, which `MaterialDecoder` says at length. So this
/// one may hold the level's own reader, and that is the point: a game's
/// bundled material and an editor's material on disk beside a document it has
/// just opened go through the same call, exactly as their textures already do.
final class _LevelMaterialSource extends AssetSource {
  const _LevelMaterialSource(this.path, this.fetch);

  final String path;
  final AssetBytes fetch;

  @override
  String get key => 'level-material:$path';

  @override
  Future<Uint8List> read() async => _bytes(await fetch(AssetRequest(path)));

  /// Images a material names are relative to the material file, the way a
  /// `.gltf`'s buffers and an `.obj`'s maps already are — so a folder of
  /// materials can be moved without rewriting what is inside them.
  @override
  AssetUriResolver get resolveUri {
    final slash = path.lastIndexOf('/');
    final directory = slash < 0 ? '' : path.substring(0, slash + 1);
    return (request) async =>
        _bytes(await fetch(AssetRequest('$directory${request.uri}')));
  }

  static Uint8List _bytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Reads a level asset and turns it into something playable.
///
/// The oldest half of the bridge, and still the clearest statement of what the
/// bridge is for: everything above it is simulation and everything below is
/// rendering, and the whole binding is the interleaving in `meshDataOf` —
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
  ///
  /// [readDocument] finds the level document itself, defaulting to
  /// `rootBundle.loadString` so the games that only ever load their own
  /// bundled levels are unaffected. [readAsset] governs the textures a level
  /// names, and is passed straight through to [build].
  ///
  /// [sidecars] is whether to look beside the document for a visibility table
  /// and a lightmap at all. True everywhere it can pay, and there is one place
  /// it cannot: **an open circuit has nothing to occlude with.** Baking the
  /// ring at a twenty-four metre grid — eight times coarser than the three
  /// metres an indoor level uses, because finer runs out of memory — took
  /// forty-eight minutes and produced a table whose density is *one hundred
  /// per cent*: all 14,992,384 pairs of its 3,872 cells see each other. The
  /// grid comes out two cells tall, which is the same fact from the other
  /// side — there is no geometry above the road to stand in the way. The
  /// crypt, for contrast, occludes 56% of its pairs at three metres in
  /// seconds, which is what the mechanism is for.
  ///
  /// So a circuit asking for sidecars is two guaranteed 404s in the console of
  /// every web build, and the alternative — shipping the table anyway — is
  /// 2.5 MB per game that culls nothing. Saying so here is cheaper than
  /// leaving each caller to discover it.
  ///
  /// [batching] is how the brushes are grouped into draws — see
  /// [LevelBatching]; a game keeps the default, a tool that has to name the
  /// brush under a pixel asks for one draw per brush.
  Future<LoadedLevel> load(
    String assetPath, {
    required GraphicsDevice device,
    required EntityRegistry registry,
    List<LevelRule> rules = const <LevelRule>[],
    AssetBytes? readAsset,
    DocumentText? readDocument,
    bool sidecars = true,
    LevelBatching batching = LevelBatching.perMaterial,
  }) async {
    final read = readDocument ?? _bundleDocument;
    final level = Level.fromJson(
      jsonDecode(await read(AssetRequest(assetPath))) as Map<String, Object?>,
    );
    final (visibility, issue) = sidecars
        ? await _sidecarVisibility(assetPath, read)
        : (null, null);
    final (lightmap, lightmapIssue) = sidecars
        ? await _sidecarLightmap(assetPath, readAsset ?? _bundleAsset)
        : (null, null);
    return build(
      level,
      device: device,
      registry: registry,
      rules: rules,
      readAsset: readAsset,
      visibility: visibility,
      lightmap: lightmap,
      issues: <LevelIssue>[?issue, ?lightmapIssue],
      batching: batching,
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
      return (Lightmap.fromBytes(_LevelMaterialSource._bytes(bytes)), null);
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

  /// The engine's shadow mode for the one a level document asked for —
  /// [LevelScene.shadowModeOf], where the reason it is a `switch` is written.
  static ShadowCastingMode shadowModeOf(ShadowCasting casting) =>
      LevelScene.shadowModeOf(casting);

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
  ///
  /// **A surface that deferred its look to a `.fmat` is rebuilt from the level's
  /// own numbers**, because the bound material belongs to the load and this
  /// method has no device work to redo it with — it re-binds nothing and
  /// re-uploads nothing on purpose. Nothing breachable defers yet; the day
  /// something does, the materials the load bound have to be kept beside the
  /// textures it uploaded, which is where the fix goes.
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
    final batches = LevelScene(batching: loaded.batching).brushBatches(
      cut,
      device: device,
      textures: loaded.materialTextures,
      lightmapLayout: origins == null ? null : loaded.lightmapLayout,
      lightmapTexture: loaded.lightmap,
      origins: origins,
    );
    for (final batch in batches) {
      loaded.scene.add(batch.node);
      loaded.brushNodes.add(batch.node);
    }
    loaded.brushMeshes = <DeviceMesh>[for (final batch in batches) batch.mesh];
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
  ///
  /// [authored]'s recipes are expanded first, and everything after — the
  /// validator, the colliders, the batches, the entities — sees the level as
  /// it is played.
  Future<LoadedLevel> build(
    Level authored, {
    required GraphicsDevice device,
    required EntityRegistry registry,
    List<LevelRule> rules = const <LevelRule>[],
    AssetBytes? readAsset,
    LevelVisibility? visibility,
    Lightmap? lightmap,
    List<LevelIssue> issues = const <LevelIssue>[],
    LevelBatching batching = LevelBatching.perMaterial,
  }) async {
    final level = expandRecipes(authored);
    // Errors throw with every one listed, because a level with a door whose key
    // is in no room is a level that cannot be finished, and finding that out
    // twenty minutes in is worse than not starting.
    final validator = LevelValidator(registry: registry, rules: rules);
    validator.assertValid(level);

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
      // A material that defers to a `.fmat` names its maps in that file, and
      // `bindMaterial` uploads them below. Uploading these three as well would
      // be three textures nothing ever samples.
      if (source.fmat != null) continue;
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

    // **The other dictionary.** Everything above binds a surface through
    // `materialFrom`, which is the bridge between the eight fields a
    // `LevelMaterial` has and the renderer's `Material` — and those eight are
    // all a level author ever had. A `.fmat` is the engine's own material
    // format and a far larger vocabulary: fourteen scalars, five texture slots
    // each with its own sampler, alpha, a shader of the application's own and
    // the parameters that shader reads. A level material naming one is saying
    // *ask that file instead*, and this is the fork.
    //
    // **What happens to the fields the second dictionary has no word for.**
    // `texelsPerMetre` is untouched and still applies: it scales the texture
    // coordinates in `BrushGeometry` long before anything is bound, so a
    // deferred wall tiles exactly as it did. `baseColor`, `roughness`,
    // `metallic`, `emissive`, `albedo`, `normal` and `orm` are *not* merged in
    // — the file is the whole answer, because a wall whose colour is stated in
    // two places is a wall somebody will one day change in the wrong one. The
    // level keeps them as what it falls back to when the file will not read,
    // which is the failure below. One thing is genuinely lost: the anisotropic
    // sampler `tilingSamplerFor` builds for brush surfaces, since a `.fmat`
    // names a sampler per slot and the file's answer wins over the level's.
    //
    // Bound once per material name rather than once per surface, so a level
    // whose walls share a look upload its maps once. Safe because a build
    // either has a lightmap layout or has not, so every surface in it carries
    // lightmap coordinates or none does — the one thing set on the material
    // per surface below.
    final deferred = <String, Material>{};
    for (final entry in level.materials.entries) {
      if (entry.value.fmat case final String path) {
        if (await _fmatMaterial(
              device,
              path,
              readAsset ?? _bundleAsset,
              loadIssues,
            )
            case final Material material) {
          deferred[entry.key] = material;
        }
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
    // Everything from here on needs no Flutter, and lives where a program
    // with none can reach it: the textures and `.fmat` materials this method
    // loaded are handed over already on the device.
    final parts = LevelScene(batching: batching).build(
      level,
      device: device,
      textures: textures,
      deferred: deferred,
      visibility: visibility,
      lightmapLayout: layout,
      lightmapTexture: lightmapTexture,
    );

    return LoadedLevel(
        level: level,
        scene: parts.scene,
        collision: collision,
        issues: <LevelIssue>[...validator.validate(level), ...loadIssues],
        drawCallCount: parts.batches.length,
        materialTextures: textures,
        // Remembered so `LoadedLevel.dispose` can release exactly what was
        // uploaded for the brushes and nothing else.
        brushMeshes: <DeviceMesh>[
          for (final batch in parts.batches) batch.mesh,
        ],
        probes: parts.probes,
        // With their boxes, so the culler can ask which of them a cell sees.
        culler: visibility == null
            ? null
            : VisibilityCuller(visibility, <VisibilityBatch>[
                for (final batch in parts.batches)
                  (node: batch.node, bounds: batch.bounds),
              ]),
        batching: batching,
      )
      ..brushNodes.addAll(<MeshNode>[
        for (final batch in parts.batches) batch.node,
      ])
      // A `.fmat`'s maps are uploaded by `bindMaterial` and named nowhere but
      // on the material, so they are collected here or never released.
      ..boundTextures.addAll(<TextureHandle>{
        for (final material in deferred.values)
          ...<TextureHandle?>[
            material.albedo,
            material.normal,
            material.metallicRoughness,
            material.occlusion,
            material.emissiveTexture,
            ...material.extraTextures.values,
          ].nonNulls,
      })
      ..lightmap = lightmapTexture
      // Kept for the rebuild after a breach, which has to plan nothing: the
      // atlas is a pure function of the authored level, and this is that
      // function's answer for the level that was actually loaded.
      ..lightmapLayout = lightmapTexture == null ? null : layout;
  }

  /// Builds an engine material from a level material and the loaded maps —
  /// [LevelScene.materialFrom], kept here under its old name because props,
  /// fixtures and the lesson viewers bind their looks through it.
  static Material materialFrom(
    LevelMaterial source,
    Map<String, TextureHandle?> textures, {
    String? name,
    SamplerOptions tiling = SamplerOptions.trilinearRepeat,
  }) => LevelScene.materialFrom(source, textures, name: name, tiling: tiling);

  /// How far the filter may reach across a brush surface at a grazing angle
  /// — [LevelScene.tilingAnisotropy].
  static const int tilingAnisotropy = LevelScene.tilingAnisotropy;

  /// The tiling sampler with the taps this [device] can take —
  /// [LevelScene.tilingSamplerFor].
  static SamplerOptions tilingSamplerFor(GraphicsDevice device) =>
      LevelScene.tilingSamplerFor(device);

  /// Reads the `.fmat` at [path] and binds it, or says why it could not.
  ///
  /// **A material that will not read is a warning, not a lost level** — the same
  /// bargain [_upload] strikes for a texture, and for the same reason: the
  /// surface falls back to the numbers the level document itself carries, the
  /// room is still walkable, and the person who renamed the file hears about it.
  /// The document's own findings come through too, because a `.fmat` with
  /// `roughnesss` in it is exactly the hand-edit that format exists to make
  /// survivable and the warning is the only place it shows.
  static Future<Material?> _fmatMaterial(
    GraphicsDevice device,
    String path,
    AssetBytes read,
    List<LevelIssue> issues,
  ) async {
    final source = _LevelMaterialSource(path, read);
    final warnings = <String>[];
    final Material material;
    try {
      final document = await loadMaterialDocument(source);
      warnings.addAll(document.warnings);
      material = await bindMaterial(
        document,
        device: device,
        resolveUri: source.resolveUri,
        warnings: warnings,
      );
    } catch (error) {
      issues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'could not be read, so the surface falls back to the numbers the '
          'level itself carries: $error',
          where: 'material "$path"',
        ),
      );
      return null;
    }
    for (final warning in warnings) {
      issues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          warning,
          where: 'material "$path"',
        ),
      );
    }
    return material;
  }

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
        // The view, not the whole buffer: a reader may hand back a window
        // onto a larger one, and the bytes outside it are not this file.
        _LevelMaterialSource._bytes(bytes),
        decodeImage: defaultImageDecoder,
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
}
