/// `renderProject`: a [ModelProject] drawn to a PNG with no window and no
/// Flutter SDK behind it — `mcp-05n`'s own row, the render half of "an agent
/// that can see the model" (`doc/model-editor-plan.md`).
///
/// **A third copy of the same nine-line switch, and that is deliberate.**
/// `apps/flutter3d_modeler/lib/src/scene_sync.dart`'s own `_dataOf` is the
/// live viewport's — an application, and `flutter3d_model_core` may not
/// depend on the application that owns it (`no package depends on an
/// application`, `tool/structure/rules.dart`). `flutter3d_render_job/lib/src/
/// scene_from_project.dart`'s own copy is a Flutter package's: it depends on
/// `flutter: sdk` because `flutter3d`'s own re-export of the renderer still
/// carries three Flutter-named symbols beside it — its own pubspec says so.
/// This package starts under a bare `dart run`, which cannot resolve a graph
/// with the Flutter SDK anywhere in it, so neither existing copy can be
/// depended on here. Spelling the switch a third time costs nine lines; a
/// fourth package built only to share them would cost more than that to
/// read.
///
/// **[renderProject] takes its device, rather than building a [CpuDevice] of
/// its own — this file names no concrete backend at all.** `flutter3d_cpu`'s
/// own `lib/` is Flutter-free, but its pubspec still dev-depends on
/// `flutter3d_conformance` and `flutter3d_shaders` (real dependencies of
/// theirs, for `conformance_test.dart` and `shader_names_test.dart`), and
/// this workspace's shared lock resolves a dev dependency the same as a real
/// one (`tool/structure/rules.dart`'s own `pubspecDependencies`, and the
/// reason its doc comment gives: `dart test` resolves those too). A direct
/// dependency on `flutter3d_cpu` would carry that chain straight into this
/// package and `flutter3d_model_mcp` above it, both of which `dart run` has
/// to resolve with no Flutter SDK on the machine at all. `TileDevice` in
/// `flutter3d_render_job/lib/src/render_snapshot_job.dart` takes the same
/// shape for the same underlying reason — a device is asked for, not built —
/// though that package can still default it to [CpuDevice] because it is a
/// Flutter package regardless. This one cannot default it to anything: the
/// caller supplies a working [GraphicsDevice] factory, typically
/// `flutter3d_cpu`'s own `cpuTileDevice`-shaped function, or a fake in a
/// test that only wants to exercise the scene-building and framing logic.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

import 'project.dart';

/// The six axis views plus a three-quarter angle.
///
/// A final class with const instances, not an enum — `tool/structure/
/// rules.dart`'s own "an enum in a published package is machinery or is not
/// an enum" rule: this package is published, and a value added here later
/// (an agent's own custom angle, say) must not break every `switch` a caller
/// already wrote against it, the same reasoning [LightingModel] itself is
/// built the same way for.
///
/// `apps/flutter3d_modeler/lib/src/display_modes.dart`'s own `StandardView`
/// names the first six identically — spelled again rather than shared for
/// the same reason [ModelProject] cannot import that application — plus
/// [iso], which a screen with its own orbiting camera has no need to name
/// but a single still picture does: an agent asking "show me the model"
/// wants the one framing nothing is ever square-on to, where an edge pointed
/// straight at the lens does not vanish into a line the way it can from any
/// of the six axis views alone.
final class RenderProjectView {
  const RenderProjectView._(this.name, this.yaw, this.pitch);

  final String name;

  /// Camera placement, in the same `yaw`/`pitch` vocabulary
  /// `OrbitController.apply` turns into a position — see [_frame].
  final double yaw;
  final double pitch;

  static const RenderProjectView front = RenderProjectView._('front', 0.0, 0.0);
  static const RenderProjectView back = RenderProjectView._(
    'back',
    math.pi,
    0.0,
  );
  static const RenderProjectView right = RenderProjectView._(
    'right',
    math.pi / 2,
    0.0,
  );
  static const RenderProjectView left = RenderProjectView._(
    'left',
    -math.pi / 2,
    0.0,
  );
  static const RenderProjectView top = RenderProjectView._(
    'top',
    0.0,
    _maxPitch,
  );
  static const RenderProjectView bottom = RenderProjectView._(
    'bottom',
    0.0,
    -_maxPitch,
  );
  static const RenderProjectView iso = RenderProjectView._(
    'iso',
    math.pi / 4,
    math.pi / 6,
  );

  static const List<RenderProjectView> values = <RenderProjectView>[
    front,
    back,
    left,
    right,
    top,
    bottom,
    iso,
  ];

  @override
  String toString() => 'RenderProjectView.$name';
}

/// Just short of the poles, the same clamp `OrbitController`'s own
/// `_kMaxPitch` uses: looking straight down makes the up vector ambiguous and
/// [SceneNode.lookAt] has no good answer for it.
const double _maxPitch = math.pi / 2 - 0.01;

/// What a surface is drawn as.
///
/// A final class with const instances for the same reason
/// [RenderProjectView] is one, not an enum. Two instances, not the four
/// `mcp-08n`'s own row eventually names. [material] and [normals] are real,
/// distinct shaders today (`LightingModel.pbr`/`LightingModel.unlit` and
/// `LightingModel.normals`, both already compiled into every backend's
/// shader bundle). `wireframe` waits on `view-07`'s own edge-drawing landing
/// in the engine — there is no member for it here rather than one that draws
/// the same picture [material] does under a name that promises otherwise.
/// `selection` is not a shading mode; see [RenderRequest.selection] for how
/// it is drawn instead.
final class RenderShading {
  const RenderShading._(this.name);

  final String name;

  static const RenderShading material = RenderShading._('material');
  static const RenderShading normals = RenderShading._('normals');

  static const List<RenderShading> values = <RenderShading>[material, normals];

  @override
  String toString() => 'RenderShading.$name';
}

/// What [renderProject] draws, and how.
final class RenderRequest {
  RenderRequest({
    required this.project,
    this.view = RenderProjectView.iso,
    this.width = 512,
    this.height = 512,
    this.shading = RenderShading.material,
    this.selection = const <int>{},
  });

  final ModelProject project;
  final RenderProjectView view;
  final int width;
  final int height;
  final RenderShading shading;

  /// Object ids drawn tinted towards orange — an agent's own "this is the
  /// thing I mean" alongside a picture, in the same vocabulary `select`'s own
  /// tool argument already names objects with. See [_materialFor] for why
  /// the tint lives in `baseColor` rather than `emissive`.
  final Set<int> selection;
}

/// Why [renderProject] declined to draw.
///
/// Named rather than left as a bare [ArgumentError]: the acceptance text asks
/// for "a refusal that names the limit," which a caller reads out of
/// [message] without parsing an arbitrary error string.
final class RenderRefusal implements Exception {
  RenderRefusal(this.message);

  final String message;

  @override
  String toString() => 'RenderRefusal: $message';
}

/// Above this, a tile grid is the right answer — `pro-rn-02`'s own
/// `RenderSnapshotJob` — and a single-shot agent tool is the wrong tool for
/// the job it would be doing.
const int _maxRenderDimension = 1024;

/// [request.project] drawn from [request.view], as PNG bytes, on a device
/// [deviceFactory] builds for the occasion — see this library's own doc
/// comment for why that is a parameter rather than a [CpuDevice] built here.
///
/// **The two lights are the exact numbers three call sites now share.**
/// `apps/flutter3d_modeler/lib/src/staging.dart`'s `ModelerStage.fromProject`
/// (the live viewport), `flutter3d_render_job`'s `sceneFromProject` (the
/// in-app snapshot job) and this function all point one directional light
/// from `(-0.5, -1.0, -0.6)` at intensity 3.2 and a second from
/// `(0.7, -0.3, 0.8)` at 1.1 — so a picture this function draws of a corner
/// of a project reads the same brightness as the other two, without any of
/// the three needing to import another to get it right.
///
/// Throws [RenderRefusal] for a size outside 1×1..1024×1024, before
/// [deviceFactory] is ever called.
Future<Uint8List> renderProject(
  RenderRequest request, {
  required GraphicsDevice Function(int width, int height) deviceFactory,
}) async {
  final width = request.width;
  final height = request.height;
  if (width < 1 ||
      height < 1 ||
      width > _maxRenderDimension ||
      height > _maxRenderDimension) {
    throw RenderRefusal(
      'renderProject draws from 1×1 up to '
      '$_maxRenderDimension×$_maxRenderDimension; asked for $width×$height.',
    );
  }

  final device = deviceFactory(width, height);
  final fallbackNormal = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(Uint8List.fromList(<int>[128, 128, 255, 255])),
  )!;
  final renderer = Renderer.create(
    device: device,
    fallbackNormal: fallbackNormal,
  );

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

  // Two passes, because an object may be listed before its parent: every
  // node made first, then hung under its parent's node, or under the scene
  // for an object with no parent or one the project no longer holds.
  final nodes = <int, MeshNode>{
    for (final ModelObject object in request.project.objects)
      object.id: MeshNode(
        DeviceMesh.upload(device, _meshDataOf(object.geometry)),
        _materialFor(request, object),
        name: object.name,
      )..setLocalMatrix(object.transform),
  };
  for (final ModelObject object in request.project.objects) {
    final node = nodes[object.id]!;
    switch (nodes[object.parent]) {
      case final MeshNode parent:
        parent.add(node);
      case null:
        scene.add(node);
    }
  }

  final camera = CameraNode(name: 'renderProject');
  scene.add(camera);
  _frame(camera, nodes.values, request.view);

  final frame = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = (await device.readPixels(frame.frame))!.buffer.asUint8List();
  return encodeCompressedPng(width, height, pixels);
}

/// Places [camera] so every mesh in [nodes] fits inside its own field of
/// view, seen from [view].
///
/// The world bounding box comes from each node's own [MeshGeometry.bounds]
/// (local space) carried through its [SceneNode.worldMatrix] — not from the
/// project's untransformed geometry, so a scaled or offset object is framed
/// where it actually stands, the same way `OrbitController`'s own framing
/// (`packages/flutter3d_core/lib/src/engine/scene/orbit_controller.dart`)
/// works from a target and a distance rather than raw vertices.
void _frame(
  CameraNode camera,
  Iterable<MeshNode> nodes,
  RenderProjectView view,
) {
  Aabb3? box;
  for (final node in nodes) {
    final worldBox = Aabb3.copy(node.mesh.bounds)..transform(node.worldMatrix);
    box = box == null ? worldBox : (box..hull(worldBox));
  }
  final center = box?.center ?? Vector3.zero();
  final radius = box == null
      ? 1.0
      : math.max(box.min.distanceTo(box.max) / 2, 0.05);

  final fovY = switch (camera.projection) {
    PerspectiveProjection(:final fovYRadians) => fovYRadians,
    _ => math.pi / 4,
  };
  // A margin over the tight fit, so an object's silhouette does not touch
  // the frame's own edge.
  final distance = radius / math.sin(fovY / 2) * 1.2;

  final cosPitch = math.cos(view.pitch);
  final offset = Vector3(
    math.sin(view.yaw) * cosPitch,
    math.sin(view.pitch),
    math.cos(view.yaw) * cosPitch,
  )..scale(distance);
  camera
    ..setPosition(center.x + offset.x, center.y + offset.y, center.z + offset.z)
    ..lookAt(center);
}

/// The buffers a geometry draws as. See this library's own doc comment for
/// why this switch has two other copies rather than one shared function.
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

/// [object]'s material, from its project material and [request]'s own
/// [RenderRequest.shading] and [RenderRequest.selection].
Material _materialFor(RenderRequest request, ModelObject object) {
  final base = _surfaceMaterialFor(request.project, object);
  final shaded = request.shading == RenderShading.normals
      ? Material(
          name: base.name,
          lighting: LightingModel.normals,
          baseColor: base.baseColor,
          doubleSided: base.doubleSided,
        )
      : base;
  if (!request.selection.contains(object.id)) return shaded;
  // Blended into `baseColor` itself, not left to `emissive`: the CPU backend
  // only ever reads `Material.emissive` behind a bound `emissiveTexture`
  // (`applyEmissiveMap` in `flutter3d_cpu/lib/src/cpu_shaders_surface.dart`
  // returns before touching it otherwise), so a highlight with no texture of
  // its own would be set and never drawn. A colour every lighting model
  // already samples has no such gate.
  final highlight = Vector4(1.0, 0.55, 0.0, shaded.baseColor.a);
  return Material(
    name: shaded.name,
    lighting: shaded.lighting,
    baseColor: Vector4(
      shaded.baseColor.r * 0.4 + highlight.r * 0.6,
      shaded.baseColor.g * 0.4 + highlight.g * 0.6,
      shaded.baseColor.b * 0.4 + highlight.b * 0.6,
      shaded.baseColor.a,
    ),
    metallic: shaded.metallic,
    roughness: shaded.roughness,
    doubleSided: shaded.doubleSided,
  );
}

/// [object]'s first material slot, translated field for field into the
/// engine's own [Material] — or a plain grey [Material] when it names none,
/// the same fallback `MaterialPool.forObject` answers with as `clay()`.
Material _surfaceMaterialFor(ModelProject project, ModelObject object) {
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
