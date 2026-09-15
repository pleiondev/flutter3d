/// Keeps a `Scene`'s own light nodes and render settings in step with a
/// project's [SceneLighting] — `mat-23`'s own row.
///
/// **Lives here, not in `apps/flutter3d_modeler`, since `tut-07`'s own
/// fix.** `LightingSync` used to sit in the application because
/// [SceneLighting]'s own doc comment once said this package "depends on
/// neither the engine nor Flutter" — no longer true: `render_project.dart`,
/// in this same package, already depends on `flutter3d_core` for `Scene`,
/// `MeshNode` and `Renderer`, and every type this file touches (`Scene`,
/// `LightNode`, `LightType`, `RenderSettings`) is one of them, re-exported
/// unchanged by `package:flutter3d/flutter3d.dart` (`export
/// 'package:flutter3d_core/flutter3d_core.dart';`, that package's own
/// `flutter3d.dart`) — so a value built here is exactly the value the
/// application already passed around under the other name. Moving the class
/// here is what lets `render_project.dart` and
/// `flutter3d_render_job/lib/src/scene_from_project.dart` call the *same*
/// sync a live viewport does, instead of each holding a private copy of the
/// same nine lines — the "third copy, deliberate" trade-off
/// `render_project.dart`'s own doc comment accepts for a mesh's vertex data
/// does not apply here, because nothing here needs the application at all.
///
/// **Rebuilt whole on every sync rather than diffed by index.** A light has
/// no id of its own in the document — [SceneLighting.lights] addresses one
/// by its position, the same way [ProjectMaterial]'s own table does — so an
/// index that used to mean one light can mean another the moment an earlier
/// one is removed. Tracking *which* `LightNode` used to be index 3 across a
/// remove is the bookkeeping [SceneSync] pays for because an object's
/// buffers are expensive to reupload; a `LightNode` is four doubles and a
/// colour; rebuilding the handful a project actually carries costs less
/// than getting the bookkeeping wrong would.
library;

import 'package:flutter3d_core/flutter3d_core.dart';

import 'scene_lighting.dart';

/// The scene's own lights, following a project's [SceneLighting].
final class LightingSync {
  final List<LightNode> _managed = <LightNode>[];

  /// Removes every `LightNode` this put in [scene] and adds one per
  /// [lighting]'s own light, in order.
  ///
  /// **This is what makes `RemoveLight` detach a node** — `mat-23`'s own
  /// acceptance. The command itself only ever edits the document; a light
  /// gone from [SceneLighting.lights] is a light this stops re-adding the
  /// next time [sync] runs, which is the only way a `LightNode` ever leaves
  /// a scene it is in (`LightNode.onDetachedFromScene` fires the moment
  /// [Scene.remove] is called on it, below).
  ///
  /// **Additive, not a replacement.** [scene] may already carry lights of
  /// its own — a viewport's fixed key/fill pair, say — and this never
  /// touches one it did not add itself; only [_managed] is ever removed. A
  /// project that has never added a light of its own leaves whatever was
  /// already lighting the scene exactly as it was.
  void sync(Scene scene, SceneLighting lighting) {
    for (final LightNode node in _managed) {
      scene.remove(node);
    }
    _managed.clear();
    for (final ProjectLight light in lighting.lights) {
      final node = LightNode(
        type: switch (light.type) {
          ProjectLightType.point => LightType.point,
          ProjectLightType.spot => LightType.spot,
          // ProjectLightType is a value class, not a sealed one — see its
          // own doc comment — so this switch cannot be exhaustive over its
          // cases. Directional is both the default `ProjectLight` itself
          // takes and the sensible fallback for a value class that grows a
          // fourth kind this file has not been taught yet.
          _ => LightType.directional,
        },
        color: light.color,
        intensity: light.intensity,
        range: light.range,
        castsShadow: light.castsShadow,
        innerConeAngle: light.innerConeAngle,
        outerConeAngle: light.outerConeAngle,
      )..setLocalMatrix(light.transform);
      scene.add(node);
      _managed.add(node);
    }
  }

  /// [settings] with [lighting]'s own exposure, shadow request and bloom
  /// toggle folded in — the `RenderSettings` half of `LightingSync →
  /// LightNode/RenderSettings`.
  ///
  /// **`mat-25`'s own gizmo switch lives here too.** `DebugDrawGizmos
  /// .addLightGizmo` — the arrow, marker sphere and spot cone — is already
  /// built into the renderer's own debug-overlay pass (`view-05`); turning it
  /// on for a project's own lights is a one-field flip on the same
  /// `RenderSettings` this method already produces, not a second seam.
  /// Gated on there being a light at all, so a project with none pays
  /// nothing extra building an empty overlay every frame.
  ///
  /// **Not [SceneLighting.ambientIntensity] or [SceneLighting.environment]
  /// — `tut-07`'s own honest remainder.** The engine's own ambient term
  /// lives on `Scene.ambientIntensity`, not on a frame's `RenderSettings`,
  /// and its default (0.06) does not match [SceneLighting]'s own (0.3) the
  /// way [SceneLighting.exposure]'s default was deliberately chosen to
  /// match `RenderSettings.defaultExposure` — folding it in here would
  /// brighten every scene this build has ever drawn a picture of, sight
  /// unseen, for a field no case or test yet asks to see. A studio/daylight/
  /// sunset [SceneEnvironmentPreset] has no picture at all yet: nothing
  /// maps it to a `SkySettings`/`EnvironmentMap`, the same open gap
  /// `mat-15`/`mat-16`'s own rows already carry for a baked environment
  /// map. Both stay a project value that round-trips without yet reaching a
  /// picture, same as before this row.
  RenderSettings apply(RenderSettings settings, SceneLighting lighting) =>
      settings.copyWith(
        exposure: lighting.exposure,
        shadows: settings.shadows.copyWith(enabled: lighting.shadows),
        bloom: settings.bloom.copyWith(enabled: lighting.post.bloomEnabled),
        debug: settings.debug.copyWith(lightGizmos: lighting.lights.isNotEmpty),
      );
}

/// How many of [lighting]'s own lights `LightBuffer` would not fit into one
/// frame — the same arithmetic `Renderer.render` reports on
/// `FrameResult.lightsDropped` (`renderer.dart`'s own `lights.gather(scene
/// .lights)` followed by `lights.overflow`), run here against a throwaway
/// [Scene] instead of a real one.
///
/// **No device, no draw.** [LightBuffer.gather] only ever needs the scene's
/// own [LightNode]s, and [LightingSync] already knows how to build those
/// from [lighting] alone — so a status line can ask this on every rebuild
/// without waiting for an actual frame to answer, the same way it already
/// reads `project.triangleCount` or `texelDensityOf` fresh each time rather
/// than caching either. `mat-24`'s own acceptance ("девятый источник →
/// оранжевый статус") is this number crossing zero, not a `lights.length >
/// 8` guess — see `computeSceneStatus`'s own doc comment (`scene_mode.dart`)
/// for why that distinction matters.
int lightOverflowOf(SceneLighting lighting) {
  final scene = Scene();
  LightingSync().sync(scene, lighting);
  return (LightBuffer()..gather(scene.lights)).overflow;
}
