/// A named place in the frame where a plugin's pass goes.
///
/// **Every pass the engine draws has an anchor before it and one after it.**
/// A plugin does not say "priority 450"; it says "after the shadows", "before
/// the transparent half", "before tone mapping", and the renderer puts its
/// node there. Several nodes at one anchor are ordered among themselves by
/// their `after`/`before` constraints and, where those leave a choice, by
/// registration order: the application's own first, then each plugin's in
/// install order, as everywhere else in the plugin API.
///
/// The frame runs the anchors in the order of [values]. Between an anchor
/// `beforeX` and its `afterX` stand the engine's own passes for `X`; between
/// `afterX` and the next `beforeY` stands nothing, so a node at `afterX` runs
/// before a node at `beforeY`. An anchor stays when the passes around it are
/// switched off, or move into an addon: a node placed `beforeBloom` runs
/// where the glow would be taken, whether or not one is.
///
/// **What an anchor promises is what has been drawn when the node runs**, and
/// the renderer's frame graph turns that into reads and writes: a node at an
/// anchor reads the versions of the frame's resources that the passes before
/// it left, and the passes after it read what it wrote. Two passes that touch
/// nothing in common may still run in either order; the anchor fixes the
/// version chain, not the clock.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1): a later
/// minor may add an anchor around a pass the engine gains, and a `switch`
/// written against today's set would break on it. The names are stable: an
/// anchor is never renamed or removed within a major, and a `.f3dplugin`
/// file names one by [name].
///
/// **A plugin may define its own (1.0).** [RenderAnchor.after] makes an
/// anchor that stands right after another — an engine anchor, or another
/// plugin's — so a plugin that draws in several places gives its own nodes,
/// and the plugins built on it, a place to meet that does not move when the
/// engine renames one of its passes. Its name is the plugin's to choose and
/// is namespaced (`<pluginId>.<name>`); the renderer refuses a node at an
/// anchor nobody added (`RendererSteps.addAnchor`).
final class RenderAnchor {
  const RenderAnchor._(this.name) : follows = null;

  /// A plugin's anchor called [name], standing right after [follows]: a node
  /// placed here runs after every node at [follows] and before anything that
  /// stands after it. [name] is namespaced — `<pluginId>.<name>` — so two
  /// plugins' anchors cannot collide, and it cannot be an engine anchor's.
  const RenderAnchor.after(RenderAnchor this.follows, this.name);

  /// What the anchor is called, in errors and in the renderer's reports.
  final String name;

  /// The anchor this one stands right after; null for the engine's own,
  /// which stand in the order of [values].
  final RenderAnchor? follows;

  /// Whether this is one of the engine's anchors, in [values].
  bool get isEngine => follows == null;

  /// The engine anchor this one is placed after, through any chain of
  /// plugin anchors; itself for an engine anchor.
  RenderAnchor get engineAnchor => follows?.engineAnchor ?? this;

  // -- Before the scene ---------------------------------------------------

  /// The start of the frame: nothing has been drawn.
  static const RenderAnchor beforeShadows = RenderAnchor._(
    'f3d.before_shadows',
  );

  /// The shadow maps are drawn: the point lights' atlases, the directional
  /// cascades and their moments. Nothing lit has been drawn yet.
  static const RenderAnchor afterShadows = RenderAnchor._('f3d.after_shadows');

  /// Before the captures the scene samples: reflection probes, the
  /// irradiance field's update, render textures and planar reflections.
  static const RenderAnchor beforeCaptures = RenderAnchor._(
    'f3d.before_captures',
  );

  /// The captures are taken; the scene has not been drawn.
  static const RenderAnchor afterCaptures = RenderAnchor._(
    'f3d.after_captures',
  );

  // -- The scene ----------------------------------------------------------

  /// Before the opaque half of the scene. The scene pass draws the opaque
  /// geometry and the sky in one render pass, so nothing can run between
  /// the two: a node here runs before both.
  static const RenderAnchor beforeOpaque = RenderAnchor._('f3d.before_opaque');

  /// The opaque half and the sky are drawn, in HDR, with the surface buffer
  /// beside them. No decal, no glass.
  static const RenderAnchor afterOpaque = RenderAnchor._('f3d.after_opaque');

  /// Before the decals are painted onto the opaque half.
  static const RenderAnchor beforeDecals = RenderAnchor._('f3d.before_decals');

  /// The decals are painted; the glass is not drawn.
  static const RenderAnchor afterDecals = RenderAnchor._('f3d.after_decals');

  /// Before the transparent half: its copy of the scene and the glass drawn
  /// over it.
  static const RenderAnchor beforeTransparent = RenderAnchor._(
    'f3d.before_transparent',
  );

  /// The transparent half is drawn.
  static const RenderAnchor afterTransparent = RenderAnchor._(
    'f3d.after_transparent',
  );

  /// The whole scene is drawn, with the object ids and the outline marks,
  /// and no post step has run. Where `FramePhase.overlay` puts a node.
  static const RenderAnchor afterScene = RenderAnchor._('f3d.after_scene');

  // -- Light and shadow on the lit picture --------------------------------

  /// Before the screen-space reflections.
  static const RenderAnchor beforeReflections = RenderAnchor._(
    'f3d.before_reflections',
  );

  /// The screen-space reflections are added.
  static const RenderAnchor afterReflections = RenderAnchor._(
    'f3d.after_reflections',
  );

  /// Before the exposure meter reads the picture.
  static const RenderAnchor beforeAutoExposure = RenderAnchor._(
    'f3d.before_auto_exposure',
  );

  /// The exposure meter has read the picture.
  static const RenderAnchor afterAutoExposure = RenderAnchor._(
    'f3d.after_auto_exposure',
  );

  /// Before the depth pyramid the next frame culls with.
  static const RenderAnchor beforeHiZ = RenderAnchor._('f3d.before_hi_z');

  /// The depth pyramid is built.
  static const RenderAnchor afterHiZ = RenderAnchor._('f3d.after_hi_z');

  /// Before the ambient occlusion and its blur.
  static const RenderAnchor beforeAmbientOcclusion = RenderAnchor._(
    'f3d.before_ambient_occlusion',
  );

  /// The ambient occlusion is computed and blurred.
  static const RenderAnchor afterAmbientOcclusion = RenderAnchor._(
    'f3d.after_ambient_occlusion',
  );

  /// Before the contact shadows and their resolve.
  static const RenderAnchor beforeContactShadows = RenderAnchor._(
    'f3d.before_contact_shadows',
  );

  /// The contact shadows are marched and resolved.
  static const RenderAnchor afterContactShadows = RenderAnchor._(
    'f3d.after_contact_shadows',
  );

  /// Before the motion of every pixel is written, with the reactive mask
  /// and the two histories the noisy effects are carried in.
  static const RenderAnchor beforeVelocity = RenderAnchor._(
    'f3d.before_velocity',
  );

  /// The velocity, the reactive mask and the histories are written.
  static const RenderAnchor afterVelocity = RenderAnchor._(
    'f3d.after_velocity',
  );

  /// Before the fog marched through the light.
  static const RenderAnchor beforeVolumetricFog = RenderAnchor._(
    'f3d.before_volumetric_fog',
  );

  /// The volumetric fog is added.
  static const RenderAnchor afterVolumetricFog = RenderAnchor._(
    'f3d.after_volumetric_fog',
  );

  /// Before the shafts of sunlight.
  static const RenderAnchor beforeLightShafts = RenderAnchor._(
    'f3d.before_light_shafts',
  );

  /// The light shafts are added.
  static const RenderAnchor afterLightShafts = RenderAnchor._(
    'f3d.after_light_shafts',
  );

  // -- The lens and the sensor --------------------------------------------

  /// Before the depth of field.
  static const RenderAnchor beforeDepthOfField = RenderAnchor._(
    'f3d.before_depth_of_field',
  );

  /// The depth of field is applied.
  static const RenderAnchor afterDepthOfField = RenderAnchor._(
    'f3d.after_depth_of_field',
  );

  /// Before the motion blur.
  static const RenderAnchor beforeMotionBlur = RenderAnchor._(
    'f3d.before_motion_blur',
  );

  /// The motion blur is applied.
  static const RenderAnchor afterMotionBlur = RenderAnchor._(
    'f3d.after_motion_blur',
  );

  /// Before the jittered frames are blended across time.
  static const RenderAnchor beforeTemporalResolve = RenderAnchor._(
    'f3d.before_temporal_resolve',
  );

  /// The temporal resolve has run. With it on, a node from here to the end
  /// works at the output size.
  static const RenderAnchor afterTemporalResolve = RenderAnchor._(
    'f3d.after_temporal_resolve',
  );

  /// Before the local exposure is measured.
  static const RenderAnchor beforeLocalExposure = RenderAnchor._(
    'f3d.before_local_exposure',
  );

  /// The local exposure is measured.
  static const RenderAnchor afterLocalExposure = RenderAnchor._(
    'f3d.after_local_exposure',
  );

  /// Before the glow is taken from the picture.
  static const RenderAnchor beforeBloom = RenderAnchor._('f3d.before_bloom');

  /// The glow is taken; the lens flare is not drawn from it yet.
  static const RenderAnchor afterBloom = RenderAnchor._('f3d.after_bloom');

  /// Before the lens flare is drawn from the glow.
  static const RenderAnchor beforeLensFlare = RenderAnchor._(
    'f3d.before_lens_flare',
  );

  /// The lens flare is added to the glow.
  static const RenderAnchor afterLensFlare = RenderAnchor._(
    'f3d.after_lens_flare',
  );

  // -- The composite and after it -----------------------------------------

  /// The last place the picture is linear and unbounded: the composite that
  /// follows tone maps it, grades it and adds the glow, the lens and the
  /// film.
  static const RenderAnchor beforeTonemap = RenderAnchor._(
    'f3d.before_tonemap',
  );

  /// The picture is tone mapped and display-referred.
  static const RenderAnchor afterTonemap = RenderAnchor._('f3d.after_tonemap');

  /// Before a reduced render scale is brought up to the output size.
  static const RenderAnchor beforeSpatialUpscale = RenderAnchor._(
    'f3d.before_spatial_upscale',
  );

  /// The picture is at the output size. With the upscale on, a node from
  /// here to the end works at the output size.
  static const RenderAnchor afterSpatialUpscale = RenderAnchor._(
    'f3d.after_spatial_upscale',
  );

  /// Before the edge smoothing and the sharpening.
  static const RenderAnchor beforeEdgeSmoothing = RenderAnchor._(
    'f3d.before_edge_smoothing',
  );

  /// The edges are smoothed and sharpened.
  static const RenderAnchor afterEdgeSmoothing = RenderAnchor._(
    'f3d.after_edge_smoothing',
  );

  /// Before the high-contrast look and its outlines.
  static const RenderAnchor beforeHighContrast = RenderAnchor._(
    'f3d.before_high_contrast',
  );

  /// The high-contrast look is applied.
  static const RenderAnchor afterHighContrast = RenderAnchor._(
    'f3d.after_high_contrast',
  );

  /// Before the editor's viewport shading modes.
  static const RenderAnchor beforeViewportShading = RenderAnchor._(
    'f3d.before_viewport_shading',
  );

  /// The viewport shading is applied.
  static const RenderAnchor afterViewportShading = RenderAnchor._(
    'f3d.after_viewport_shading',
  );

  /// The end of the frame: the picture is what the caller is about to be
  /// handed. Where `FramePhase.present` puts a node.
  static const RenderAnchor beforePresent = RenderAnchor._(
    'f3d.before_present',
  );

  /// The value called [name], or null for a name this version does not
  /// know, which is what a file written by a later version can carry.
  static RenderAnchor? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Every anchor, in the order the frame meets them.
  static const List<RenderAnchor> values = <RenderAnchor>[
    beforeShadows,
    afterShadows,
    beforeCaptures,
    afterCaptures,
    beforeOpaque,
    afterOpaque,
    beforeDecals,
    afterDecals,
    beforeTransparent,
    afterTransparent,
    afterScene,
    beforeReflections,
    afterReflections,
    beforeAutoExposure,
    afterAutoExposure,
    beforeHiZ,
    afterHiZ,
    beforeAmbientOcclusion,
    afterAmbientOcclusion,
    beforeContactShadows,
    afterContactShadows,
    beforeVelocity,
    afterVelocity,
    beforeVolumetricFog,
    afterVolumetricFog,
    beforeLightShafts,
    afterLightShafts,
    beforeDepthOfField,
    afterDepthOfField,
    beforeMotionBlur,
    afterMotionBlur,
    beforeTemporalResolve,
    afterTemporalResolve,
    beforeLocalExposure,
    afterLocalExposure,
    beforeBloom,
    afterBloom,
    beforeLensFlare,
    afterLensFlare,
    beforeTonemap,
    afterTonemap,
    beforeSpatialUpscale,
    afterSpatialUpscale,
    beforeEdgeSmoothing,
    afterEdgeSmoothing,
    beforeHighContrast,
    afterHighContrast,
    beforeViewportShading,
    afterViewportShading,
    beforePresent,
  ];

  /// The engine anchor called [name], or null. A plugin's anchors are found
  /// through the renderer that added them (`RendererSteps.anchorNamed`).
  ///
  /// The word from before the `f3d.` prefix (`after bloom`) finds the anchor
  /// too, as the files written then name it: a word without a dot was
  /// always the engine's.
  static RenderAnchor? named(String name) {
    final word = name.contains('.')
        ? name
        : 'f3d.${name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_')}';
    for (final anchor in values) {
      if (anchor.name == name || anchor.name == word) return anchor;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is RenderAnchor && other.name == name && other.follows == follows;

  @override
  int get hashCode => Object.hash(name, follows);

  @override
  String toString() => 'RenderAnchor($name)';
}
