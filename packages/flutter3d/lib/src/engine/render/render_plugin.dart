import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/scene.dart';
import 'lighting_model.dart';
import 'renderer.dart';
import 'render_view.dart';

/// Counters and bound state shared across everything encoded into one pass.
///
/// Public because plugins write into it: a plugin that draws without counting
/// its draw calls makes the frame statistics lie, and a plugin that leaves the
/// pipeline tracker describing a pipeline it replaced makes the next node
/// skip a bind it needed.
final class FramePassState {
  LightingModel? boundPipeline;
  bool? boundSkinned;
  int drawCalls = 0;
  int pipelineSwitches = 0;
  int skinnedDraws = 0;

  /// Call after encoding anything that binds its own pipeline.
  ///
  /// The tracker describes the mesh pipelines only, so a pass that replaced
  /// whatever it thought was bound has to say so or the next mesh will trust
  /// a stale answer.
  void invalidatePipeline() {
    boundPipeline = null;
    boundSkinned = null;
  }
}

/// Where in the frame a plugin draws.
///
/// The two are not a preference. Anything written into the HDR target is scene
/// light: it is tone mapped and it bleeds into the bloom, which is right for a
/// spark and wrong for a gizmo. And anything sharing the world's depth buffer
/// is clipped by the world, which is right for a spark and fatal for a weapon
/// held at arm's length.
enum RenderStage {
  /// Inside the scene's HDR pass, alongside the world, once per view.
  inScene,

  /// Its own pass over the finished scene, before the post chain.
  overlayScene,
}

/// What the renderer lends a plugin.
///
/// Narrow on purpose. A plugin needs the shaders it was compiled against, a
/// way to fill a uniform block without reimplementing the reflection dance,
/// and — for anything drawing meshes rather than its own vertex format — the
/// renderer's own node encoder. Everything else it brings itself.
///
/// An interface rather than the [Renderer] class so a plugin cannot reach past
/// what it was offered, and so a test can drive one without a GPU context.
abstract interface class PluginServices {
  /// The compiled shader bundle, for a plugin building its own pipeline.
  gpu.ShaderLibrary get library;

  /// Fills [blockName] from [members] and binds it.
  ///
  /// False when the block does not exist or reflects as empty, which is the
  /// phantom-binding trap: the compiler drops a block nothing reads, and
  /// binding it anyway takes the process down with no Dart stack.
  bool bindUniformBlock(
    gpu.RenderPass pass,
    gpu.HostBuffer host,
    gpu.Shader shader,
    String blockName,
    Map<String, Float32List> members,
  );

  /// Draws every visible mesh of [scene], as the renderer draws the world.
  ///
  /// For a plugin whose content is ordinary geometry in an unordinary place —
  /// a first person weapon, a portal's far side — so it inherits materials,
  /// skinning and lighting instead of growing a second copy of them.
  void encodeScene({
    required gpu.RenderPass pass,
    required gpu.HostBuffer host,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    required RenderSettings settings,
    required FramePassState state,
  });
}

/// Everything a plugin is given to encode with.
///
/// A record of the arguments the renderer's own encoders already take, rather
/// than an invented interface: the point of the seam is that particles and the
/// weapon view model move onto it unchanged, and an argument list that does
/// not fit them is the wrong argument list.
final class PluginFrame {
  PluginFrame({
    required this.pass,
    required this.host,
    required this.services,
    required this.state,
    required this.settings,
    required this.width,
    required this.height,
    this.view,
    this.viewProjection,
    this.sceneColor,
  });

  final gpu.RenderPass pass;
  final gpu.HostBuffer host;
  final PluginServices services;
  final FramePassState state;
  final RenderSettings settings;

  final int width;
  final int height;

  /// The view being drawn. Null for [RenderStage.overlayScene], which is
  /// encoded once for the frame rather than once per view.
  final RenderView? view;
  final vm.Matrix4? viewProjection;

  /// The HDR target the scene was drawn into, for a stage that owns its pass.
  final gpu.Texture? sceneColor;
}

/// Something that draws into a frame without the renderer knowing what it is.
///
/// The seam exists because `render()` was growing a parameter per feature —
/// first the weapon view model, then the particles — and positional audio,
/// decals and a fog volume would each have added another. A parameter list is
/// a registry with no ordering and no way for an application to add to it.
///
/// Modelled on Flame's components: the engine owns the loop and the plugin
/// owns what it draws. Unlike Flame, the stage is declared rather than implied
/// by tree position, because in 3D *when* something is drawn decides whether
/// it is lit, clipped and bloomed — and that is too important to infer.
abstract base class RenderPlugin {
  const RenderPlugin();

  RenderStage get stage;

  /// Lower encodes first, within a stage. Ties keep registration order.
  int get order => 0;

  /// Whether there is anything to draw this frame. Checked before [encode] so
  /// a plugin with nothing to say costs no pass setup.
  bool get isActive => true;

  void encode(PluginFrame frame);
}

/// The set of plugins a renderer draws, and the order it draws them in.
///
/// Its own class rather than three fields on [Renderer] because ordering is
/// the whole substance of a registry and the only part worth testing — and
/// testing it through the renderer would need a GPU context to ask a question
/// that is pure list arithmetic.
final class PluginRegistry {
  final List<RenderPlugin> _plugins = <RenderPlugin>[];
  List<RenderPlugin> _ordered = const <RenderPlugin>[];

  /// Registration order, which is not drawing order — see [forStage].
  List<RenderPlugin> get all => List<RenderPlugin>.unmodifiable(_plugins);

  int get length => _plugins.length;

  T add<T extends RenderPlugin>(T plugin) {
    _plugins.add(plugin);
    _reorder();
    return plugin;
  }

  bool remove(RenderPlugin plugin) {
    final removed = _plugins.remove(plugin);
    if (removed) _reorder();
    return removed;
  }

  void clear() {
    _plugins.clear();
    _ordered = const <RenderPlugin>[];
  }

  /// Everything active in [stage], in drawing order.
  ///
  /// [RenderPlugin.isActive] is asked here rather than by the caller so a
  /// plugin with nothing to say this frame costs no pass setup.
  Iterable<RenderPlugin> forStage(RenderStage stage) sync* {
    for (final plugin in _ordered) {
      if (plugin.stage == stage && plugin.isActive) yield plugin;
    }
  }

  void _reorder() {
    // Sorted by order alone, and stably, so two plugins claiming the same
    // number keep the order they were registered in — the only tie-break an
    // application can actually control. Recomputed on change rather than per
    // frame: the set moves once at startup and the frame runs sixty times a
    // second.
    _ordered = List<RenderPlugin>.of(_plugins)
      ..sort((RenderPlugin a, RenderPlugin b) => a.order.compareTo(b.order));
  }
}
