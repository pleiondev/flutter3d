/// `S9`'s own row: what changes about the picture while screen 19's preview
/// is open — tonemap, shadows and the sky — and nothing else.
///
/// **Lighting is not here on purpose.** `LightingSync` already owns the
/// scene's own light nodes and the exposure/shadow-request pair it folds
/// into a frame's [RenderSettings] (`lighting_sync.dart`'s own `apply`); this
/// file only overrides the three fields the preview itself asks for on top
/// of whatever `LightingSync` already produced, through [applyTo]. A caller
/// that skipped `LightingSync` and drew with [render] alone would lose every
/// light's own exposure and shadow request — this is a delta, not a
/// replacement.
///
/// **Nothing is saved and nothing is restored.** [render] and [sky] are
/// values `GamePreviewScreen` hands to its own `ModelerViewport` on every
/// frame it draws — the document's own `ModelerStage` and its scene are
/// never written to, so there is nothing to put back once the route pops.
/// "restored to whatever they were on exit," the row's own wording, is true
/// here by construction rather than by a save/restore pair: the main
/// viewport keeps computing its own [RenderSettings] the way it always did,
/// this screen's own settings live only inside the frames *it* draws, and
/// closing the route is the whole of "exit."
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// `#RRGGBB`, sRGB, in 0..1 — the same tiny reader `weight_gradient.dart`
/// keeps its own private copy of, for the same reason that file's own
/// comment gives: a design hand-over states its colours in sRGB hex and a
/// [SkySettings] field wants them linear.
Vector3 _srgbFromHex(int hex) => Vector3(
  ((hex >> 16) & 0xFF) / 255.0,
  ((hex >> 8) & 0xFF) / 255.0,
  (hex & 0xFF) / 255.0,
);

/// IEC 61966-2-1 — `weight_gradient.dart`'s own `_srgbChannelToLinear`,
/// restated rather than shared: that file's copy is private to it, and
/// pulling one three-line function out to share it was not worth a change to
/// a file outside this pass.
double _srgbChannelToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

Vector3 _srgbToLinear(int hex) {
  final srgb = _srgbFromHex(hex);
  return Vector3(
    _srgbChannelToLinear(srgb.x),
    _srgbChannelToLinear(srgb.y),
    _srgbChannelToLinear(srgb.z),
  );
}

/// Screen 19's own sky, fixed regardless of whatever `SceneEnvironmentPreset`
/// the scene mode has chosen — the hand-over's own zenith/nadir for "as it
/// would look in the game," independent of what the project is being
/// authored under.
SkySettings _previewSky() {
  final zenith = _srgbToLinear(0x243440);
  final nadir = _srgbToLinear(0x0F181D);
  return SkySettings(
    enabled: true,
    zenith: zenith,
    // No named horizon in the hand-over — a straight blend between the two
    // named stops is what `SkySettings.horizon`'s own null default already
    // gives (see its doc comment for `resolved`), so this leaves it null
    // rather than guessing a third colour nobody specified.
    nadir: nadir,
  );
}

/// Whether [target] gets a shadow pass in the preview at all.
///
/// **A profile question, not a `SceneLighting.shadows` one.** The scene
/// mode's own shadow toggle (`mat-23`/`mat-24`) is an authoring choice —
/// "let me see shadows while I place lights" — and stays exactly what
/// [LightingSync.apply] already reads it as. This is a different question:
/// "would the *device* this profile describes draw a shadow pass at all,"
/// which is `false` for [ProfileTarget.mobile] and `true` otherwise —
/// the same distinction [ProjectProfile.mobile]'s own smaller texture and
/// triangle budgets already draw between a handset and everything else.
bool _shadowsForTarget(ProfileTarget target) => target != ProfileTarget.mobile;

/// `S9`'s own render tweaks: tonemap, shadows and the sky, computed once
/// from a project's own [ProjectProfile] — "тонмап, тени по профилю" in the
/// plan's own words.
final class GamePreviewSettings {
  const GamePreviewSettings({required this.render, required this.sky});

  /// Built from [profile] — the only input, since nothing else about the
  /// preview is per-project.
  factory GamePreviewSettings.forProfile(ProjectProfile profile) {
    final bool shadows = _shadowsForTarget(profile.target);
    return GamePreviewSettings(
      render: const RenderSettings().copyWith(
        tonemap: true,
        shadows: const ShadowSettings().copyWith(enabled: shadows),
      ),
      sky: _previewSky(),
    );
  }

  /// This preview's own tonemap and shadow request — [sky] is kept apart
  /// since [applyTo] writes it onto a different field of [RenderSettings]
  /// than the one it is stored under here.
  final RenderSettings render;

  /// Fixed regardless of the project's own scene environment — see
  /// [_previewSky].
  final SkySettings sky;

  /// [base] — whatever `RenderSettings` the caller was already drawing
  /// with, its own exposure and debug flags kept — with this preview's own
  /// tonemap, shadow pass and sky folded in on top.
  RenderSettings applyTo(RenderSettings base) => base.copyWith(
    tonemap: render.tonemap,
    shadows: base.shadows.copyWith(enabled: render.shadows.enabled),
    sky: sky,
  );
}
