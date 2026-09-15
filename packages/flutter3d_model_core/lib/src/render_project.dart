/// `renderProject`: a [ModelProject] drawn to a PNG with no window and no
/// Flutter SDK behind it — `mcp-05n`'s own row, the render half of "an agent
/// that can see the model" (`doc/model-editor-plan.md`).
///
/// **The scene comes from `sceneFromProject`, the one builder this package
/// has.** A tiled snapshot (`RenderSnapshotJob`, beside this file) draws the
/// same scene; what this adds is an agent's framing — seven named views fitted
/// to the model — and two ways of shading it.
///
/// **[renderProject] takes its device, rather than building a [CpuDevice] of
/// its own — this file names no concrete backend at all.** This package is
/// the modeller's document layer: it starts under a bare `dart run` and says
/// what a picture of a project is, not which backend draws it. The caller
/// supplies a working [GraphicsDevice] factory — typically one over
/// `flutter3d_cpu`'s `CpuDevice` — or a fake in a test that only wants the
/// framing logic.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

import 'lighting_sync.dart';
import 'project.dart';
import 'scene_from_project.dart';

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
/// [RenderProjectView] is one, not an enum. Three instances now, not the
/// four `mcp-08n`'s own row eventually names. [material] and [normals] are
/// real, distinct shaders (`LightingModel.pbr`/`LightingModel.unlit` and
/// `LightingModel.normals`, both already compiled into every backend's
/// shader bundle). [weights] is not a shader at all — `tut-11`'s own fix —
/// see its own doc comment. `wireframe` waits on `view-07`'s own
/// edge-drawing landing in the engine — there is no member for it here
/// rather than one that draws the same picture [material] does under a name
/// that promises otherwise. `selection` is not a shading mode; see
/// [RenderRequest.selection] for how it is drawn instead.
final class RenderShading {
  const RenderShading._(this.name);

  final String name;

  static const RenderShading material = RenderShading._('material');
  static const RenderShading normals = RenderShading._('normals');

  /// The weight-paint gradient — `tut-11`'s own row. Every object with an
  /// [EditedGeometry] mesh bound to [RenderRequest.weightsJoint]'s own
  /// skeleton is coloured by [weightGradientColor] of its own weight on
  /// that joint, unlit; everything else (unskinned, or bound to a different
  /// skeleton) draws as [material] rather than going blank, so a picture of
  /// a scene with more than one object still shows all of it.
  static const RenderShading weights = RenderShading._('weights');

  static const List<RenderShading> values = <RenderShading>[
    material,
    normals,
    weights,
  ];

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
    this.weightsJoint,
  });

  final ModelProject project;
  final RenderProjectView view;
  final int width;
  final int height;
  final RenderShading shading;

  /// Object ids drawn tinted towards orange — an agent's own "this is the
  /// thing I mean" alongside a picture, in the same vocabulary `select`'s own
  /// tool argument already names objects with. See [_restyle] for why the
  /// tint lives in `baseColor` rather than `emissive`.
  final Set<int> selection;

  /// Which joint [RenderShading.weights] paints the gradient for, by its own
  /// [ModelObject.id] — the same id a `PaintWeights`/`SetRig` call already
  /// names a joint with. Meaningless with any other [shading]; with
  /// [RenderShading.weights] and this left null, nothing has a joint to
  /// measure a weight against and every mesh falls back to [material].
  final int? weightsJoint;
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

/// Above this, a tile grid is the right answer — `RenderSnapshotJob` — and a
/// single-shot agent tool is the wrong tool for the job it would be doing.
const int _maxRenderDimension = 1024;

/// [request.project] drawn from [request.view], as PNG bytes, on a device
/// [deviceFactory] builds for the occasion — see this library's own doc
/// comment for why that is a parameter rather than a [CpuDevice] built here.
///
/// **The project's own lights, its skinned pose and its shape-key blend reach
/// the picture — `tut-07` and `tut-10`'s own fix.** Before them, neither a
/// project's own `AddLight`/`SetEnvironment`/`SetSceneLightingField` settings
/// nor a posed skeleton ever reached a headless picture at all; the scene
/// comes from [sceneFromProject], which adds the project's lights through the
/// same `LightingSync` the live viewport uses, and this function reads that
/// sync's render settings too. See `LightingSync`'s own doc comment for why
/// the two fixed lights stay rather than being replaced, and for what
/// [ModelProject.lighting] still does not reach a picture through
/// (`ambientIntensity`, `environment`).
///
/// **`tut-07` also moved bloom and shadows onto [SceneLighting]'s own
/// defaults, which do not match [RenderSettings]'s bare ones — `tut-22`'s
/// own finding.** Before `tut-07`, this function always rendered with
/// `bloom` forced off and `shadows` left at [ShadowSettings]'s own default
/// (`enabled: true`), regardless of the project. Since, both come from
/// [LightingSync.apply] instead: `bloom.enabled` follows
/// `SceneLighting.post.bloomEnabled` (default `true`) and `shadows.enabled`
/// follows `SceneLighting.shadows` (default `false`) — the opposite of each
/// bare default, for *any* project that has never called
/// `SetSceneLightingField` at all. A deliberate change (verified against
/// case 3's and case 4's own reference pictures in the same commit, and by
/// `tut-22`'s own determinism tests below — this function has no clock, no
/// random seed and no unordered iteration on its own render path, so it is
/// not the source of a byte difference), but four other tutorial cases'
/// reference pictures were not regenerated when it landed and quietly went
/// stale — `tut-22`'s own row is the account of finding and fixing that.
/// **Any tutorial case whose fixture never sets `SceneLighting` explicitly
/// is reading these two defaults**, so if either one moves again, every
/// such case's reference pictures need regenerating, not only the ones a
/// commit happens to check by eye.
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

  final scene = sceneFromProject(
    request.project,
    device,
    restyle: (ModelObject object, Material material) =>
        _restyle(request, object, material),
    weightsJoint: request.shading == RenderShading.weights
        ? request.weightsJoint
        : null,
  );
  final camera = CameraNode(name: 'renderProject');
  scene.add(camera);
  _frame(camera, scene.meshes, request.view);

  // `mat-25`'s own light gizmos stay off here even though [LightingSync
  // .apply] would otherwise turn them on the moment [request.project] has a
  // light: those are an editing overlay for the live viewport, and a
  // headless picture — a tutorial page's own "what you get," an agent's own
  // "show me the model" — wants the scene, not the markers pointing at its
  // lights.
  final RenderSettings lit = LightingSync()
      .apply(const RenderSettings(), request.project.lighting)
      .copyWith(debug: const DebugDrawOptions());
  // `tut-11`'s own fix: a vertex colour named by hex is not scene-referred
  // light, and only reads back as that hex with tonemapping and exposure
  // out of the way — the identical pair `weight_gradient.dart`'s own
  // `weightGradientSettings` gives the live viewport's weights view, for
  // the same reason `ShadingMode.normals` gets it there too.
  final RenderSettings settings = request.shading == RenderShading.weights
      ? lit.copyWith(tonemap: false, exposure: 1.0)
      : lit;

  final frame = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings,
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

/// [material], shaded the way [request] asks and tinted when [object] is in
/// its selection.
Material _restyle(
  RenderRequest request,
  ModelObject object,
  Material material,
) {
  final shaded = request.shading == RenderShading.normals
      ? Material(
          name: material.name,
          lighting: LightingModel.normals,
          baseColor: material.baseColor,
          doubleSided: material.doubleSided,
        )
      : material;
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
