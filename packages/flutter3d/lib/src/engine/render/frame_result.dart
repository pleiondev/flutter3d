/// What a rendered frame *was*, as opposed to how it was asked for.
///
/// **Not a setting, and it lived in `render_settings.dart` anyway.** Everything
/// else in that file is a knob turned before a frame; this is the texture and
/// the counters that come back after one. It referenced nothing there and
/// nothing there referenced it, which is what made the misfiling invisible.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// One rendered frame.
final class FrameResult {
  const FrameResult({
    required this.frame,
    required this.cpuMicros,
    required this.submitMicros,
    required this.drawCalls,
    required this.culled,
    required this.pipelineSwitches,
    required this.debugLines,
    required this.lights,
    required this.lightsDropped,
    required this.pipelines,
    required this.shadowCasters,
    required this.skinnedDraws,
    this.wireframeDeclined = false,
  });

  /// The texture the frame was drawn into.
  ///
  /// A handle and not a `ui.Image`, which is the whole of the change: an image
  /// is what *one* backend can produce for free, and asking every backend for
  /// one costs a GPU->CPU->GPU round trip on any that cannot. Show it with
  /// `GraphicsDevice.present`, read it with `GraphicsDevice.readPixels`, and
  /// let the backend decide which of those is cheap.
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

  /// Meshes rejected by frustum culling, so the win is visible.
  final int culled;

  /// How often the pipeline changed. With sorting working this should be close
  /// to the number of distinct lighting models in view.
  final int pipelineSwitches;

  /// Line segments submitted by the debug overlay, zero when it is off.
  final int debugLines;

  /// Lights actually shaded this frame.
  final int lights;

  /// Lights that did not fit in the uniform array, so a scene that quietly
  /// stopped lighting its ninth lamp says so instead of looking wrong.
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

  /// Draws that went through the skinned vertex stage.
  final int skinnedDraws;
}
