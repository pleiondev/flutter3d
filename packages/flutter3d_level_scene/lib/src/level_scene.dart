/// A level document turned into a scene, with no Flutter anywhere in reach.
///
/// **The half of loading a level that never needed a window.** Brushes into
/// meshes, level materials into engine materials, lights into light nodes,
/// probes into probe nodes: arithmetic and device calls, every one of them
/// reachable from `flutter3d_core`. It lived in `flutter3d_app`'s
/// `LevelLoader` beside the two things that do need Flutter — `rootBundle`,
/// and decoding a PNG through `dart:ui` — and so a program started by
/// `dart run` could not draw a level at all. The loader keeps the bundle and
/// the decoding, hands what they produced to [LevelScene.build], and wraps
/// the answer in its own `LoadedLevel`; the level editor's agent server hands
/// it nothing and draws the level flat.
///
/// It sat in `flutter3d_editor_core` until 1.0.0-rc.1, which made the
/// application depend on the editor's document layer to load a level. It is
/// a package of its own now, under both.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// How a level's brushes are grouped into draws.
///
/// A class with const instances rather than an enum, so a third way of
/// grouping — per cell alone, say — is a new constant and not a break in
/// every `switch` somebody wrote against the first two.
final class LevelBatching {
  const LevelBatching._(this.name, {required this.drawPerBrush});

  /// One draw per material and shadow answer — and per visibility cell when
  /// there is a table. What a game draws with: a level of two hundred brushes
  /// is a handful of draws.
  static const LevelBatching perMaterial = LevelBatching._(
    'perMaterial',
    drawPerBrush: false,
  );

  /// One draw per brush, so a pixel names the brush it belongs to. What a
  /// tool that has to say *which* wall hides a torch draws with, paying a
  /// draw per brush for the answer.
  static const LevelBatching perBrush = LevelBatching._(
    'perBrush',
    drawPerBrush: true,
  );

  final String name;

  /// Whether every brush is a draw of its own — what `BrushGeometry.build`'s
  /// `perBrush` is handed.
  final bool drawPerBrush;

  @override
  String toString() => 'LevelBatching.$name';
}

/// One draw of a level's brushes: the node in the scene, the mesh it draws
/// (uploaded by [LevelScene], so released by whoever keeps the level), the
/// box around it, and the brush it is when the level was built
/// [LevelBatching.perBrush].
typedef LevelBatch = ({
  MeshNode node,
  DeviceMesh mesh,
  Aabb3 bounds,
  int? brush,
});

/// What [LevelScene.build] made: the scene, and the parts of it a caller
/// keeps to rebuild, cull or release.
final class LevelSceneParts {
  const LevelSceneParts({
    required this.scene,
    required this.batches,
    required this.lights,
    required this.probes,
    this.decals = const <DecalNode>[],
    this.reflectors = const <PlanarReflectorNode>[],
    this.screens = const <RenderView>[],
  });

  final Scene scene;

  /// Every brush draw, in the order added to [scene].
  final List<LevelBatch> batches;

  /// One light node per `level.lights`, in document order.
  final List<LightNode> lights;

  /// One kept probe per reflection-probe entity, in document order.
  final List<ReflectionProbeNode> probes;

  /// One per decal entity. They are drawn where the game turns decals on,
  /// so a game whose level has some reads this to know it should.
  final List<DecalNode> decals;

  /// One per reflector entity, mirroring the batches of its material.
  final List<PlanarReflectorNode> reflectors;

  /// One per camera-screen entity, already added to the scene. Each is the
  /// caller's to give back with `Renderer.releaseTextureAfterFrame`.
  final List<RenderView> screens;
}

/// Builds the scene a level document describes.
///
/// Nothing here knows what game it is loading, and nothing here reads a
/// file: the textures a level names and the `.fmat` materials it defers to
/// are loaded by the caller — the one with an asset bundle and an image
/// decoder — and handed in already on the device. A caller with neither
/// hands nothing, and every surface is drawn in the numbers the document
/// itself carries.
final class LevelScene {
  const LevelScene({this.batching = LevelBatching.perMaterial});

  final LevelBatching batching;

  /// The level's brushes, lights and probes in a new [Scene].
  ///
  /// [textures] are the maps the level's materials name, by path; [deferred]
  /// the bound material of every level material that defers to a `.fmat`, by
  /// material name. [visibility] batches the brushes per cell, and
  /// [lightmapLayout] with [lightmapTexture] gives every brush vertex its
  /// place in the baked light — see [brushBatches].
  LevelSceneParts build(
    Level level, {
    required GraphicsDevice device,
    Map<String, TextureHandle?> textures = const <String, TextureHandle?>{},
    Map<String, RenderMaterial> deferred = const <String, RenderMaterial>{},
    LevelVisibility? visibility,
    LightmapLayout? lightmapLayout,
    TextureHandle? lightmapTexture,
  }) {
    final scene = Scene();
    final batches = brushBatches(
      level,
      device: device,
      textures: textures,
      deferred: deferred,
      visibility: visibility,
      lightmapLayout: lightmapLayout,
      lightmapTexture: lightmapTexture,
    );
    for (final batch in batches) {
      scene.add(batch.node);
    }
    final lights = <LightNode>[
      for (final light in level.lights) lightOf(light),
    ];
    for (final light in lights) {
      scene.add(light);
    }
    // A probe wherever the document asks for one, built the way the lights
    // are rather than spawned: it is a scene node and the simulation has no
    // use for it. The kind that validates the entity is the game's to speak
    // — see `ReflectionProbeKind`.
    final probes = <ReflectionProbeNode>[
      for (final entity in level.ofType(EntityTypes.reflectionProbe))
        probeOf(entity),
    ];
    for (final probe in probes) {
      scene.add(probe);
    }
    // Decals, mirrors and screens, each naming a level material the way a
    // brush does: the picture a decal paints, the surfaces a mirror is
    // drawn on, the surfaces a screen lights. Kinds in `flutter3d_sim`
    // validate them; see `DecalKind`.
    final decals = <DecalNode>[
      for (final entity in level.ofType(EntityTypes.decal))
        decalOf(entity, level, textures),
    ];
    final reflectors = <PlanarReflectorNode>[
      for (final entity in level.ofType(EntityTypes.reflector))
        reflectorOf(entity, batches),
    ];
    final screens = <RenderView>[
      for (final entity in level.ofType(EntityTypes.cameraScreen))
        screenOf(entity, batches, device: device),
    ];
    for (final node in <SceneNode>[...decals, ...reflectors]) {
      scene.add(node);
    }
    screens.forEach(scene.addTextureView);
    return LevelSceneParts(
      scene: scene,
      batches: batches,
      lights: lights,
      probes: probes,
      decals: decals,
      reflectors: reflectors,
      screens: screens,
    );
  }

  /// The level's brushes as draws, uploaded to [device] and not yet in any
  /// scene.
  ///
  /// With [lightmapLayout] and [lightmapTexture] both given, every vertex
  /// carries its place in the atlas and every draw samples it; [origins] is
  /// `BrushGeometry.build`'s, for brushes a breach has cut. A surface whose
  /// material is in [deferred] draws with that material, and every other one
  /// with [materialFrom] of the document's own numbers.
  List<LevelBatch> brushBatches(
    Level level, {
    required GraphicsDevice device,
    Map<String, TextureHandle?> textures = const <String, TextureHandle?>{},
    Map<String, RenderMaterial> deferred = const <String, RenderMaterial>{},
    LevelVisibility? visibility,
    LightmapLayout? lightmapLayout,
    TextureHandle? lightmapTexture,
    List<int>? origins,
  }) {
    final surfaces = const BrushGeometry().build(
      level,
      visibility: visibility,
      lightmap: lightmapTexture == null ? null : lightmapLayout,
      origins: origins,
      perBrush: batching.drawPerBrush,
    );
    // Once per level, as `tilingSamplerFor` promises: one object, shared by
    // every brush surface below.
    final tiling = tilingSamplerFor(device);
    return <LevelBatch>[
      for (final surface in surfaces)
        _batchOf(
          surface,
          DeviceMesh.upload(device, meshDataOf(surface)),
          deferred[surface.material] ??
              materialFrom(
                level.materials[surface.material] ?? LevelMaterial(),
                textures,
                name: surface.material,
                tiling: tiling,
              ),
          lightmapTexture,
        ),
    ];
  }

  static LevelBatch _batchOf(
    BrushSurface surface,
    DeviceMesh mesh,
    RenderMaterial material,
    TextureHandle? lightmap,
  ) {
    final node =
        MeshNode(
            mesh,
            material..lightmap = surface.lightmapUvs == null ? null : lightmap,
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
          ..shadowCasting = shadowModeOf(surface.shadowCasting)
          // `P7`: the document's order, which is also why surfaces are
          // batched by it.
          ..drawOrder = surface.drawOrder;
    // The document's depth layer — `RenderMaterial.depthLayer`, which coplanar
    // surfaces are ordered by; batches never mix layers.
    material.depthLayer = surface.depthLayer;
    return (
      node: node,
      mesh: mesh,
      bounds: surface.bounds,
      brush: surface.brush,
    );
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

  /// Builds an engine material from a level material and the loaded maps.
  ///
  /// A free function rather than a method on either type: [LevelMaterial] lives
  /// in the game package, which must not know that textures exist, and
  /// [RenderMaterial] lives in the renderer, which must not know that levels do. This
  /// is the seam, and it is the only place that knows both.
  static RenderMaterial materialFrom(
    LevelMaterial source,
    Map<String, TextureHandle?> textures, {
    String? name,
    SamplerDescriptor tiling = _tiling,
  }) {
    final material = RenderMaterial(
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
      // The level's numbers as they always reached the shader, and its
      // strength in the old unit, which the material takes as nits.
      emissive: switch (source.storedBaseColor) {
        final stored => LinearColor(stored.x, stored.y, stored.z),
      },
      emissiveStrength: source.emissive * Photometric.legacyNits,
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
  static SamplerDescriptor tilingSamplerFor(GraphicsDevice device) =>
      _tiling.withAnisotropy(
        math.min(tilingAnisotropy, device.limits.maxSamplerAnisotropy),
      );

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
  /// with no device to ask; a level built through this class gets
  /// [tilingSamplerFor] instead.
  static const SamplerDescriptor _tiling = SamplerDescriptor.trilinearRepeat;

  /// The light node a level light becomes.
  static LightNode lightOf(LevelLight light) {
    final node = LightNode(
      type: switch (light.type) {
        LevelLightType.directional => LightType.directional,
        LevelLightType.point => LightType.point,
        LevelLightType.spot => LightType.spot,
      },
      color: light.color.toLinearColor(),
      intensity: light.intensity * Photometric.legacyUnit,
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

  /// A kept probe at the entity's position, with the document's numbers
  /// where it gave any and the probe's own defaults where it did not.
  ///
  /// The defaults are restated rather than reached for because the node's
  /// are constructor defaults, and a document that says nothing means those.
  /// Kept, never rolling: a level's rooms do not move, and a probe that
  /// redrew a face a frame would spend a view of the level on a picture it
  /// already has.
  /// The decal [entity] asks for: its material's picture and colour,
  /// stamped down a box of `size` at its `at`, turned by its `yaw` and
  /// tipped by its `pitch` — ninety stands it on a wall.
  static DecalNode decalOf(
    EntityDef entity,
    Level level,
    Map<String, TextureHandle?> textures,
  ) {
    final source = level.materials[entity.string('material')];
    final size = entity.vector('size') ?? Vector3(1.0, 1.0, 1.0);
    final pitch = (entity.number('pitch') ?? 0.0) * math.pi / 180.0;
    return DecalNode(
        name: entity.name,
        texture: source == null ? null : textures[source.albedo],
        color: source == null ? LinearColor.white : source.baseColor,
        order: entity.integer('order') ?? 0,
      )
      ..setPositionFrom(entity.position)
      ..setRotation(
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw) *
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), pitch),
      )
      ..setScale(size.x, size.y, size.z);
  }

  /// The mirror [entity] asks for: a plane through its `at`, facing up,
  /// drawn on every batch of its material.
  static PlanarReflectorNode reflectorOf(
    EntityDef entity,
    List<LevelBatch> batches,
  ) {
    final material = entity.string('material');
    return PlanarReflectorNode(
      name: entity.name,
      surfaces: <MeshNode>[
        for (final batch in batches)
          if (batch.node.material.name == material) batch.node,
      ],
      reflectance: entity.number('reflectance') ?? 1.0,
      strength: entity.number('strength') ?? 1.0,
      resolution: entity.number('resolution') ?? 0.5,
    )..setPositionFrom(entity.position);
  }

  /// The camera [entity] asks for, drawing into a texture every batch of
  /// its material gives off as light — and leaves out of its own picture,
  /// or a screen in view would show itself showing itself.
  static RenderView screenOf(
    EntityDef entity,
    List<LevelBatch> batches, {
    required GraphicsDevice device,
  }) {
    final look = entity.vector('look') ?? entity.position + Vector3(0, 0, -1);
    final camera =
        CameraNode(
            name: entity.name,
            projection: PerspectiveProjection(
              fovY: (entity.number('fov') ?? 60.0) * math.pi / 180.0,
            ),
          )
          ..setPositionFrom(entity.position)
          ..lookAt(look, up: Vector3(0.0, 1.0, 0.0));
    final screen = RenderView.texture(
      device,
      camera: camera,
      width: entity.integer('width') ?? 256,
      height: entity.integer('height') ?? 144,
      options: RenderViewSettings(refreshEveryFrame: !entity.flag('once')),
    );
    final material = entity.string('material');
    for (final batch in batches) {
      final shown = batch.node.material;
      if (shown.name != material) continue;
      screen.excluded.add(batch.node);
      shown
        ..emissiveTexture = screen.texture
        ..emissive = LinearColor(1.0, 1.0, 1.0)
        ..emissiveStrength = math.max(
          shown.emissiveStrength,
          Photometric.legacyNits,
        );
    }
    return screen;
  }

  static ReflectionProbeNode probeOf(EntityDef entity) => ReflectionProbeNode(
    name: entity.name,
    radius: entity.number('radius') ?? 0.0,
    intensity: entity.number('intensity') ?? 1.0,
    faceSize: entity.integer('faceSize') ?? 64,
    levels: entity.integer('levels') ?? 4,
    near: entity.number('near') ?? 0.05,
    far: entity.number('far') ?? 200.0,
  )..setPositionFrom(entity.position);
}

/// Interleaves the level package's plain arrays into the engine's layout.
///
/// **One copy, because there are two producers.** `BrushSurface` is what
/// `flutter3d_sim` emits for anything it can describe as triangles — the
/// level's brushes, and terrain since a `Heightfield` learned to build its
/// own — and the paragraph below is a note about a GPU failure that produces
/// no error at all, which a second copy would one day stop matching.
///
/// It has to be [VertexLayout.standard] and not a shorter one. flutter_gpu
/// takes the layout from the vertex shader's `in` declarations, and
/// `mesh.vert` declares position, normal, texcoord, tangent **and** colour —
/// sixteen floats. Supplying eight does not fail: the GPU keeps reading at
/// the stride the shader expects and assembles each vertex from two of the
/// ones actually written, which draws a convincing field of garbage
/// triangles and no error anywhere.
MeshData meshDataOf(BrushSurface surface) {
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

  return MeshData(layout: layout, vertices: vertices, indices: surface.indices);
}
