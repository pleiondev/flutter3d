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
/// **The two default lights, plus whatever [ModelProject.lighting] adds on
/// top — `tut-07`'s own fix.** The pair is the numbers
/// `ModelerStage.fromProject` lights every project with, so a picture drawn
/// here reads as bright as the viewport showing the same corner; a project's
/// own lights come through `LightingSync`, the same sync the live viewport
/// calls, additive over the pair rather than replacing it — see
/// `LightingSync.sync`'s own doc comment for why the pair stays.
///
/// **The mesh a picture shows is the one the viewport shows** — modifiers
/// folded in (`tut-06`), a skinned object posed through its joints and a
/// shape-key blend at its current weights (`tut-10`).
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'lighting_sync.dart';
import 'modifier_evaluation_cache.dart';
import 'modifier_slot.dart';
import 'project.dart';
import 'project_animation.dart';
import 'project_morphs.dart';
import 'weight_gradient_colors.dart';
import 'wire_overlay.dart';
import 'world_transform.dart';

/// [project]'s objects as a [Scene] on [device] — a key and a fill light and
/// the project's own lights, the hierarchy walked, no camera (each caller
/// frames its own).
///
/// [restyle], when given, is handed every object and the material this
/// function would draw it with, and answers the one to draw instead — how
/// `renderProject` shades normals or tints a selection without a second walk.
///
/// [weightsJoint], when given, is the joint whose skin weights are painted as
/// a gradient on every [EditedGeometry] mesh bound to that joint's skeleton —
/// `tut-11`'s own weights picture. Such an object draws unlit in its gradient
/// and [restyle] is not asked about it; everything else draws as usual.
///
/// [wires], when true, hangs a second mesh under every [EditedGeometry]
/// object: that object's own polygon edges as thin solids — `mcp-08n`'s
/// fourth render mode, and `wire_overlay.dart` says why it is geometry
/// rather than a line topology. An object with no half-edge topology behind
/// it — an [ImportedGeometry] — gets none, because it has no polygons to
/// read.
Scene sceneFromProject(
  ModelProject project,
  GraphicsDevice device, {
  Material Function(ModelObject object, Material material)? restyle,
  int? weightsJoint,
  bool wires = false,
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
  // Additive over the fixed pair above — see [LightingSync.sync]'s own doc
  // comment. A fresh instance is fine: this function builds one scene and
  // hands it back, with nothing kept alive to stay in step with a second call.
  LightingSync().sync(scene, project.lighting);

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
          _meshDataFor(modifierCache, project, object, weightsJoint),
        ),
        _isWeightsTarget(project, object, weightsJoint)
            ? _weightsGradientMaterial
            : switch (restyle) {
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
  if (wires) {
    // A child of the object's own node rather than a sibling in the scene, so
    // the wires carry the object's transform — and the whole chain of its
    // parents' — without this function computing a world matrix a second
    // time. The child's own matrix is identity: the edges are already in the
    // object's local space, which is where `EditMesh` keeps them.
    for (final ModelObject object in project.objects) {
      final Geometry geometry = object.geometry;
      if (geometry is! EditedGeometry) continue;
      final MeshData? wire = wireMeshFor(geometry.mesh);
      if (wire == null) continue;
      nodes[object.id]!.add(
        MeshNode(
          DeviceMesh.upload(device, wire),
          _wireMaterial,
          name: '${object.name} wires',
        ),
      );
    }
  }
  return scene;
}

/// What a wire is drawn with: near-black, unlit, and lit by nothing.
///
/// Unlit for the reason the weights gradient is — a wire is a diagram and not
/// a surface, and a shaded one would be bright on the lit side of the model
/// and invisible on the other, which is the half of the mesh somebody asked
/// to see. Not fully black: a wire against a dark background needs somewhere
/// to go.
final Material _wireMaterial = Material(
  name: 'wires',
  lighting: LightingModel.unlit,
  baseColor: Vector4(0.06, 0.07, 0.09, 1.0),
);

/// [VertexLayout.skinned] for an object bound to a skeleton,
/// [VertexLayout.standard] otherwise — the exact switch `SceneSync
/// ._layoutFor` already runs for the live viewport (`apps/flutter3d_modeler/
/// lib/src/scene_sync.dart`), read off the document itself so a skinned
/// object's picture carries the joint/weight attributes [_withSkin] reads
/// back off it — `tut-10`'s own fix.
VertexLayout _layoutFor(ModelObject object) =>
    object.skeletonIndex == null ? VertexLayout.standard : VertexLayout.skinned;

/// The buffers [object] draws as — [ModelObject.geometry] run through its own
/// modifier stack first, when it has at least one enabled slot, or straight
/// through [_meshDataOf]/[_editedMeshDataFor] otherwise, then [_withSkin]
/// when [object] is bound to a skeleton. `tut-06`'s own fix: before it, every
/// picture drawn here read the geometry directly, and a mirror or an array
/// modifier never appeared in one until "Apply" baked it in and dropped the
/// stack.
MeshData _meshDataFor(
  ModifierEvaluationCache cache,
  ModelProject project,
  ModelObject object,
  int? weightsJoint,
) {
  final layout = _layoutFor(object);
  final hasEnabledModifier = object.modifiers.any(
    (ModifierSlot slot) => slot.enabled,
  );
  final evaluated = hasEnabledModifier
      ? cache.evaluatedMesh(project, object)
      : null;
  final data = evaluated != null
      ? evaluated.toMeshData(layout: layout)
      : _rawMeshDataFor(project, object, layout, weightsJoint);

  final skeletonIndex = object.skeletonIndex;
  if (skeletonIndex == null ||
      skeletonIndex < 0 ||
      skeletonIndex >= project.skeletons.length) {
    return data;
  }
  return _withSkin(
    data,
    project,
    object,
    project.skeletons[skeletonIndex],
    layout,
  );
}

/// [object]'s own geometry, read at [layout] with neither a modifier stack
/// nor a skeleton folded in — the raw mesh underneath both.
MeshData _rawMeshDataFor(
  ModelProject project,
  ModelObject object,
  VertexLayout layout,
  int? weightsJoint,
) {
  if (object.geometry case EditedGeometry(:final mesh)) {
    return _editedMeshDataFor(project, object, mesh, layout, weightsJoint);
  }
  return _meshDataOf(object.geometry, layout);
}

/// [mesh] as [layout], with [object]'s own shape-key blend (`tut-10`) and
/// weight-gradient bake (`tut-11`) folded in when either applies — the
/// ordinary case (neither) takes the plain, cheap [EditMesh.toMeshData] path
/// unchanged.
///
/// **Building [MeshLayoutPlan] a second time, deliberately.**
/// [EditMesh.toMeshData] keeps its own plan privately; a caller that needs
/// the GPU row ↔ document vertex map [MeshLayoutPlan.gpuVertexToVertex]
/// gives — which both the shape blend and the gradient bake need, the same
/// way `weight_gradient.dart`'s own `paintWeightGradient` does — has to build
/// its own, with the identical `layout` [EditMesh.toMeshData] would use, so
/// the two plans agree row for row. A second build costs nothing worth
/// avoiding next to drawing the picture.
MeshData _editedMeshDataFor(
  ModelProject project,
  ModelObject object,
  EditMesh mesh,
  VertexLayout layout,
  int? weightsJoint,
) {
  final blend = object.shapeSet.keys.isNotEmpty;
  final gradient = _isWeightsTarget(project, object, weightsJoint);
  if (!blend && !gradient) return mesh.toMeshData(layout: layout);

  final plan = MeshLayoutPlan()..build(mesh, layout: layout);
  final buffer = Float32List(plan.vertexCount * plan.floatsPerVertex);
  plan.fillVertices(mesh, buffer);
  var drawn = MeshData(
    layout: layout,
    vertices: buffer,
    indices: Uint32List.fromList(
      Uint32List.sublistView(plan.indices, 0, plan.triangleCount * 3),
    ),
  );
  if (layout.has(VertexLayout.tangent)) drawn = drawn.withGeneratedTangents();

  if (blend) {
    drawn = _withShapeBlend(drawn, plan, mesh, object.shapeSet, layout);
  }
  if (gradient) {
    drawn = _withWeightGradient(
      drawn,
      plan,
      mesh,
      project,
      object,
      weightsJoint!,
      layout,
    );
  }
  return drawn;
}

/// [data]'s own position channel, with [shapeSet]'s own keys blended in at
/// their current weights — `tut-10`'s own fix. [ShapeKey.blend]'s formula
/// (`base + Σ weightᵢ × deltaᵢ`), run through [shapeKeyMorphTargets] so the
/// deltas already line up with [plan]'s own GPU rows the way a hard edge or
/// a UV seam needs — see that function's own doc comment.
MeshData _withShapeBlend(
  MeshData data,
  MeshLayoutPlan plan,
  EditMesh mesh,
  ShapeSet shapeSet,
  VertexLayout layout,
) {
  final targets = shapeKeyMorphTargets(plan, mesh, shapeSet.keys);
  final positionOffset = layout.floatOffsetOf(VertexLayout.position.name);
  final stride = layout.floatsPerVertex;
  final out = Float32List.fromList(data.vertices);
  for (var k = 0; k < targets.length; k++) {
    final weight = k < shapeSet.weights.length ? shapeSet.weights[k] : 0.0;
    if (weight == 0.0) continue;
    final deltas = targets[k].positions;
    for (var row = 0; row < plan.vertexCount; row++) {
      final base = row * stride + positionOffset;
      final d = row * 3;
      out[base] += deltas[d] * weight;
      out[base + 1] += deltas[d + 1] * weight;
      out[base + 2] += deltas[d + 2] * weight;
    }
  }
  return MeshData(layout: data.layout, vertices: out, indices: data.indices);
}

/// Whether [object] is what a weights picture paints: an [EditedGeometry]
/// mesh, bound to the skeleton that owns [weightsJoint]. Everything else
/// draws its own material — see `RenderShading.weights`' own doc comment.
bool _isWeightsTarget(
  ModelProject project,
  ModelObject object,
  int? weightsJoint,
) {
  if (weightsJoint == null) return false;
  if (object.geometry is! EditedGeometry) return false;
  final skeletonIndex = object.skeletonIndex;
  if (skeletonIndex == null ||
      skeletonIndex < 0 ||
      skeletonIndex >= project.skeletons.length) {
    return false;
  }
  return project.skeletons[skeletonIndex].joints.contains(weightsJoint);
}

/// [data]'s own colour channel, overwritten with [weightGradientColor] of
/// each GPU row's own weight on [weightsJoint] — `tut-11`'s own fix, the
/// headless half of `weight_gradient.dart`'s own live `paintWeightGradient`.
MeshData _withWeightGradient(
  MeshData data,
  MeshLayoutPlan plan,
  EditMesh mesh,
  ModelProject project,
  ModelObject object,
  int weightsJoint,
  VertexLayout layout,
) {
  final colorOffset = layout.floatOffsetOf(VertexLayout.color.name);
  if (colorOffset < 0) return data;
  final skeleton = project.skeletons[object.skeletonIndex!];
  final localJoint = skeleton.joints.indexOf(weightsJoint);

  final stride = layout.floatsPerVertex;
  final rowToVertex = plan.gpuVertexToVertex;
  final out = Float32List.fromList(data.vertices);
  for (var row = 0; row < rowToVertex.length; row++) {
    final vertex = rowToVertex[row];
    var weight = 0.0;
    if (vertex >= 0) {
      for (final pair in weightsOf(mesh, vertex)) {
        if (pair.joint == localJoint) weight += pair.weight;
      }
    }
    final color = weightGradientColor(weight);
    final base = row * stride + colorOffset;
    out[base] = color.x;
    out[base + 1] = color.y;
    out[base + 2] = color.z;
    out[base + 3] = color.w;
  }
  return MeshData(layout: data.layout, vertices: out, indices: data.indices);
}

/// The buffers a geometry draws as, at [layout] — the switch
/// `apps/flutter3d_modeler/lib/src/scene_sync.dart`'s own `_dataOf` runs for
/// the live viewport, which this package cannot import.
MeshData _meshDataOf(Geometry geometry, VertexLayout layout) =>
    switch (geometry) {
      ParametricGeometry(:final shape) => shape.drawn.build(layout: layout),
      EditedGeometry(:final mesh) => mesh.toMeshData(layout: layout),
      ImportedGeometry(:final data) => data,
      // A socket draws nothing — see `SocketGeometry`'s own doc comment.
      SocketGeometry() => _emptyMesh,
    };

final MeshData _emptyMesh = MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List(0),
  indices: Uint32List(0),
);

/// [data]'s own position channel, posed through [skeleton]'s own current
/// joint transforms — `tut-10`'s own fix: before it, every mesh drew at its
/// raw bind-pose position regardless of a `PoseJoint`/`RotateBy` anywhere on
/// the project.
///
/// **Baked on the CPU, in [object]'s own local space, rather than handed to
/// the engine's own [Skeleton]/`MeshNode.skeleton` GPU pipeline.** Not
/// because the two conventions disagree — `tut-21` fixed that at the source,
/// `buildSkeleton` itself, so [ProjectSkeleton.inverseBindMatrices] are
/// correct in the engine's own convention whichever pipeline reads them — but
/// because nothing else about a picture built here wants a live skinning setup
/// stood up just to pose one mesh. The formula is deliberately the plain glTF
/// one, `jointMatrix = inverse(meshWorld) * jointWorld * inverseBind`
/// (`Skeleton.update`'s own doc comment, read that first), with no extra
/// correction folded in: an earlier version composed one (an extra
/// `* meshWorld` on each joint's matrix) to compensate for `buildSkeleton`
/// binding in world space rather than the mesh's own local space — real, but
/// the wrong place to fix it, since every other reader of the same skeleton
/// (the live viewport's GPU pipeline, the shadow and object-pick passes) had
/// no such workaround and skinned every non-identity mesh transform wrong.
/// `buildSkeleton` now bakes the correction into the inverse-bind matrices
/// itself; the two are the same composition, reassociated, so a picture's
/// numbers do not change.
///
/// **The mesh's own world transform is read once and treated as bind pose.**
/// Nothing in this build animates an object's own transform independently of
/// its skeleton — a character's mesh sits still and its joints move.
///
/// A joint id the skeleton names that [project] no longer holds, or a weight
/// naming a joint slot past the skeleton's joints, leaves that vertex wherever
/// its other influences already put it — the same "no data, no effect" rule
/// [ShapeKey.grownTo] states for a shape key that has not caught up with a
/// topology edit either.
MeshData _withSkin(
  MeshData data,
  ModelProject project,
  ModelObject object,
  ProjectSkeleton skeleton,
  VertexLayout layout,
) {
  final positionOffset = layout.floatOffsetOf(VertexLayout.position.name);
  final jointsOffset = layout.floatOffsetOf(VertexLayout.joints.name);
  final weightsOffset = layout.floatOffsetOf(VertexLayout.weights.name);
  if (positionOffset < 0 || jointsOffset < 0 || weightsOffset < 0) return data;

  final meshWorld = worldTransformOf(project, object.id);
  final invMeshWorld = Matrix4.copy(meshWorld)..invert();
  final jointMatrices = <Matrix4>[
    for (var i = 0; i < skeleton.joints.length; i++)
      Matrix4.copy(invMeshWorld)
        ..multiply(worldTransformOf(project, skeleton.joints[i]))
        ..multiply(skeleton.inverseBindMatrices[i]),
  ];

  final stride = layout.floatsPerVertex;
  final vertexCount = data.vertices.length ~/ stride;
  final out = Float32List.fromList(data.vertices);
  for (var v = 0; v < vertexCount; v++) {
    final base = v * stride;
    final local = Vector3(
      out[base + positionOffset],
      out[base + positionOffset + 1],
      out[base + positionOffset + 2],
    );
    final skinned = Vector3.zero();
    var weightSum = 0.0;
    for (var slot = 0; slot < 4; slot++) {
      final weight = out[base + weightsOffset + slot];
      if (weight == 0.0) continue;
      final jointIndex = out[base + jointsOffset + slot].round();
      if (jointIndex < 0 || jointIndex >= jointMatrices.length) continue;
      skinned.addScaled(
        jointMatrices[jointIndex].transformed3(Vector3.copy(local)),
        weight,
      );
      weightSum += weight;
    }
    if (weightSum <= 0.0) continue;
    skinned.scale(1.0 / weightSum);
    out[base + positionOffset] = skinned.x;
    out[base + positionOffset + 1] = skinned.y;
    out[base + positionOffset + 2] = skinned.z;
  }
  return MeshData(layout: data.layout, vertices: out, indices: data.indices);
}

/// Unlit and white, so [_withWeightGradient]'s own vertex colour is the whole
/// of what shows — the same material `weight_gradient.dart`'s own
/// `kWeightGradientMaterial` gives the live viewport's weights view: a
/// diagnostic colour is not a picture of light.
final Material _weightsGradientMaterial = Material(
  name: 'weights',
  lighting: LightingModel.unlit,
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
