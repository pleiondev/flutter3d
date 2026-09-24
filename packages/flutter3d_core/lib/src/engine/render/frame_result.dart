/// What a rendered frame *was*, as opposed to how it was asked for.
///
/// **Not a setting, and it lived in `render_settings.dart` anyway.** Everything
/// else in that file is a knob turned before a frame; this is the texture and
/// the counters that come back after one. It referenced nothing there and
/// nothing there referenced it, which is what made the misfiling invisible.
/// The one thing it reads from there now is the default exposure, so that the
/// number lives in one place rather than in a literal here that would drift
/// from the setting's the day somebody changed it.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'frame_graph.dart' show PassSkip, SkippedPass;
import 'render_settings.dart' show RenderSettings;

/// What one node of the frame graph cost — `gfx-01n`'s own row.
///
/// **A frame total says a frame got slower and not where.** Four passes draw
/// in an ordinary frame — the shadows, the scene, the sky, the composite —
/// and "the frame is up twelve draw calls" is the same sentence whether the
/// shadow map gained a cascade or somebody added an overlay. Per pass, it is
/// one sentence and it names the pass.
///
/// A record rather than a class because it is read and never built by
/// anything outside the renderer, and a named one because the shape is
/// written out in four files and was drifting.
typedef FramePass = ({
  /// The graph node's own name.
  String name,

  /// What `RenderNode.isActive` said at the node this timing came from. See
  /// [FrameResult.passes] for why absence, not `false`, is how a pass that
  /// did not run is reported.
  bool active,

  /// Wall-clock time inside this node's own `execute`.
  int micros,

  /// What the GPU spent in the passes this node opened, or null where the
  /// device does not measure it — `H2`. See
  /// `GraphicsDevice.supportsGpuTimestamps`.
  int? gpuMicros,

  /// Draws this node encoded. Zero for a node that only moves textures
  /// about — the composite's own full-screen triangle is a draw and counts.
  int drawCalls,
  int triangles,
  int pipelineSwitches,
});

/// What smoothed the edges of a frame, as opposed to what was asked for —
/// `gfx-20n`.
///
/// **Two mechanisms that a caller thinks of as one setting, and one of them
/// turns itself off.** Multisampling belongs to the scene pass's attachments;
/// the post-process pass is a node in the graph. They are asked for
/// separately and they interact: attachments in one target must agree on
/// sample count, so the moment anything consumes the surface buffer the scene
/// pass stops multisampling — switch occlusion on and the edges get worse,
/// with nothing anywhere saying why.
///
/// That is the readback this type exists for. [msaaDeclined] names the reason
/// rather than leaving a caller to compare a sample count against a setting
/// and guess.
final class EffectiveAntiAliasing {
  const EffectiveAntiAliasing({
    required this.msaaSamples,
    required this.fxaa,
    required this.msaaDeclined,
    this.temporal = false,
  });

  /// Samples the scene pass actually drew with. One means none.
  final int msaaSamples;

  /// Whether the scene was jittered and resolved across frames — `R1`. On,
  /// this is the reason [msaaSamples] is one.
  final bool temporal;

  /// Whether the post-process pass ran.
  ///
  /// Derivable from `FrameResult.passes`, and stated here anyway: a caller
  /// asking "what smoothed my edges" should get one answer rather than a
  /// number and a list to search.
  final bool fxaa;

  /// Why multisampling was not used, or null when it was — or when nobody
  /// asked for it.
  ///
  /// A sentence rather than a code, because there are exactly two reasons and
  /// both are things a caller can act on: the device has no multisampled
  /// offscreen target, or something in this frame reads the surface buffer.
  final String? msaaDeclined;

  /// Whether the frame got no anti-aliasing at all.
  bool get none => msaaSamples <= 1 && !fxaa && !temporal;

  @override
  String toString() =>
      'EffectiveAntiAliasing(msaa $msaaSamples, fxaa $fxaa'
      '${temporal ? ", temporal" : ""}'
      '${msaaDeclined == null ? "" : ", msaa declined: $msaaDeclined"})';
}

/// One rendered frame.
final class FrameResult {
  const FrameResult({
    required this.frame,
    required this.cpuMicros,
    required this.submitMicros,
    required this.drawCalls,
    required this.triangles,
    required this.instances,
    required this.culled,
    required this.pipelineSwitches,
    required this.debugLines,
    required this.lights,
    required this.lightsDropped,
    required this.pipelines,
    required this.shadowCasters,
    required this.skinnedDraws,
    this.shadowsDenied = 0,
    this.batchedDraws = 0,
    this.wireframeDeclined = false,
    this.exposure = RenderSettings.defaultExposure,
    this.passes = const <FramePass>[],
    this.skipped = const <SkippedPass>[],
    this.antiAliasing = const EffectiveAntiAliasing(
      msaaSamples: 1,
      fxaa: false,
      msaaDeclined: null,
    ),
  });

  /// How many individual draws the automatic batcher replaced — `gfx-67n`.
  ///
  /// Zero unless `RenderSettings.batchIdenticalDraws` asked for it. A hundred
  /// identical meshes drawn in one call look exactly like a hundred drawn in a
  /// hundred, so the saving needs a number: this is `100` for that frame, and
  /// `drawCalls` is the figure it came off.
  final int batchedDraws;

  /// What actually smoothed the edges — `gfx-20n`.
  ///
  /// Beside [skipped] rather than folded into it, because multisampling is
  /// not a pass: it is a property of the scene pass's attachments, and a
  /// frame that quietly stopped multisampling has no node to report.
  final EffectiveAntiAliasing antiAliasing;

  /// Every registered pass that did not run this frame, and why — `gfx-39n`.
  ///
  /// [passes] says what ran and what each cost. This says what did not, which
  /// is the harder question and the one that actually gets asked: a frame
  /// missing its occlusion looks exactly like a frame whose occlusion did
  /// nothing, and [culled] only counts them.
  ///
  /// It joins [shadowsDenied], [wireframeDeclined] and [exposure] rather than
  /// starting a new convention — this class already answers "you asked for
  /// something and here is what you actually got" three times, and those three
  /// each needed their own field because there was no general form. This is
  /// the general form.
  final List<SkippedPass> skipped;

  /// Why [name] did not run this frame, or null if it ran or was never
  /// registered.
  ///
  /// The two nulls are deliberately one: a caller holding a name from
  /// [passes] is asking about a pass that ran, and a caller holding a name
  /// from nowhere has a question this frame cannot answer. Telling those
  /// apart is `FrameGraphError`'s job, at compile, where a name nothing
  /// carries is refused outright.
  PassSkip? skipReasonOf(String name) {
    for (final entry in skipped) {
      if (entry.name == name) return entry.reason;
    }
    return null;
  }

  /// The exposure the composite used: the setting's, or — with auto exposure
  /// on — what the meter had adapted to by this frame.
  ///
  /// Reported because it is the one number in the frame that the settings do
  /// not decide, and a HUD, a test or a person asking "why is this frame so
  /// bright" has nowhere else to read it.
  final double exposure;

  /// The texture the frame was drawn into.
  ///
  /// A handle and not a `ui.Image`, which is the whole of the change: an image
  /// is what *one* backend can produce for free, and asking every backend for
  /// one costs a GPU->CPU->GPU round trip on any that cannot. Show it with
  /// `presentFrame` from `flutter3d_app`, read it with
  /// `GraphicsDevice.readPixels`, and let the backend decide which of those
  /// is cheap.
  ///
  /// It is the renderer's own target and is reused every frame, so it is valid
  /// until the next [Renderer.render] and not beyond.
  final TextureHandle frame;

  /// Wall-clock time spent inside [Renderer.render], submit included.
  ///
  /// This is what the renderer costs the UI thread. It is not the GPU cost: the
  /// frame is still executing when this number is taken.
  final int cpuMicros;

  /// Wall-clock time inside `CommandBuffer.submit`. Not a GPU timestamp —
  /// no backend here exposes one — but enough to notice a regression.
  final int submitMicros;

  final int drawCalls;

  /// Triangles actually drawn this frame — `view-17`'s own row. A batch's
  /// mesh counts once per instance; a plain [MeshNode] once. Not derived
  /// from [drawCalls]: a single instanced draw call can carry any number of
  /// these, which is the whole reason instancing is cheaper than [drawCalls]
  /// alone would suggest.
  final int triangles;

  /// Instances drawn through an [InstancedMeshNode], summed across every
  /// batch in the frame — `view-17`'s own row, alongside [triangles]. Zero
  /// when nothing in the frame batches. An ordinary [MeshNode] is one draw,
  /// not one instance of itself, so it does not add to this count — the same
  /// reason [pipelineSwitches] counts a pipeline change and not every draw
  /// that kept the same one.
  final int instances;

  /// Meshes rejected by frustum culling, so the win is visible.
  final int culled;

  /// How often the pipeline changed. With sorting working this should be close
  /// to the number of distinct lighting models in view.
  final int pipelineSwitches;

  /// Line segments submitted by the debug overlay, zero when it is off.
  final int debugLines;

  /// Lights actually shaded this frame.
  final int lights;

  /// Lights the scene holds beyond the eight one packing can carry.
  ///
  /// It used to mean lights going unlit, and it no longer does: above zero, the
  /// renderer stops handing every draw the same eight and picks eight per
  /// object instead, so the ninth lamp lights what stands beside it. What the
  /// number reports now is that the frame is in that regime — worth watching,
  /// because the selection is a per-draw cost that a scene inside eight lights
  /// never pays, and worth knowing before reading a profile.
  final int lightsDropped;

  /// Whether `RenderSettings.wireframe` was asked for and could not be given.
  ///
  /// **The backends refuse a polygon mode they have no line primitives for,
  /// loudly and by design — and the engine was swallowing the refusal.** A
  /// caller that set `wireframe: true` on the WebGL or software backend got a
  /// solid model, no exception and no word anywhere, which is the one place
  /// this repository's own rule about backends refusing rather than
  /// substituting was undone a layer up. Reported here for the same reason
  /// [lightsDropped] is: a setting that did nothing should say so.
  final bool wireframeDeclined;

  /// Pipelines the renderer has built so far.
  ///
  /// Reported per frame because it is the number that has to stay put: light
  /// count, light type and material values are all uniforms, and any of them
  /// pushing this up would mean a permutation had crept in where a uniform
  /// belonged. With no runtime shader compilation, that is not a slow path —
  /// it is a wrong one.
  final int pipelines;

  /// Meshes drawn into the shadow map, zero when the pass did not run.
  final int shadowCasters;

  /// Point and spot lights that asked for a cube shadow and got no atlas row.
  ///
  /// The atlas has `kShadowedLights` rows, and a light past them shades
  /// unshadowed — which one, decided by relevance and hysteresis rather than
  /// by scene order, so the count can change as the player walks. Reported for the same reason [lightsDropped] is: a
  /// `castsShadow` that did nothing should say so, rather than leave the
  /// author reading a missing shadow as a bug in the shadows.
  final int shadowsDenied;

  /// Draws that went through the skinned vertex stage.
  final int skinnedDraws;

  /// One entry per node `CompiledFrameGraph.order` actually kept this frame,
  /// in that same order — `pro-eng-05`'s own row.
  ///
  /// **Absence is the signal, not `active: false`.** `_compileFrameGraph`
  /// drops every node whose own `RenderNode.isActive` answers false before
  /// `order` is even built — bloom, with bloom off, is never asked and never
  /// appears here at all, rather than appearing with `active: false`. So
  /// `active` reads `isActive` at the same node this frame's own timing
  /// came from, and is therefore always true for anything in this list
  /// today; it is reported as its own field rather than assumed, because the
  /// two questions — "did the graph keep this node" and "what did the node
  /// itself say about its own readiness" — happen to agree now and are not
  /// the same question.
  final List<FramePass> passes;
}

/// What [Renderer.renderPost] handed back.
///
/// `pro-eng-03`'s own row: a standalone bloom-and-composite pass over a
/// colour buffer the caller supplies rather than one a scene node in the
/// same graph produced. Deliberately its own type rather than a narrower
/// [FrameResult] — a scene's own draw counts, light counts and shadow
/// counts do not exist for a call with no scene at all, and filling them
/// with zeros would read as "nothing was shaded" rather than "there was
/// never anything to shade".
final class PostFrameResult {
  const PostFrameResult({
    required this.frame,
    required this.cpuMicros,
    this.hdr,
  });

  /// The tone-mapped, sRGB-encoded output — the same picture the composite
  /// node inside [Renderer.render] would have written, for the same
  /// [hdr]/settings pair.
  final TextureHandle frame;

  /// The bloomed HDR buffer [renderPost] composited from, kept only when
  /// `keepHdr: true` was asked for. Null otherwise: a pooled texture
  /// nothing outside this call has a reason to hold a reference to.
  final TextureHandle? hdr;

  /// Wall-clock time spent inside [Renderer.renderPost].
  final int cpuMicros;
}
