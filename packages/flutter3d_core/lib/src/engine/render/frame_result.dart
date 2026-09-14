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

import 'render_settings.dart' show RenderSettings;

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
    this.wireframeDeclined = false,
    this.exposure = RenderSettings.defaultExposure,
    this.passes = const <({String name, bool active, int micros})>[],
  });

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
  final List<({String name, bool active, int micros})> passes;
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
