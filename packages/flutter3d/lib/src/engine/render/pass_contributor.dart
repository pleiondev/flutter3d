import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter3d_hal/flutter3d_hal.dart';
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

/// The shadow textures one scene draw samples, as the frame answered for them.
///
/// It exists to close a hole in the declaration model. The shadow samplers are
/// bound deep inside the renderer's mesh encoder, and **two** graph nodes reach
/// that code: the scene, which declares it reads the maps, and anything drawing
/// ordinary geometry somewhere unordinary through [RenderServices.encodeScene]
/// — the first-person view model is the one that ships. So there was no single
/// node whose declaration could be asked at the binding, and the encoder took
/// the atlas out of a renderer field instead. A node sampled a resource it
/// never declared, and every extension calling `encodeScene` inherited that.
///
/// Now the *caller* answers, out of the resources of the frame it was handed,
/// and what it can answer is bounded by what it declared a read of. Which
/// shadows a draw gets is therefore a decision at the call site, where it can be
/// read, rather than a field lookup two thousand lines away.
final class SceneShadows {
  const SceneShadows({
    this.directional,
    this.point,
    this.pointStatic,
    this.casterIndex = -1,
  });

  /// Nothing to sample: every surface is lit as if unoccluded.
  static const SceneShadows none = SceneShadows();

  /// The directional light's map, or null when this frame drew none.
  ///
  /// Null is not "shadows are off" — it is the honest answer for a frame whose
  /// shadow pass gave up, and binding a texture regardless would offer the last
  /// frame that had one.
  final TextureHandle? directional;

  /// Which light in the packed buffer [directional] was drawn for; -1 for none.
  final int casterIndex;

  /// The point-light atlases: what moves, and what was baked once.
  ///
  /// Unlike [directional] these are maintained across frames — see
  /// `FrameGraphNode.keeps` — so a texture here may hold pixels an earlier
  /// frame drew, deliberately, and is exactly as valid to sample for it.
  final TextureHandle? point;
  final TextureHandle? pointStatic;
}

/// What the renderer lends a contributor or a node.
///
/// One method, and that is the whole of it now. It used to carry two more —
/// the shader bundle and a uniform-block writer — and both were really
/// questions for the *backend*: a bundle is where a `ShaderHandle` comes from,
/// and how a uniform block reaches the GPU is a lifetime rule of one API. They
/// live on [GraphicsDevice] and `CommandEncoder` respectively, so what is left
/// here is the one thing only the renderer can answer.
///
/// An interface rather than the [Renderer] class so a plugin cannot reach past
/// what it was offered, and so a test can drive one without a GPU context.
abstract interface class RenderServices {
  /// Draws every visible mesh of [scene], as the renderer draws the world.
  ///
  /// For a plugin whose content is ordinary geometry in an unordinary place —
  /// a first person weapon, a portal's far side — so it inherits materials,
  /// skinning and lighting instead of growing a second copy of them.
  ///
  /// [shadows] is required and has no default, which is the point of it: what
  /// a draw samples is now something the caller states out of the frame it
  /// declared, rather than something this method reaches for. [SceneShadows.none]
  /// is the way to say "none", and saying it is cheap; not being able to say
  /// anything at all is what left the view model sampling an atlas it had never
  /// declared.
  void encodeScene({
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    required RenderSettings settings,
    required FramePassState state,
    required SceneShadows shadows,
  });
}

/// Everything something drawing **into someone else's pass** is given.
///
/// It carries a pass, and that is the whole distinction: a contributor draws
/// into a pass it did not make, so it must be handed one. A node owns its pass
/// and therefore creates one, which is why it takes [NodeFrame] instead. The
/// two were one type until the scene pass was extracted and the difference
/// stopped being expressible.
final class ContributorFrame {
  ContributorFrame({
    required this.encoder,
    required this.device,
    required this.services,
    required this.state,
    required this.settings,
    required this.width,
    required this.height,
    this.view,
    this.viewProjection,
  });

  /// The pass being built. Drawing into it is the point.
  ///
  /// A [PassEncoder] and not a `CommandEncoder`, so it cannot be submitted:
  /// this pass belongs to whoever opened it, and a contributor that ended it
  /// would take every draw after its own with it. That distinction used to be a
  /// comment.
  final PassEncoder encoder;

  /// The backend, for a contributor that builds its own pipeline out of the
  /// bundle's stages. Passed as a value; there is no global to reach for.
  final GraphicsDevice device;

  final RenderServices services;
  final FramePassState state;
  final RenderSettings settings;

  final int width;
  final int height;

  /// The view being drawn.
  final RenderView? view;
  final vm.Matrix4? viewProjection;
}

/// Something that draws inside a pass it does not own.
///
/// The seam exists because `render()` was growing a parameter per feature —
/// first the weapon view model, then the particles — and positional audio,
/// decals and a fog volume would each have added another. A parameter list is
/// a registry with no ordering and no way for an application to add to it.
///
/// Modelled on Flame's components: the engine owns the loop and the
/// contributor owns what it draws. What it does *not* have any more is a
/// stage, because the two stages turned out to be two different things. A
/// contributor draws into the scene's pass, before it is submitted. Anything
/// that wanted its own pass was never a contributor at all — it is a
/// [RenderNode], and the weapon view model has moved.
abstract base class PassContributor {
  const PassContributor();

  /// Lower encodes first. Ties keep registration order.
  int get order => 0;

  /// Whether there is anything to draw this frame. Checked before [encode] so
  /// a contributor with nothing to say costs no pass setup.
  bool get isActive => true;

  void encode(ContributorFrame frame);
}

/// The contributors a renderer draws, and the order it draws them in.
///
/// Its own class rather than three fields on [Renderer] because ordering is
/// the whole substance of a registry and the only part worth testing — and
/// testing it through the renderer would need a GPU context to ask a question
/// that is pure list arithmetic.
final class ContributorRegistry {
  final List<PassContributor> _plugins = <PassContributor>[];
  List<PassContributor> _ordered = const <PassContributor>[];

  /// Registration order, which is not drawing order — see [active].
  List<PassContributor> get all =>
      List<PassContributor>.unmodifiable(_plugins);

  int get length => _plugins.length;

  T add<T extends PassContributor>(T plugin) {
    _plugins.add(plugin);
    _reorder();
    return plugin;
  }

  bool remove(PassContributor plugin) {
    final removed = _plugins.remove(plugin);
    if (removed) _reorder();
    return removed;
  }

  void clear() {
    _plugins.clear();
    _ordered = const <PassContributor>[];
  }

  /// Everything active, in drawing order.
  ///
  /// [PassContributor.isActive] is asked here rather than by the caller so a
  /// contributor with nothing to say this frame costs no pass setup.
  Iterable<PassContributor> get active sync* {
    for (final plugin in _ordered) {
      if (plugin.isActive) yield plugin;
    }
  }

  void _reorder() {
    // Sorted by order alone, and stably, so two plugins claiming the same
    // number keep the order they were registered in — the only tie-break an
    // application can actually control. Recomputed on change rather than per
    // frame: the set moves once at startup and the frame runs sixty times a
    // second.
    _ordered = List<PassContributor>.of(_plugins)
      ..sort((PassContributor a, PassContributor b) =>
          a.order.compareTo(b.order));
  }
}
