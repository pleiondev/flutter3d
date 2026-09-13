/// Builds the [Scene] a [RenderSnapshotJob] draws.
///
/// **A second scene builder, and the plan's own words already say why one
/// exists.** `apps/flutter3d_modeler/lib/src/staging.dart`'s own
/// `ModelerStage.fromProject` is the one door a document already comes
/// through for the live viewport — but it lives in the application, and a
/// package under `flutter3d_model_core` may not depend on the application
/// that owns it (`no package depends on an application`,
/// `tool/structure/rules.dart`). So this is a second, narrower door: the
/// same node types and the same default lighting, built directly against a
/// [GraphicsDevice] rather than through `SceneSync`'s incremental diffing,
/// which a one-shot snapshot has no use for — there is nothing to diff
/// against.
///
/// **No textures, and that is a real gap rather than a silent one.**
/// `MaterialPool`'s own decoding is asynchronous and content-hashed across
/// the whole project table; a snapshot wants one deterministic, synchronous
/// pass over values already in memory. A textured object renders in its
/// base colour, metallic and roughness alone — the same "clay" the live
/// viewport itself shows for one frame while its own pool is still filling,
/// per that class's own doc comment. Wiring a real texture pipeline through
/// an isolate boundary is future work, not something this row's own `M` size
/// budgets for.
///
/// **The two default lights, not [ModelProject.lighting].** `mat-23`'s own
/// `SceneLighting`/`ProjectLight` table is real and already has a scene-side
/// counterpart in `apps/flutter3d_modeler/lib/src/lighting_sync.dart`'s
/// `LightingSync` — but nothing in the application calls it yet (`grep -rn
/// LightingSync apps/flutter3d_modeler/lib` finds only its own file), so the
/// live viewport today still lights every project with `ModelerStage`'s own
/// hardcoded key and fill pair regardless of what `project.lighting` holds.
/// Reading `project.lighting.lights` here instead would make a snapshot
/// disagree with the live viewport it is supposed to match — the exact
/// failure this row's own acceptance is about — for the sake of a feature
/// the viewport does not act on yet. This function matches today's actual
/// live behaviour; switching both sides over to `SceneLighting` together is
/// `mat-23`'s own integration to finish, not a divergence to introduce here.
///
/// **No parent hierarchy either.** `ModelObject.parent` is read by nothing
/// here; every object attaches directly to the scene root in its own local
/// transform. A project that nests a child under a moved parent would
/// therefore render that child in the wrong place. `ModelerStage.fromProject`
/// already walks the hierarchy correctly for the live viewport; duplicating
/// that walk here is exactly the kind of scope a "job wrapper" row should
/// not absorb on its own initiative.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

/// [project]'s objects as a [Scene] on [device] — key and fill lights, no
/// camera (a [RenderSnapshotJob] builds its own from `RenderPreset.camera`
/// per tile, since a tile's device is not [device]).
///
/// The two lights are the exact numbers `ModelerStage.fromProject`'s own
/// `_light` uses, so a snapshot of an unlit-looking corner of a project
/// reads the same as the live viewport showing it — the one piece of visual
/// parity this function can promise without the app's own material pool.
Scene sceneFromProject(ModelProject project, GraphicsDevice device) {
  final scene = Scene();
  scene.add(
    LightNode(type: LightType.directional, name: 'key')
      ..intensity = 3.2
      ..setLocalForward(Vector3(-0.5, -1.0, -0.6)),
  );
  scene.add(
    LightNode(type: LightType.directional, name: 'fill')
      ..intensity = 1.1
      ..setLocalForward(Vector3(0.7, -0.3, 0.8)),
  );

  for (final ModelObject object in project.objects) {
    final data = _dataOf(object.geometry);
    final node = MeshNode(
      DeviceMesh.upload(device, data),
      _materialFor(project, object),
      name: object.name,
    )..setLocalMatrix(object.transform);
    scene.add(node);
  }
  return scene;
}

/// The buffers a geometry draws as — the same switch
/// `apps/flutter3d_modeler/lib/src/scene_sync.dart`'s own `_dataOf` runs,
/// copied rather than shared because that file is in the application.
MeshData _dataOf(Geometry geometry) => switch (geometry) {
  ParametricGeometry(:final shape) => shape.drawn.build(),
  EditedGeometry(:final mesh) => mesh.toMeshData(),
  ImportedGeometry(:final data) => data,
  // A socket draws nothing — see `SocketGeometry`'s own doc comment.
  SocketGeometry() => _empty,
};

final MeshData _empty = MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List(0),
  indices: Uint32List(0),
);

/// [object]'s first material slot, translated field for field into the
/// engine's own [Material] — or a plain grey [Material] when it names none,
/// the same fallback `MaterialPool.forObject` answers with as `clay()`.
Material _materialFor(ModelProject project, ModelObject object) {
  if (object.materialSlots.isEmpty) {
    return Material(lighting: LightingModel.pbr);
  }
  final index = object.materialSlots.first;
  if (index < 0 || index >= project.materials.length) {
    return Material(lighting: LightingModel.pbr);
  }
  final surface = project.materials[index].surface;
  return Material(
    name: surface.name,
    lighting: surface.unlit ? LightingModel.unlit : LightingModel.pbr,
    baseColor: surface.baseColor,
    metallic: surface.metallic,
    roughness: surface.roughness,
    emissive: surface.emissive,
    emissiveStrength: surface.emissiveStrength,
    doubleSided: surface.doubleSided,
  );
}
