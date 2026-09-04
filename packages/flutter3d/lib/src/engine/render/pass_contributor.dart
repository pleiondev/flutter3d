import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/scene.dart';
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'frame_resources.dart';
import 'lighting_model.dart';
import 'render_node.dart';
import 'render_view.dart';
import 'renderer.dart';

// Re-exported so an existing import of this file keeps seeing
// `PassContributor` and `ContributorRegistry`: they moved to their own file
// because the registry is independently testable list arithmetic with no
// claim on anything declared below, not because a user of either type should
// now import two files instead of one.
export 'contributor_registry.dart';

/// Counters and bound state shared across everything encoded into one pass.
///
/// Public because plugins write into it: a plugin that draws without counting
/// its draw calls makes the frame statistics lie, and a plugin that leaves the
/// pipeline tracker describing a pipeline it replaced makes the next node
/// skip a bind it needed.
final class FramePassState {
  LightingModel? boundPipeline;
  bool? boundSkinned;
  bool? boundInstanced;
  bool? boundLightmapped;

  /// The depth test the pass is currently set to.
  ///
  /// Tracked rather than set per mesh so that a scene where no material
  /// overrides it emits no `setDepthCompare` at all — which is not an
  /// optimisation but the property the golden sets depend on: unset means
  /// *emit nothing*, and a redundant call has flipped behaviour on two of the
  /// three backends before now (see `PassState`'s own history).
  ///
  /// Seeded with what the scene pass establishes for itself, and reseeded
  /// wherever that state is re-established.
  CompareFunction depthCompare = CompareFunction.less;
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
    boundInstanced = null;
    boundLightmapped = null;
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

  /// What [frame]'s node declared, and only that.
  ///
  /// Built here rather than at each call site, because every caller was writing
  /// the same three lines and the failure when one forgot was a weapon lit as
  /// though the room were not. Only the names the node declared are asked for:
  /// a node that never claimed the atlas gets nothing to sample rather than an
  /// error, and a node that claimed it gets whatever the frame has.
  ///
  /// [casterIndex] is the frame's, not the node's — it says which light the
  /// directional map belongs to, and a node either has that map or does not.
  static SceneShadows from(NodeFrame frame, {int casterIndex = -1}) {
    final resources = frame.resources;
    TextureHandle? declared(ResourceId id) =>
        resources.declares(id) ? resources.tryTexture(id) : null;

    // The directional map only if *this frame* drew it, and the asymmetry with
    // the two atlases is the point of asking. The matrix it is sampled through
    // is one field rewritten every frame, so pixels from an earlier frame would
    // be projected through this frame's matrix and land somewhere else
    // entirely. The atlas has no such problem because its face matrices are
    // kept in step with its tiles, which is exactly what lets it be kept and
    // this not be.
    final drawnDirectional =
        resources.declares(FrameResourceIds.shadowMap) &&
        resources.originOf(FrameResourceIds.shadowMap) == ResourceOrigin.drawn;

    return SceneShadows(
      directional: drawnDirectional
          ? resources.tryTexture(FrameResourceIds.shadowMap)
          : null,
      point: declared(FrameResourceIds.cubeShadow),
      pointStatic: declared(FrameResourceIds.cubeShadowStatic),
      casterIndex: casterIndex,
    );
  }

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

/// One full-screen pass, described rather than assembled.
///
/// The plumbing a post-processing pass needs is not interesting and there is a
/// lot of it: a triangle covering the target, an index buffer for it, a pass
/// state with depth and culling off, a pipeline built from the shared
/// full-screen vertex stage and cached so it is not rebuilt every frame, a
/// clamped sampler, a viewport. All of it was private to `Renderer`, and a node
/// is handed a [GraphicsDevice] rather than a `Renderer` — deliberately, so a
/// plugin cannot reach past what it was offered. The effect was that the one
/// shape every post effect has could not be expressed outside the file that
/// already had three of them.
///
/// A description rather than a builder, because everything here is a fact about
/// one draw and none of it is a decision made in stages.
final class FullscreenDraw {
  const FullscreenDraw({
    required this.target,
    required this.fragment,
    this.textures = const <String, TextureHandle>{},
    this.uniforms = const <String, Map<String, Float32List>>{},
    this.sampler = SamplerOptions.linearClamp,
    this.samplers = const <String, SamplerOptions>{},
    this.loadAction = LoadAction.dontCare,
  });

  /// What is drawn into. Its size is the viewport — a half-resolution effect
  /// needs to say nothing else.
  final TextureHandle target;

  /// The fragment stage. The vertex stage is the engine's own, which is what
  /// makes the triangle somebody else's problem.
  final ShaderHandle fragment;

  /// Slot name to texture, bound with [samplerFor].
  final Map<String, TextureHandle> textures;

  /// Slots that want something other than [sampler], by name.
  ///
  /// **Because one draw can read two kinds of texture.** The reflection pass
  /// samples the scene, which is colour and wants filtering, and the surface
  /// buffer, which is an octahedral normal and a depth and must not be
  /// filtered at all — and a single sampler for the draw could serve one of
  /// them or the other. It served the wrong one for as long as the pass has
  /// existed; see [sampler].
  final Map<String, SamplerOptions> samplers;

  /// How [slot] is sampled: its own entry in [samplers], or [sampler].
  SamplerOptions samplerFor(String slot) => samplers[slot] ?? sampler;

  /// Uniform block name, to member name, to the data for that member.
  ///
  /// Nested because a block is the unit a backend binds and a member is the
  /// unit it reflects an offset for. A single flat map would have to guess
  /// which of the two a key was.
  final Map<String, Map<String, Float32List>> uniforms;

  /// Clamped and linear by default: a post pass reading outside its source
  /// would otherwise wrap the far edge onto the near one.
  ///
  /// **An effect reading a buffer of *data* rather than colour wants
  /// [SamplerOptions.nearestClamp], and two of them were not asking for it.**
  /// The surface buffer holds an octahedral normal in `rg` and a window depth
  /// in `a`; the average of two octahedral normals is not the encoding of any
  /// normal, which is the sentence `ssao.frag` opens with to explain why
  /// reading that buffer switches multisampling off — and the pass that says
  /// it was itself sampling the buffer bilinearly. Per-slot overrides live in
  /// [samplers].
  final SamplerOptions sampler;

  /// Discarding by default, because nothing under a full-screen pass survives
  /// it and loading what was there costs bandwidth for pixels about to be
  /// overwritten. An effect that blends with what it lands on wants
  /// [LoadAction.load].
  final LoadAction loadAction;
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
  /// `shadows` is required and has no default, which is the point of it: what
  /// a draw samples is now something the caller states out of the frame it
  /// declared, rather than something this method reaches for. [SceneShadows.none]
  /// is the way to say "none", and saying it is cheap; not being able to say
  /// anything at all is what left the view model sampling an atlas it had never
  /// declared.
  /// Draws [scene] into an open pass.
  ///
  /// Takes the [NodeFrame] rather than the settings, the pass state and the
  /// shadows separately. Those three came off the frame at every call site, and
  /// the shadows had to be assembled there too — three lines a caller could get
  /// wrong quietly. Getting them wrong looked like a weapon lit as though the
  /// room were not, and there was no way for this method to tell.
  ///
  /// [viewProjection] stays a parameter because it is the one thing genuinely
  /// the caller's: the view model draws the same scene through a different
  /// camera, which is what makes it a separate pass. Build it with
  /// `toDepthRange`, or it is right on one backend and wrong on the other.
  void encodeScene({
    required NodeFrame frame,
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    int casterIndex = -1,
  });

  /// Draws one full-screen pass, described by [draw].
  ///
  /// The second thing only the renderer can answer, and for the same reason as
  /// the first: it owns the triangle, the shared vertex stage and the pipeline
  /// cache. A node could open its own pass — it is handed a device — and would
  /// then be rebuilding a pipeline every frame and re-deriving a covering
  /// triangle from nothing.
  ///
  /// The engine's own bloom, reflections and occlusion passes go through this.
  /// That is not tidiness: an extension point that its author's own three
  /// callers do not use is an extension point nobody has checked, and the first
  /// plugin to try it finds out what it cannot express.
  ///
  /// **Where the fragment stage comes from differs per backend**, and all three
  /// answers are worth having in one place, because the question arrives as
  /// "why does my effect work in tests and not on the device":
  ///
  ///  * the software rasteriser takes a Dart object — add it to the map handed
  ///    to `CpuShaderLibrary` alongside `builtinCpuShaders()`;
  ///  * WebGL compiles GLSL at runtime — put the source in the `ShaderSources`
  ///    handed to `WebGlDevice.create`;
  ///  * Impeller compiles ahead of time, so an application ships its own bundle
  ///    and names it in `GpuRenderBackend.create(extraBundles: [...])`. Those
  ///    are searched before the engine's, so a stage sharing a name with one of
  ///    the engine's replaces it.
  void drawFullscreen(FullscreenDraw draw);
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
