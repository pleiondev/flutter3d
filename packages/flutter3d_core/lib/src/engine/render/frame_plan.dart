/// The names this engine's frame is drawn from.
///
/// This file also held `describeFrame` — a frame written out as bodyless nodes,
/// which the real one was checked against while it moved onto the graph.
/// Writing that description first was deliberate and it paid: it answered "can
/// the graph express this frame at all" before any of the frame was
/// restructured, and it found four gaps in the model, the optional read among
/// them, none of which the graph's own tests could have shown.
///
/// **It is gone, and it should be.** It described a frame; the renderer now
/// *is* that frame, node for node, down to the two halves of the cube atlas
/// that were the last thing outside the graph. A second description would from
/// here on only ever be checked against itself — and worse, the one question it
/// still answered, whether the surface buffer is wanted, it answered wrongly by
/// construction: only the compiled graph can see a read declared by an
/// application's own node, and a description of the built-in passes cannot.
library;

import 'frame_graph.dart';

/// The names of the engine's passes that code outside the renderer refers
/// to, as `FrameResult.passes` reports them: a plugin ordering a node after
/// one, a check that looks for one in a frame.
///
/// For the reason [FrameResourceIds] are constants: the node, the
/// `RenderStep` that owns it, `RenderSettings.passOrder` and every reader
/// spell the name once, here. `RenderSettings.passOrder` lists every name.
abstract final class FramePassNames {
  /// Decals painted onto the opaque half.
  static const String decals = 'decals';

  /// The motion the camera alone gives every pixel.
  static const String cameraVelocity = 'camera velocity';

  /// The motion of the nodes that moved, over [cameraVelocity]'s.
  static const String objectVelocity = 'object velocity';
}

/// Everything the frame produces or hands around.
///
/// Named constants rather than bare strings so a misspelling is a compile
/// error here instead of a graph error at run time — the graph checks names it
/// is given, but it cannot check the ones it never receives.
abstract final class FrameResourceIds {
  /// The scene's HDR colour, before any post: linear, unbounded and before
  /// exposure, in the renderer's light scale, whose unit is
  /// `FrameContext.nitsPerHdrUnit` nits ("Frame resources a stage reads" in
  /// `docs/CONTRACTS.md`).
  static const ResourceId hdrColor = ResourceId('f3d.hdr_color');

  /// The second attachment of the scene pass: the world normal,
  /// octahedral-encoded, in `rg`, the perceptual roughness in `b`, and the
  /// depth along the view axis in metres in `a`; all zero where nothing was
  /// drawn. A debug view may take `rgb` over. Frozen within 1.x ("Frame
  /// resources a stage reads" in `docs/CONTRACTS.md`).
  static const ResourceId surfaceBuffer = ResourceId('f3d.surface_buffer');

  /// Each surface's own colour, sRGB in eight bits, the scene pass's third
  /// attachment — `L5`. Present only when a pass reads it, the surface buffer
  /// is attached too and the device opens three colour attachments.
  static const ResourceId albedoBuffer = ResourceId('f3d.albedo_buffer');

  /// The directional light's shadow map.
  static const ResourceId shadowMap = ResourceId('f3d.shadow_map');

  /// The directional map as blurred exponential moments, for the `evsm`
  /// filter — `S2`. Made from [shadowMap], never instead of it.
  static const ResourceId shadowMoments = ResourceId('f3d.shadow_moments');

  /// The point lights' cube atlases, dynamic and baked.
  static const ResourceId cubeShadow = ResourceId('f3d.cube_shadow');
  static const ResourceId cubeShadowStatic = ResourceId(
    'f3d.cube_shadow_static',
  );

  /// The bloom pyramid.
  static const ResourceId bloom = ResourceId('f3d.bloom');

  /// Ambient occlusion, at half the scene's resolution.
  ///
  /// Half because occlusion is low-frequency by nature — it is the shape of a
  /// corner, not the detail in it — and because the pass reads the surface
  /// buffer twelve times per pixel.
  static const ResourceId ao = ResourceId('f3d.ao');

  /// The short march toward the sun, at the scene's own resolution —
  /// `gfx-76n`.
  ///
  /// Full resolution where the occlusion is half, and for the reason the
  /// occlusion is half: a contact shadow is the *highest*-frequency thing in
  /// the frame — a seam a few pixels wide where a box meets a floor — and at
  /// half resolution it is either gone or a step. It costs less than the
  /// occlusion anyway: sixteen taps along one line against twelve over a
  /// hemisphere, and only where a surface faces the light.
  static const ResourceId contactShadow = ResourceId('f3d.contact_shadow');

  /// The local exposure, in stops per place, at an eighth of the frame —
  /// `R7`. Produced only while `RenderSettings.localExposure` is on.
  static const ResourceId localExposure = ResourceId('f3d.local_exposure');

  /// How far each pixel moved on screen since the last frame, in UV units
  /// (nought to one from the top left), now minus then — `R1`. Red and
  /// green; zero where nothing was drawn. Produced while
  /// `RenderStep.velocity` is on and something reads it: temporal
  /// anti-aliasing, motion blur, or a placed node whose read switches the
  /// producer on.
  ///
  /// The HDR format because it holds signed fractions, and there is no
  /// two-channel float format in `TextureFormat` to be smaller with.
  static const ResourceId velocity = ResourceId('f3d.velocity');

  /// The temporal resolve's history, at the output's size — `R2`. The
  /// renderer's own texture, maintained across frames, so it is a `keeps`
  /// rather than a write: what it holds is the running blend of every frame
  /// since the last cut.
  static const ResourceId temporalHistory = ResourceId('f3d.temporal_history');

  /// The irradiance field's atlas as the GPU keeps it — `L4`. Maintained
  /// across frames, a `keeps` of the update node.
  static const ResourceId irradianceAtlas = ResourceId('f3d.irradiance_atlas');

  /// The scene's log luminance at a fixed small size, for the exposure meter
  /// to read back. Produced only while auto exposure is on.
  static const ResourceId luminance = ResourceId('f3d.luminance');

  /// The surface buffer's farthest depth over blocks of it, at a fixed small
  /// size in RGBA8, for the occlusion readback to reproject — `C3`. Produced
  /// only while `RenderSettings.occlusion` is `OcclusionMode.hiZ`.
  static const ResourceId depthPyramid = ResourceId('f3d.depth_pyramid');

  /// The scene as the opaque half left it, at its own size and at five
  /// halvings, side by side in one texture — `M3`, for the transmissive draws
  /// to read. Produced only on a frame that holds one; see
  /// `SceneColorChain`.
  static const ResourceId sceneColor = ResourceId('f3d.scene_color');

  /// Which node drew each pixel, as an id in RGBA8. Produced only on a frame
  /// something asked to pick from.
  static const ResourceId objectIds = ResourceId('f3d.object_ids');

  /// The colour each marked node is ringed in, where the scene shows it, in
  /// RGBA8 with alpha one where a mark is — `N9`. Produced only while the
  /// high-contrast look is on and some node carries a `MeshNode.outlineColor`.
  static const ResourceId outlineMask = ResourceId('f3d.outline_mask');

  /// What is shown.
  static const ResourceId frame = ResourceId('f3d.frame');

  /// The vertices a `SkinningHook` wrote for the meshes it skins this
  /// frame, a buffer for each, which the scene draws in place of the
  /// meshes' own. Produced only while a hook is placed.
  static const ResourceId skinnedVertices = ResourceId('f3d.skinned_vertices');

  /// What the frame's compute workloads wrote for the scene to draw: a
  /// water's surface, particles to instance — `WorkloadStep`. The scene
  /// reads it while a workload is in the frame, so the graph keeps every
  /// workload's step, and runs it, before the draws. Since 1.0.0-rc.1+1.
  static const ResourceId computedVertices = ResourceId(
    'f3d.computed_vertices',
  );

  /// The filtered cube of the [index]th reflection probe in the scene.
  ///
  /// One name per probe rather than one for all of them, because a resource
  /// is a texture and a scene may hold several: the scene node declares an
  /// optional read of each, which is what orders every probe's capture before
  /// the world that reflects it.
  static ResourceId reflectionProbe(int index) =>
      ResourceId('f3d.reflection_probe_$index');

  /// What the scene's `RenderTexture`s were drawn into — `P4`.
  ///
  /// One name for all of them, and what it stands for is the order: the
  /// scene reads it optionally, so every camera into a texture draws before
  /// the materials that show its picture. The pictures themselves are each
  /// texture's own and outlive the frame.
  static const ResourceId renderTextures = ResourceId('f3d.render_textures');

  /// The mirrored pictures of the scene's planar reflectors — `P4`, one
  /// name for all of them and every view, for [renderTextures]' reason.
  static const ResourceId planarReflections = ResourceId(
    'f3d.planar_reflections',
  );
}
