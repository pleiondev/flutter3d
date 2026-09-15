/// `sceneFromProject`: a [ModelProject] as a [Scene], for every picture of a
/// project drawn outside the application.
///
/// **One builder, and there used to be two.** `renderProject` (an agent's
/// single still) and `RenderSnapshotJob` (a tiled, supersampled snapshot) each
/// spelled the same walk over a project — the same two lights, the same
/// geometry switch, the same material translation — in two packages, and the
/// copies had already drifted: one read a material's own lighting model and
/// the other did not. Both live in this package now and draw through this.
///
/// The live viewport has its own door, `apps/flutter3d_modeler`'s
/// `ModelerStage.fromProject`, because it diffs a scene it keeps rather than
/// building one per picture; this package may not depend on that application
/// (`no package depends on an application`), and a one-shot picture has
/// nothing to diff against.
///
/// **No textures.** A textured object draws in its base colour, metallic and
/// roughness alone — the "clay" the live viewport shows for one frame while
/// its own material pool is still filling. Decoding a project's images is
/// asynchronous and content-hashed in the application; a picture built here
/// wants one synchronous pass over values already in memory.
///
/// **The two default lights, not [ModelProject.lighting].** They are the
/// numbers `ModelerStage.fromProject` lights every project with, so a picture
/// drawn here reads as bright as the viewport showing the same corner.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

import 'modifier_evaluation_cache.dart';
import 'modifier_slot.dart';
import 'project.dart';

/// [project]'s objects as a [Scene] on [device] — a key and a fill light, the
/// hierarchy walked, no camera (each caller frames its own).
///
/// [restyle], when given, is handed every object and the material this
/// function would draw it with, and answers the one to draw instead — how
/// `renderProject` shades normals or tints a selection without a second walk.
Scene sceneFromProject(
  ModelProject project,
  GraphicsDevice device, {
  Material Function(ModelObject object, Material material)? restyle,
}) {
  final scene = Scene()
    ..add(
      LightNode(type: LightType.directional, name: 'key')
        ..intensity = 3.2
        ..setLocalForward(Vector3(-0.5, -1.0, -0.6)),
    )
    ..add(
      LightNode(type: LightType.directional, name: 'fill')
        ..intensity = 1.1
        ..setLocalForward(Vector3(0.7, -0.3, 0.8)),
    );

  // A fresh cache per call: a picture is built once from whatever [project]
  // is right now, with nothing to keep an evaluated mesh alive for past it.
  final modifierCache = ModifierEvaluationCache();

  // Two passes, because an object may be listed before its parent: every node
  // made first, then each hung under its parent's node — or under the scene,
  // for an object with no parent or one the project no longer holds.
  final nodes = <int, MeshNode>{
    for (final ModelObject object in project.objects)
      object.id: MeshNode(
        DeviceMesh.upload(
          device,
          _meshDataFor(modifierCache, project, object),
        ),
        switch (restyle) {
          null => _materialOf(project, object),
          final restyle => restyle(object, _materialOf(project, object)),
        },
        name: object.name,
      )..setLocalMatrix(object.transform),
  };
  for (final ModelObject object in project.objects) {
    final node = nodes[object.id]!;
    switch (nodes[object.parent]) {
      case final MeshNode parent:
        parent.add(node);
      case null:
        scene.add(node);
    }
  }
  return scene;
}

/// The buffers [object] draws as — [ModelObject.geometry] run through its own
/// modifier stack first, when it has at least one enabled slot, or straight
/// through [_meshDataOf] otherwise. `tut-06`'s own fix: before it, every
/// picture drawn here read the geometry directly, and a mirror or an array
/// modifier never appeared in one until "Apply" baked it in and dropped the
/// stack.
MeshData _meshDataFor(
  ModifierEvaluationCache cache,
  ModelProject project,
  ModelObject object,
) {
  final hasEnabledModifier = object.modifiers.any(
    (ModifierSlot slot) => slot.enabled,
  );
  if (hasEnabledModifier) {
    final evaluated = cache.evaluatedMesh(project, object);
    if (evaluated != null) return evaluated.toMeshData();
  }
  return _meshDataOf(object.geometry);
}

/// The buffers a geometry draws as — the switch
/// `apps/flutter3d_modeler/lib/src/scene_sync.dart`'s own `_dataOf` runs for
/// the live viewport, which this package cannot import.
MeshData _meshDataOf(Geometry geometry) => switch (geometry) {
  ParametricGeometry(:final shape) => shape.drawn.build(),
  EditedGeometry(:final mesh) => mesh.toMeshData(),
  ImportedGeometry(:final data) => data,
  // A socket draws nothing — see `SocketGeometry`'s own doc comment.
  SocketGeometry() => _emptyMesh,
};

final MeshData _emptyMesh = MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List(0),
  indices: Uint32List(0),
);

/// [object]'s first material slot, translated field for field into the
/// engine's own [Material] — or a plain grey [Material] when it names none,
/// the same fallback `MaterialPool.forObject` answers with as `clay()`.
Material _materialOf(ModelProject project, ModelObject object) {
  final index = object.materialSlots.firstOrNull;
  if (index == null || index < 0 || index >= project.materials.length) {
    return Material(lighting: LightingModel.pbr);
  }
  final surface = project.materials[index].surface;
  return Material(
    name: surface.name,
    lighting:
        surface.lightingModel ??
        (surface.unlit ? LightingModel.unlit : LightingModel.pbr),
    baseColor: surface.baseColor,
    metallic: surface.metallic,
    roughness: surface.roughness,
    emissive: surface.emissive,
    emissiveStrength: surface.emissiveStrength,
    doubleSided: surface.doubleSided,
  );
}
