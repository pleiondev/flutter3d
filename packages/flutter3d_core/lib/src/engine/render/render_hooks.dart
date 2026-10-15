/// The hooks into how a renderer chooses what to draw and when (D22b): what
/// a view's draw list keeps and in what order, which level of detail a group
/// shows, how a skinned mesh is skinned, whether a frame is held, and which
/// quality row a frame is drawn at.
///
/// Each hook is an `abstract base` class whose methods take one context
/// object that can gain members, and answer null (or do nothing) by default,
/// which is the engine's own choice. A plugin registers the renderer's with
/// [RenderHooks] (`host.registry<RenderHooks>()`, beside the render steps);
/// `FramePacing` and `AdaptiveQuality` take theirs directly.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart' show MeshData, VertexLayout;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show GraphicsDevice, StorageBuffer;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry, PluginScope, Registration;
import 'package:flutter3d_shaders/kernel.dart' show ComputeKernel;

import '../animation/skin_blend.dart';
import '../scene/camera_node.dart';
import '../scene/lod_group.dart';
import '../scene/mesh_node.dart';
import 'compute_step.dart';
import 'quality_table.dart';
import 'render_view.dart';

/// What a [DrawListHook] is asked about one mesh of one view.
///
/// One per renderer, filled again for every mesh: read it within the call,
/// and keep nothing of it.
final class DrawListContext {
  DrawListContext._();

  late MeshNode _node;
  late CameraView _view;
  double _viewDepth = 0.0;

  /// The mesh.
  MeshNode get node => _node;

  /// The view whose list it is in.
  CameraView get view => _view;

  /// How far in front of the view's eye its bounds' centre is, in metres
  /// along the view axis.
  double get viewDepth => _viewDepth;
}

/// A plugin's say in a view's draw list (D22b): which meshes it keeps, and
/// the order they are drawn in.
///
/// Asked after the engine's own tests — visibility, layers, the frustum and
/// the occlusion — so a hook only ever narrows what is drawn. Extendable
/// outside this package, and stays so through 1.x.
abstract base class DrawListHook {
  const DrawListHook();

  /// Whether [context]'s mesh is drawn in its view. Every hook must keep a
  /// mesh for it to be drawn; true by default.
  bool keeps(DrawListContext context) => true;

  /// The mesh's place in the view's order, below its draw bucket: a number
  /// from nought to 2³⁵ − 1, smaller drawn first, or null for the order the
  /// view's `SortMode` gives. The first hook to answer decides.
  int? sortKey(DrawListContext context) => null;
}

/// What a [LodPolicy] is asked about one group for one view.
final class LodContext {
  const LodContext({
    required this.group,
    required this.camera,
    required this.choice,
    this.viewportHeight,
  });

  /// The group choosing.
  final LodGroup group;

  /// The camera it is chosen for.
  final CameraNode camera;

  /// The level the engine's own rule chose, by index.
  final int choice;

  /// The view's height in pixels, or null where there is none.
  final double? viewportHeight;
}

/// Which level of detail a group shows (D22b): the engine's rule by screen
/// fraction and pixel error, or a plugin's own — by distance to a point of
/// interest, by a budget of triangles, by importance.
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class LodPolicy {
  const LodPolicy();

  /// The level [context]'s group shows, by index (clamped to its levels),
  /// or null for [LodContext.choice].
  int? select(LodContext context) => null;
}

/// What a [SkinningHook] is asked about one skinned mesh, and where it
/// writes the answer.
///
/// **One context that can grow**, never a list of parameters that does: a
/// later minor adds members here, and a hook written against this one keeps
/// compiling. [claims](SkinningHook.claims) is asked with [node] and
/// [jointMatrices] alone; [record](SkinningHook.record) with the rest too.
final class SkinningContext {
  const SkinningContext({
    required this.node,
    required this.jointMatrices,
    this.device,
    this.output,
    this.compute,
  });

  /// The skinned mesh.
  final MeshNode node;

  /// Its joints' matrices, sixteen column-major floats a joint — what the
  /// engine's skinned vertex stage reads.
  final Float32List jointMatrices;

  /// The device [output] lives on: the one drawing the frame, or the one
  /// [compute] runs on. Null while the hook is only asked [SkinningHook.claims].
  final GraphicsDevice? device;

  /// Where the skinned vertices go: [vertexCount] vertices in
  /// [VertexLayout.standard] — position, normal, texture coordinate, tangent
  /// and colour, the skinned layout without its joints and weights — which
  /// the mesh pass binds as the mesh's vertices this frame. A buffer
  /// resource of the frame (`FrameResourceIds.skinnedVertices`), written
  /// before the scene draws. Null while the hook is only asked
  /// [SkinningHook.claims].
  final StorageBuffer? output;

  /// The compute pass the hook's [SkinningHook.kernels] run in — the
  /// executor its step was placed on, its device and each kernel's stage —
  /// or null for a [HostSkinningHook], which computes on the host.
  final ComputeContext? compute;

  /// How many vertices the mesh has, and so how many [output] holds.
  int get vertexCount => node.mesh.vertexCount;
}

/// How a skinned mesh is skinned (D22b), beside the engine's own four-joint
/// linear blend in `mesh_skinned.vert`.
///
/// **A compute pass that writes a buffer the mesh pass draws.** A hook
/// [claims] the meshes it skins, names the [kernels] it skins with, and for
/// each claimed mesh [record]s a pass that writes the skinned vertices into
/// [SkinningContext.output]; the scene draws that buffer as an unskinned
/// mesh. It is placed like any `ComputeStep`
/// (`RendererSteps.placeSkinningHook`): on the device drawing the frame,
/// where the vertices never leave the GPU, or on the CPU, which fills the
/// same buffer from the host. A hook that computes on the host without
/// kernels is a [HostSkinningHook].
///
/// The shadow passes, the pick pass and the instanced draws skin with the
/// engine's own stage still; a hook changes what the scene shows.
///
/// Extendable outside this package, and stays so through 1.x: a member
/// added later arrives with a default, and every method takes the one
/// growing context.
abstract base class SkinningHook {
  const SkinningHook();

  /// Whether this hook skins [context]'s mesh. False by default.
  bool claims(SkinningContext context) => false;

  /// The kernels [record] dispatches, as a `ComputeStep`'s are: what
  /// placing the hook loads where it lands. Where that is, the hardware
  /// layer says: since 1.0.0-rc.1+1 a hook demands no placement.
  List<ComputeKernel> get kernels => const <ComputeKernel>[];

  /// Records the skinning of [context]'s mesh into its
  /// [SkinningContext.output], through [SkinningContext.compute]. True when
  /// it wrote the vertices; false leaves the mesh to the engine's own
  /// skinning this frame, which is the default.
  bool record(SkinningContext context) => false;
}

/// A [SkinningHook] that computes the skinned vertices on the host, as a
/// list of floats, and has the frame upload them.
///
/// **The synchronous shape, as an adapter of the compute one**: [skin]
/// answers the vertices in the mesh's own layout, as `SkinBlend.vertices`
/// holds them, and [record] writes their standard part into the output on
/// the drawing device — an upload, never a readback. It has no kernels and
/// needs no placement.
abstract base class HostSkinningHook extends SkinningHook {
  const HostSkinningHook();

  /// The skinned vertices of [context]'s mesh, in its own layout and
  /// stride, or null to leave it to the engine this frame.
  Float32List? skin(SkinningContext context);

  @override
  bool record(SkinningContext context) {
    final device = context.device;
    final output = context.output;
    if (device == null || output == null) return false;
    final vertices = skin(context);
    if (vertices == null) return false;
    final layout = context.node.mesh.source?.layout ?? VertexLayout.skinned;
    device.writeBuffer(
      output,
      0,
      ByteData.sublistView(
        standardVertices(vertices, layout, context.vertexCount),
      ),
    );
    return true;
  }
}

/// [vertices] in [layout], as [vertexCount] vertices of
/// [VertexLayout.standard]: the attributes the standard layout has, in its
/// order, copied float for float.
Float32List standardVertices(
  Float32List vertices,
  VertexLayout layout,
  int vertexCount,
) {
  const standard = VertexLayout.standard;
  final from = layout.floatsPerVertex;
  final to = standard.floatsPerVertex;
  final out = Float32List(vertexCount * to);
  // The standard layout is the skinned one's prefix, so the common case is
  // one copy a vertex.
  final prefix = <int>[
    for (final attribute in standard.attributes)
      layout.floatOffsetOf(attribute.name),
  ];
  for (var v = 0; v < vertexCount; v++) {
    var at = 0;
    for (var a = 0; a < standard.attributes.length; a++) {
      final width = standard.attributes[a].componentCount;
      final source = prefix[a];
      for (var i = 0; i < width; i++) {
        out[v * to + at + i] = source < 0
            ? 0.0
            : vertices[v * from + source + i];
      }
      at += width;
    }
  }
  return out;
}

/// The engine's own CPU skinning — `SkinBlend`, the four-joint linear blend
/// `mesh_skinned.vert` computes — as a [HostSkinningHook]: every skinned
/// mesh whose source data was kept, skinned on the host and drawn from the
/// uploaded buffer.
final class LinearBlendSkinning extends HostSkinningHook {
  LinearBlendSkinning();

  final Expando<SkinBlend> _blends = Expando<SkinBlend>();

  @override
  bool claims(SkinningContext context) =>
      context.node.mesh.source?.layout.isSkinned ?? false;

  @override
  Float32List? skin(SkinningContext context) {
    final MeshData? source = context.node.mesh.source;
    if (source == null || !source.layout.isSkinned) return null;
    final blend = _blends[source] ??= SkinBlend(source);
    blend.blend(context.jointMatrices);
    return blend.vertices;
  }
}

/// What a [PacingPolicy] is asked before a frame is drawn.
final class PacingContext {
  const PacingContext({
    required this.frameIndex,
    required this.unfinishedFrames,
    required this.framesInFlight,
    required this.gpuIsBehind,
  });

  /// The frame about to be drawn.
  final int frameIndex;

  /// How many frames the GPU has not finished.
  final int unfinishedFrames;

  /// How many frames the pacing allows in flight.
  final int framesInFlight;

  /// Whether the engine's own rule finds the GPU behind by every frame in
  /// flight — what holds a frame when `FramePacing.holdWhenBehind` is on.
  final bool gpuIsBehind;
}

/// Whether a frame is held — the last picture handed back again, nothing
/// drawn — or drawn (D22b): the engine's rule, or a plugin's own (a frame
/// held only when the GPU is two behind, a cap on frames a second).
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class PacingPolicy {
  const PacingPolicy();

  /// True to hold [context]'s frame, false to draw it, null for the
  /// engine's rule. Never asked while the renderer warms up, on a first
  /// frame or on a resized one, which have no picture to hand back.
  bool? hold(PacingContext context) => null;
}

/// What a [QualityPolicy] is asked once a frame's time is recorded.
final class QualityContext {
  const QualityContext({
    required this.table,
    required this.micros,
    required this.motion,
    required this.current,
    required this.choice,
  });

  /// The quality table chosen from.
  final QualityTable table;

  /// What the frame took, in microseconds.
  final int micros;

  /// How far the picture moved, as a fraction of the screen's width.
  final double motion;

  /// The row the frame was drawn at, by index.
  final int current;

  /// The row the engine's rule moves to, by index.
  final int choice;
}

/// Which quality row the next frame is drawn at (D22b): `AdaptiveQuality`'s
/// rule, or a plugin's own.
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class QualityPolicy {
  const QualityPolicy();

  /// The row [context]'s next frame is drawn at, by index (clamped to the
  /// table), or null for [QualityContext.choice].
  int? choose(QualityContext context) => null;
}

/// A renderer's hooks into what it draws (D22b): the draw-list hooks, the
/// level-of-detail policy and the skinning hooks plugins registered.
///
/// Reached by a plugin as `host.registry<RenderHooks>()`, a companion of
/// the render steps; an application uses `Renderer.hooks`.
final class RenderHooks extends PluginRegistry {
  /// A renderer's, with nothing registered.
  RenderHooks() : _store = _HookStore(), _scope = null;

  RenderHooks._scoped(this._store, this._scope);

  final _HookStore _store;
  final PluginScope? _scope;

  /// The draw-list hooks, in the order they were added. A view of the
  /// renderer's own list, read for every mesh of every view, so it is not
  /// copied.
  List<DrawListHook> get drawListHooks => _store.drawListView;

  /// The level-of-detail policy, the one added last; null for the
  /// engine's rule.
  LodPolicy? get lodPolicy => _store.lod.lastOrNull;

  /// The skinning hooks, in the order they were added: what an application
  /// or a tool lists to say who skins what.
  List<SkinningHook> get skinningHooks =>
      List<SkinningHook>.unmodifiable(_store.skinning);

  /// Adds [hook] to every view's draw list until the result is cancelled.
  Registration addDrawListHook(DrawListHook hook) =>
      _add(_store.drawList, hook);

  /// Makes [policy] choose every group's level until the result is
  /// cancelled; the one added last decides.
  Registration addLodPolicy(LodPolicy policy) => _add(_store.lod, policy);

  /// Lists [hook] among the skinning hooks until the result is cancelled.
  ///
  /// **A listed hook does not skin by being listed**: it skins once
  /// `RendererSteps.placeSkinningHook` has placed it, which lists it too.
  /// This is for a tool that keeps its own account of who skins what.
  Registration addSkinningHook(SkinningHook hook) =>
      _add(_store.skinning, hook);

  Registration _add<T>(List<T> into, T hook) {
    into.add(hook);
    final registration = Registration(() => into.remove(hook));
    _scope?.track(registration);
    return registration;
  }

  @override
  RenderHooks forPlugin(PluginScope scope) =>
      RenderHooks._scoped(_store, scope);
}

/// What the draw list needs from [RenderHooks], and nobody else. Not
/// exported by `flutter3d_core.dart`.
extension RenderHooksInternals on RenderHooks {
  /// The context a draw-list hook is handed, filled for [node] in [view].
  DrawListContext contextFor(MeshNode node, CameraView view, double depth) =>
      _store.context
        .._node = node
        .._view = view
        .._viewDepth = depth;
}

final class _HookStore {
  final List<DrawListHook> drawList = <DrawListHook>[];
  late final UnmodifiableListView<DrawListHook> drawListView =
      UnmodifiableListView<DrawListHook>(drawList);
  final List<LodPolicy> lod = <LodPolicy>[];
  final List<SkinningHook> skinning = <SkinningHook>[];
  final DrawListContext context = DrawListContext._();
}
