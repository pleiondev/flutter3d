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

/// Everything the frame produces or hands around.
///
/// Named constants rather than bare strings so a misspelling is a compile
/// error here instead of a graph error at run time — the graph checks names it
/// is given, but it cannot check the ones it never receives.
abstract final class FrameResourceIds {
  /// The scene's HDR colour, before any post.
  static const ResourceId hdrColour = ResourceId('hdr_colour');

  /// World normal and depth, the second attachment of the scene pass.
  static const ResourceId surfaceBuffer = ResourceId('surface_buffer');

  /// The directional light's shadow map.
  static const ResourceId shadowMap = ResourceId('shadow_map');

  /// The point lights' cube atlases, dynamic and baked.
  static const ResourceId cubeShadow = ResourceId('cube_shadow');
  static const ResourceId cubeShadowStatic = ResourceId('cube_shadow_static');

  /// The bloom pyramid.
  static const ResourceId bloom = ResourceId('bloom');

  /// Ambient occlusion, at half the scene's resolution.
  ///
  /// Half because occlusion is low-frequency by nature — it is the shape of a
  /// corner, not the detail in it — and because the pass reads the surface
  /// buffer twelve times per pixel.
  static const ResourceId ao = ResourceId('ao');

  /// What is shown.
  static const ResourceId frame = ResourceId('frame');

  /// The filtered cube of the [index]th reflection probe in the scene.
  ///
  /// One name per probe rather than one for all of them, because a resource
  /// is a texture and a scene may hold several: the scene node declares an
  /// optional read of each, which is what orders every probe's capture before
  /// the world that reflects it.
  static ResourceId reflectionProbe(int index) =>
      ResourceId('reflection_probe_$index');
}
