/// Scene-wide lighting, carried on the project the way [ProjectMaterial]'s
/// own table is.
///
/// **A document value, not a runtime one.** [ProjectLight] mirrors
/// `LightNode`'s own fields (type, colour, intensity, range, a shadow
/// request, the two cone angles) but knows nothing about a scene graph — the
/// same split [ProjectMaterial] keeps from `Material`, and the same reason:
/// this file has to serialize, journal and undo without a `GraphicsDevice`
/// anywhere nearby. Pushing a value here onto the actual `LightNode`s and
/// `RenderSettings` a viewport draws is `LightingSync`'s job
/// (`lighting_sync.dart`, this same package) — no `GraphicsDevice` needed
/// for that either, only `flutter3d_core`'s scene graph, which
/// `render_project.dart` already depends on for the identical reason.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Which kind of light a [ProjectLight] is.
///
/// **A value class rather than an enum, for the reason `LightingModel`'s
/// own class comment gives: this list is not closed.** `LightNode`'s own
/// `LightType` — a package this one does not depend on — can add a fourth
/// kind (an area light, a rect light) without this file ever knowing, and a
/// published package's own enum would break every switch written against
/// it the day that happens.
final class ProjectLightType {
  const ProjectLightType._(this.name);

  final String name;

  static const ProjectLightType directional = ProjectLightType._('directional');
  static const ProjectLightType point = ProjectLightType._('point');
  static const ProjectLightType spot = ProjectLightType._('spot');

  static const List<ProjectLightType> values = <ProjectLightType>[
    directional,
    point,
    spot,
  ];

  @override
  String toString() => 'ProjectLightType.$name';
}

/// One light in [SceneLighting.lights], addressed by its position in the
/// list — the same convention [ProjectMaterial]'s own table uses, and for
/// the same reason: nothing here needs to survive a reorder the way an
/// object survives one under undo, so a row is only ever appended or
/// collapsed, and every command that names one takes the index it is at
/// right now.
final class ProjectLight {
  ProjectLight({
    this.type = ProjectLightType.directional,
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.castsShadow = false,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = math.pi / 4.0,
    Matrix4? transform,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0),
       transform = transform ?? Matrix4.identity();

  final ProjectLightType type;

  /// Linear RGB, the same space `LightNode.color` is in.
  final Vector3 color;

  final double intensity;

  /// Distance at which a point or spot light stops contributing. Zero means
  /// unbounded, matching `LightNode`'s own default.
  final double range;

  /// A request, not a promise — see `LightNode.castsShadow`'s own doc
  /// comment for what "one directional, one point" means for a second one
  /// that asks.
  final bool castsShadow;

  final double innerConeAngle;
  final double outerConeAngle;

  /// Where the light sits and which way it points, local to the scene's
  /// own root — the same single [Matrix4] `ModelObject.transform` carries
  /// for an object, rather than a separate position/rotation pair, so a
  /// light is placed the same way everything else in a project already is.
  /// Identity by default, matching `LightNode`'s own default of "at the
  /// scene's own origin, pointing down -Z" — the gap `LightingSync` used to
  /// leave every light in before `mat-24` closed it.
  final Matrix4 transform;

  ProjectLight copyWith({
    ProjectLightType? type,
    Vector3? color,
    double? intensity,
    double? range,
    bool? castsShadow,
    double? innerConeAngle,
    double? outerConeAngle,
    Matrix4? transform,
  }) => ProjectLight(
    type: type ?? this.type,
    color: color ?? this.color,
    intensity: intensity ?? this.intensity,
    range: range ?? this.range,
    castsShadow: castsShadow ?? this.castsShadow,
    innerConeAngle: innerConeAngle ?? this.innerConeAngle,
    outerConeAngle: outerConeAngle ?? this.outerConeAngle,
    transform: transform ?? this.transform,
  );
}

/// Which built-in sky a project's viewport is lit against, as a value rather
/// than a texture — the project file has no room to carry six cube faces of
/// its own, and `mat-15`'s own `Material Studio` already established the
/// vocabulary these three names come from.
///
/// **Deliberately three fixed presets and not a general environment
/// reference.** The row this type exists for names "environment" as one
/// field beside lights, shadows and exposure, not as a slot for an imported
/// panorama — that is `mat-15`'s own concern, one document scene down from
/// this one, and giving this field an open-ended value now would be
/// building the bigger feature nobody asked this row for.
/// A value class rather than an enum, for the reason [ProjectLightType] is
/// one: a fourth preset is a name this file can add without breaking a
/// switch a caller already wrote against the first three.
final class SceneEnvironmentPreset {
  const SceneEnvironmentPreset._(this.name);

  final String name;

  static const SceneEnvironmentPreset none = SceneEnvironmentPreset._('none');
  static const SceneEnvironmentPreset studio = SceneEnvironmentPreset._(
    'studio',
  );
  static const SceneEnvironmentPreset daylight = SceneEnvironmentPreset._(
    'daylight',
  );
  static const SceneEnvironmentPreset sunset = SceneEnvironmentPreset._(
    'sunset',
  );

  static const List<SceneEnvironmentPreset> values = <SceneEnvironmentPreset>[
    none,
    studio,
    daylight,
    sunset,
  ];

  @override
  String toString() => 'SceneEnvironmentPreset.$name';
}

/// Post-processing knobs a project carries as document state.
///
/// **Narrow on purpose.** The row this exists for names "пост" as one word
/// beside lights, environment, shadows and exposure — `RenderSettings` in
/// the engine already has a much larger `LookSettings`/`BloomSettings` pair
/// with a dozen fields between them, and mirroring all of it into document
/// state before anything reads more than one of those fields would be
/// speculative. [bloomEnabled] is the one post-processing toggle a person
/// is likely to want per project rather than per session; the rest stays a
/// viewport setting until a row asks for more of it by name.
final class ScenePostSettings {
  const ScenePostSettings({this.bloomEnabled = true});

  final bool bloomEnabled;

  ScenePostSettings copyWith({bool? bloomEnabled}) =>
      ScenePostSettings(bloomEnabled: bloomEnabled ?? this.bloomEnabled);
}

/// A project's own lighting, environment, ambient level, shadow request and
/// post-processing — everything `mat-23`'s own row names, held as one value
/// on [ModelProject.lighting].
final class SceneLighting {
  const SceneLighting({
    this.lights = const <ProjectLight>[],
    this.environment = SceneEnvironmentPreset.none,
    this.ambientIntensity = 0.3,
    this.shadows = false,
    this.exposure = 1.6,
    this.post = const ScenePostSettings(),
    this.panorama,
  });

  final List<ProjectLight> lights;
  final SceneEnvironmentPreset environment;

  /// A flat ambient term, applied the way a viewport's own hemispheric
  /// ambient already is — this is the document's own opinion of it, not a
  /// second light.
  final double ambientIntensity;

  /// Whether this project's own lights ask the viewport for a shadow map.
  /// A request, matching every individual [ProjectLight.castsShadow] — a
  /// scene-wide off short-circuits every light's own ask without a caller
  /// having to walk the list.
  final bool shadows;

  /// Matches `RenderSettings.exposure`'s own default, so a project that has
  /// never touched this field draws exactly what it always drew.
  final double exposure;

  final ScenePostSettings post;

  /// An index into [ModelProject.images], or null — `ux-49`.
  ///
  /// **A panorama beside the presets rather than a fifth preset.** The four
  /// [SceneEnvironmentPreset] values are names this build knows how to draw;
  /// a panorama is a picture the project carries, and the two cannot be the
  /// same field without one of them becoming a string that sometimes means a
  /// file. When this is set it is what lights the scene, and [environment]
  /// is what a project falls back to when the image is cleared.
  ///
  /// **An index into the image table**, like every texture binding in this
  /// document, so a panorama is saved with the project and travels with it
  /// rather than being a path that may not exist on the next machine.
  ///
  /// `SetPanorama` is the only thing that sets this, and it refuses an image
  /// that is not twice as wide as it is tall — see that command for why.
  final int? panorama;

  SceneLighting copyWith({
    List<ProjectLight>? lights,
    SceneEnvironmentPreset? environment,
    double? ambientIntensity,
    bool? shadows,
    double? exposure,
    ScenePostSettings? post,
    int? panorama,
    bool clearPanorama = false,
  }) => SceneLighting(
    lights: lights ?? this.lights,
    environment: environment ?? this.environment,
    ambientIntensity: ambientIntensity ?? this.ambientIntensity,
    shadows: shadows ?? this.shadows,
    exposure: exposure ?? this.exposure,
    post: post ?? this.post,
    panorama: clearPanorama ? null : (panorama ?? this.panorama),
  );
}
