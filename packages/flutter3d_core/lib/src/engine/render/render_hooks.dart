/// The hooks into how a renderer chooses what to draw and when (D22b): what
/// a view's draw list keeps and in what order, which level of detail a group
/// shows, how a skinned mesh is skinned, whether a frame is held, and which
/// quality row a frame is drawn at.
///
/// Each hook is an `abstract base` class whose methods take one context
/// object that can gain members, and answer null (or do nothing) by default,
/// which is the engine's own choice. A plugin registers the renderer's with
/// [RenderHooks] (`host.registry<RenderHooks>()`, beside the render steps),
/// each a registration withdrawn with the plugin; an application may also
/// hand `FramePacing` and `AdaptiveQuality` one of its own directly.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart' show MeshData, VertexLayout;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show GraphicsDevice, StorageBuffer;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        NameTakenException,
        PluginException,
        PluginRegistry,
        PluginScope,
        Registration;
import 'package:flutter3d_shaders/kernel.dart' show ComputeKernel;

import '../animation/skin_blend.dart';
import '../scene/camera_node.dart';
import '../scene/lod_group.dart';
import '../scene/mesh_node.dart';
import 'compute_step.dart';
import 'quality_table.dart';
import 'render_view.dart';
import 'shadow_settings.dart';

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
  /// Lets a subclass be const.
  const DrawListHook();

  /// Whether [context]'s mesh is drawn in its view. Every hook must keep a
  /// mesh for it to be drawn; true by default.
  bool keeps(DrawListContext context) => true;

  /// The mesh's place in the view's order, below its draw bucket: a number
  /// from nought to 2³⁵ − 1, smaller drawn first, or null for the order the
  /// view's `SortMode` gives. The first hook to answer decides, in the
  /// order `RenderHooks.drawListHooks` lists them; null passes to the next.
  int? sortKey(DrawListContext context) => null;
}

/// What a [LodPolicy] is asked about one group for one view.
final class LodContext {
  /// What [group] is asked for in [camera]'s view, with the engine's own
  /// [choice] and the viewport's height when it is known.
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
  /// Lets a subclass be const.
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
  /// What a skinning hook is asked about [node] posed by [jointMatrices]; the
  /// rest is given only when the hook records.
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
  /// Lets a subclass be const.
  const SkinningHook();

  /// Whether this hook skins [context]'s mesh. False by default.
  bool claims(SkinningContext context) => false;

  /// The kernels [record] dispatches, as a `ComputeStep`'s are: what
  /// placing the hook loads where it lands. Where that is, the hardware
  /// layer says: since 1.0.0-rc.1 a hook demands no placement.
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
  /// Lets a subclass be const.
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
  /// A hook keeping one CPU blend per mesh, made on first use.
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
  /// What a pacing policy is asked about frame [frameIndex].
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
  /// Lets a subclass be const.
  const PacingPolicy();

  /// True to hold [context]'s frame, false to draw it, null for the
  /// engine's rule. Never asked while the renderer warms up, on a first
  /// frame or on a resized one, which have no picture to hand back.
  bool? hold(PacingContext context) => null;
}

/// What a [QualityPolicy] is asked once a frame's time is recorded.
final class QualityContext {
  /// What a quality policy is asked once a frame's time, [micros], is
  /// recorded against [table].
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
  /// Lets a subclass be const.
  const QualityPolicy();

  /// The row [context]'s next frame is drawn at, by index (clamped to the
  /// table), or null for [QualityContext.choice].
  int? choose(QualityContext context) => null;
}

/// A renderer's hooks into what it draws (D22b): the draw-list hooks, the
/// level-of-detail and sort policies, the skinning hooks, the pacing and
/// quality policies and the shadow techniques plugins registered.
///
/// Reached by a plugin as `host.registry<RenderHooks>()`, a companion of
/// the render steps; an application uses `Renderer.hooks`.
///
/// **Every policy is a registration, and several chain.** A hook added here
/// is withdrawn with the plugin that added it, and the hooks of one kind are
/// asked in the plugins' dependency order — the application's first, then
/// each plugin's in install order, and within one owner as they were added.
/// The first to answer decides; one that answers null passes the question
/// to the next, and the last to pass leaves it to the engine's own rule. So
/// two level-of-detail policies, two sort keys or two pacing rules from two
/// plugins compose instead of the one added last silently winning, and
/// which one decides does not change with the order a game happened to
/// install them in.
final class RenderHooks extends PluginRegistry {
  /// A renderer's, with nothing registered.
  RenderHooks() : _store = _HookStore(), _scope = null;

  RenderHooks._scoped(this._store, this._scope);

  final _HookStore _store;
  final PluginScope? _scope;

  /// The draw-list hooks, in the order they are asked: the application's,
  /// then each plugin's in dependency order. A view of the renderer's own
  /// list, read for every mesh of every view, so it is not copied. Every
  /// hook must keep a mesh for it to be drawn, and the first to answer a
  /// [DrawListHook.sortKey] gives its order.
  List<DrawListHook> get drawListHooks => _store.drawList.view;

  /// The level-of-detail policies, in the order they are asked.
  List<LodPolicy> get lodPolicies =>
      List<LodPolicy>.unmodifiable(_store.lod.hooks);

  /// The level-of-detail policy every group asks: [lodPolicies] chained,
  /// the first to answer a level deciding and null passing to the next.
  /// Null when none is registered, which is the engine's rule.
  LodPolicy? get lodPolicy => _store.lod.hooks.isEmpty ? null : _store.lodChain;

  /// The skinning hooks, in the order they were added: what an application
  /// or a tool lists to say who skins what.
  List<SkinningHook> get skinningHooks =>
      List<SkinningHook>.unmodifiable(_store.skinning.hooks);

  /// The pacing policies, in the order they are asked.
  List<PacingPolicy> get pacingPolicies =>
      List<PacingPolicy>.unmodifiable(_store.pacing.hooks);

  /// What every frame of this renderer asks before it is drawn, after
  /// `FramePacing.policy`: [pacingPolicies] chained, null passing to the
  /// next. Null when none is registered.
  PacingPolicy? get pacingPolicy =>
      _store.pacing.hooks.isEmpty ? null : _store.pacingChain;

  /// The quality policies, in the order they are asked.
  List<QualityPolicy> get qualityPolicies =>
      List<QualityPolicy>.unmodifiable(_store.quality.hooks);

  /// What an `AdaptiveQuality` handed these hooks asks once a frame's time
  /// is recorded, after its own `policy`: [qualityPolicies] chained, null
  /// passing to the next. Null when none is registered.
  QualityPolicy? get qualityPolicy =>
      _store.quality.hooks.isEmpty ? null : _store.qualityChain;

  /// The shadow techniques registered, in the order they are found.
  List<ShadowTechnique> get shadowTechniques =>
      List<ShadowTechnique>.unmodifiable(_store.shadows.hooks);

  /// Adds [hook] to every view's draw list until the result is cancelled.
  Registration addDrawListHook(DrawListHook hook) =>
      _add(_store.drawList, hook);

  /// Makes [policy] one of the level-of-detail policies every group asks
  /// until the result is cancelled. Chained with the others ([lodPolicy]):
  /// the first, in dependency order, to answer a level decides.
  Registration addLodPolicy(LodPolicy policy) => _add(_store.lod, policy);

  /// Lists [hook] among the skinning hooks until the result is cancelled.
  ///
  /// **A listed hook does not skin by being listed**: it skins once
  /// `RendererSteps.placeSkinningHook` has placed it, which lists it too.
  /// This is for a tool that keeps its own account of who skins what.
  Registration addSkinningHook(SkinningHook hook) =>
      _add(_store.skinning, hook);

  /// Makes [policy] one of the pacing policies every frame of this renderer
  /// asks until the result is cancelled, chained with the others
  /// ([pacingPolicy]) after `FramePacing.policy`, the application's own.
  Registration addPacingPolicy(PacingPolicy policy) =>
      _add(_store.pacing, policy);

  /// Makes [policy] one of the quality policies an `AdaptiveQuality` handed
  /// these hooks asks until the result is cancelled, chained with the others
  /// ([qualityPolicy]) after the controller's own `policy`.
  Registration addQualityPolicy(QualityPolicy policy) =>
      _add(_store.quality, policy);

  /// Makes [technique] the one a `ShadowFilter` named
  /// [ShadowTechnique.name] is drawn with, until the result is cancelled
  /// (D22): a settings file, a level or another plugin names the filter
  /// (`ShadowFilter.custom('acme_soft.sun', base: ShadowFilter.pcf)`) and
  /// this renderer draws it with the technique, without the settings
  /// holding the object.
  ///
  /// A technique the filter itself was given wins ([techniqueFor]). Throws
  /// a [NameTakenException] for the name of a built-in filter and for one
  /// another technique has, naming who has it; through a plugin's view, a
  /// [PluginException] for a name outside the plugin's namespace,
  /// `<namespace>.<name>`.
  Registration addShadowTechnique(ShadowTechnique technique) {
    final name = technique.name;
    final problem = _scope?.manifest.nameProblem(
      name,
      what: 'the shadow technique',
    );
    if (problem != null) throw PluginException(problem);
    if (ShadowFilter.values.any((filter) => filter.name == name)) {
      throw NameTakenException(
        name,
        what: 'the shadow technique',
        owner: 'the engine',
        detail: 'it is the name of one of the engine\'s own filters',
      );
    }
    for (final entry in _store.shadows.entries) {
      if (entry.hook.name != name) continue;
      throw NameTakenException(
        name,
        what: 'the shadow technique',
        owner: entry.owner,
      );
    }
    return _add(_store.shadows, technique);
  }

  /// The technique registered under [name], or null.
  ShadowTechnique? shadowTechniqueNamed(String name) {
    for (final technique in _store.shadows.hooks) {
      if (technique.name == name) return technique;
    }
    return null;
  }

  /// What this renderer draws [filter] with: the technique the filter, or a
  /// filter it is drawn as, was given ([ShadowFilter.givenTechnique]); else
  /// the one registered under its name, or under the name of a filter it is
  /// drawn as; else its [ShadowFilter.technique], its base's built-in one.
  ShadowTechnique techniqueFor(ShadowFilter filter) {
    if (filter.givenTechnique case final given?) return given;
    for (ShadowFilter? at = filter; at != null; at = at.drawnAs) {
      if (shadowTechniqueNamed(at.name) case final registered?) {
        return registered;
      }
    }
    return filter.technique;
  }

  Registration _add<T extends Object>(_Hooks<T> into, T hook) {
    final entry = _Hooked<T>(hook, _scope, _store.sequence++);
    into.add(entry);
    final registration = Registration(() => into.remove(entry));
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
  final _Hooks<DrawListHook> drawList = _Hooks<DrawListHook>();
  final _Hooks<LodPolicy> lod = _Hooks<LodPolicy>();
  final _Hooks<SkinningHook> skinning = _Hooks<SkinningHook>();
  final _Hooks<PacingPolicy> pacing = _Hooks<PacingPolicy>();
  final _Hooks<QualityPolicy> quality = _Hooks<QualityPolicy>();
  final _Hooks<ShadowTechnique> shadows = _Hooks<ShadowTechnique>();
  final DrawListContext context = DrawListContext._();
  late final LodPolicy lodChain = _LodChain(lod);
  late final PacingPolicy pacingChain = _PacingChain(pacing);
  late final QualityPolicy qualityChain = _QualityChain(quality);
  int sequence = 0;
}

/// One hook, who added it, and when.
final class _Hooked<T extends Object> {
  _Hooked(this.hook, this.scope, this.sequence);

  final T hook;
  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  String get owner => switch (scope?.manifest.id) {
    final String id => 'plugin "$id"',
    null => 'the application',
  };

  static int compare(_Hooked<Object> a, _Hooked<Object> b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

/// The hooks of one kind, in the order they are asked: by their owner's
/// place in the install order, then as they were added. [hooks] is kept in
/// that order in place, so [view] can be read for every mesh without a
/// copy.
final class _Hooks<T extends Object> {
  final List<_Hooked<T>> entries = <_Hooked<T>>[];
  final List<T> hooks = <T>[];
  late final UnmodifiableListView<T> view = UnmodifiableListView<T>(hooks);

  void add(_Hooked<T> entry) {
    entries.add(entry);
    _order();
  }

  void remove(_Hooked<T> entry) {
    if (entries.remove(entry)) _order();
  }

  void _order() {
    entries.sort(_Hooked.compare);
    hooks
      ..clear()
      ..addAll(<T>[for (final entry in entries) entry.hook]);
  }
}

/// Every level-of-detail policy, asked in order until one answers.
///
/// Asked for every group of every view, so the list is read where it is,
/// never copied: a policy registers nothing while it is asked.
final class _LodChain extends LodPolicy {
  _LodChain(this._policies);

  final _Hooks<LodPolicy> _policies;

  @override
  int? select(LodContext context) {
    final hooks = _policies.hooks;
    for (var i = 0; i < hooks.length; i++) {
      if (hooks[i].select(context) case final int level) return level;
    }
    return null;
  }
}

/// Every pacing policy, asked in order until one answers.
final class _PacingChain extends PacingPolicy {
  _PacingChain(this._policies);

  final _Hooks<PacingPolicy> _policies;

  @override
  bool? hold(PacingContext context) {
    for (final policy in _policies.hooks) {
      if (policy.hold(context) case final bool held) return held;
    }
    return null;
  }
}

/// Every quality policy, asked in order until one answers.
final class _QualityChain extends QualityPolicy {
  _QualityChain(this._policies);

  final _Hooks<QualityPolicy> _policies;

  @override
  int? choose(QualityContext context) {
    for (final policy in _policies.hooks) {
      if (policy.choose(context) case final int row) return row;
    }
    return null;
  }
}
