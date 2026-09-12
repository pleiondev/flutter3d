/// Keeps the scene's own light nodes and render settings in step with a
/// project's [SceneLighting] — `mat-23`'s own row, the same seam
/// `scene_sync.dart` already keeps between a project's objects and the
/// nodes drawing them.
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

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

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
      );
      scene.add(node);
      _managed.add(node);
    }
  }

  /// [settings] with [lighting]'s own exposure and shadow request folded in
  /// — the `RenderSettings` half of `LightingSync → LightNode/RenderSettings`.
  ///
  /// **`mat-25`'s own gizmo switch lives here too.** `DebugDrawGizmos
  /// .addLightGizmo` — the arrow, marker sphere and spot cone — is already
  /// built into the renderer's own debug-overlay pass (`view-05`); turning it
  /// on for a project's own lights is a one-field flip on the same
  /// `RenderSettings` this method already produces, not a second seam.
  /// Gated on there being a light at all, so a project with none pays
  /// nothing extra building an empty overlay every frame.
  RenderSettings apply(RenderSettings settings, SceneLighting lighting) =>
      settings.copyWith(
        exposure: lighting.exposure,
        shadows: settings.shadows.copyWith(enabled: lighting.shadows),
        debug: settings.debug.copyWith(
          lightGizmos: lighting.lights.isNotEmpty,
        ),
      );
}
