/// Scene mode v1's own pure logic — `mat-24`'s row: which of a project's
/// lights are pickable markers, what the status line says, and when it
/// turns orange.
///
/// **Nothing here touches a scene graph or a renderer.** `lightsDropped` and
/// `shadowsDenied` are the renderer's own answer to "I asked for more than I
/// got" — `FrameResult`'s own fields (`packages/flutter3d/lib/src/engine/
/// render/frame_result.dart`), produced by `Renderer.render` after it has
/// actually drawn a frame — and this file's job is only to turn a project's
/// lighting and that frame's own counts into what the status line and the
/// warning show, the same split every panel in this app keeps: a widget
/// draws what a pure function already decided.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// How many lights `Renderer`'s own shadow pass ever serves in one frame —
/// `Renderer.kShadowedLights` in `packages/flutter3d/lib/src/engine/render/
/// renderer.dart`, restated here rather than imported because this package
/// depends on `flutter3d_model_core`, not the engine, and a status line does
/// not need a `GraphicsDevice` nearby to know what its own denominator is.
/// The cost of restating it is that a change to the engine's own cap has to
/// be followed by hand here — cheap, because nothing in this file computes a
/// shadow count from scratch; it only ever names the number a caller already
/// has, alongside the frame the renderer drew with it.
const int kSceneShadowCap = 6;

/// What the status line says, and whether it should read as a warning.
final class SceneStatus {
  const SceneStatus({
    required this.lightCount,
    required this.shadowedCount,
    required this.shadowCap,
    required this.warning,
  });

  /// How many lights the project's own [SceneLighting.lights] carries.
  final int lightCount;

  /// How many of them are shadowing this frame, capped at [shadowCap] —
  /// never more, because the renderer itself never draws more than that in
  /// one frame.
  final int shadowedCount;

  /// The denominator the status line names — [kSceneShadowCap] unless a
  /// caller has a reason to say otherwise.
  final int shadowCap;

  /// Whether the status should read orange: a light or a shadow request the
  /// renderer could not honour drawing this frame.
  final bool warning;

  /// `Источников N · теневых M из 6` — `mat-24`'s own row, verbatim.
  String get text =>
      'Источников $lightCount · теневых $shadowedCount из $shadowCap';

  @override
  String toString() => 'SceneStatus($text, warning: $warning)';
}

/// [lights]' own status, as of a frame that reported [lightsDropped] and
/// [shadowsDenied] — both read straight off that frame's own `FrameResult`,
/// so this never re-derives from a light count what the renderer already
/// measured while drawing the thing.
///
/// **The ninth light lights the warning, not a count this file guesses at.**
/// `LightBuffer.maxLights` is 8; a ninth light in one draw is the light
/// `Renderer.render` could not fit, and it is *that* render's own
/// `lightsDropped` this function is handed — see `mat-24`'s own acceptance,
/// "девятый источник → оранжевый статус". Reading `lights.length > 8` here
/// instead would agree with that one case and disagree with the one that
/// actually matters: a ninth light that never overlaps anything the first
/// eight already light stays undropped, and a project ought to be able to
/// carry as many of those as it wants without ever going orange for it.
SceneStatus computeSceneStatus({
  required List<ProjectLight> lights,
  int shadowCap = kSceneShadowCap,
  int lightsDropped = 0,
  int shadowsDenied = 0,
}) {
  final int requested = lights
      .where((ProjectLight light) => light.castsShadow)
      .length;
  final int shadowed = requested > shadowCap ? shadowCap : requested;
  return SceneStatus(
    lightCount: lights.length,
    shadowedCount: shadowed,
    shadowCap: shadowCap,
    warning: lightsDropped > 0 || shadowsDenied > 0,
  );
}

/// Which of [lighting]'s own lights are pickable markers in the viewport —
/// every one of them, named by its own index into [SceneLighting.lights].
///
/// A function of its own, rather than an assumption baked into whatever
/// picks a marker, so "every light is pickable" is a fact this file states
/// and a later row narrowing it (a light locked by its own layer, say) has
/// one place to change rather than a picker's own hit-testing to re-read.
List<int> pickableLightIndices(SceneLighting lighting) =>
    List<int>.generate(lighting.lights.length, (int i) => i);
