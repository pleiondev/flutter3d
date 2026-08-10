/// The frame this engine actually draws, written as a graph.
///
/// Not yet what executes it — `render()` still runs the sequence by hand. This
/// is the blueprint the migration moves onto, and writing it first is
/// deliberate: it answers "can the graph express this frame at all" before any
/// of the frame is restructured, which is a question worth failing cheaply.
///
/// It is production code rather than a test fixture because the migration will
/// consume it, and because a description of the frame that lives only in a test
/// drifts from the frame within a release.
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

  /// What is shown.
  static const ResourceId frame = ResourceId('frame');
}

/// A pass in the frame, with nothing to execute yet.
///
/// The migration replaces these with real [RenderNode]s one at a time; until
/// then the plan is a shape to check against, and a node with no body is the
/// honest way to write a shape.
final class PlannedPass extends FrameGraphNode {
  const PlannedPass(
    this.name, {
    this.reads = const <ResourceId>[],
    this.optionalReads = const <ResourceId>[],
    this.writes = const <ResourceId>[],
    this.isActive = true,
  });

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> optionalReads;
  @override
  final List<ResourceId> writes;
  @override
  final bool isActive;
}

/// Describes the frame for a given set of switches.
///
/// The switches are the ones `RenderSettings` already carries; they are
/// parameters rather than a `RenderSettings` argument so this stays free of
/// everything else that class holds, and so a test can walk the combinations
/// without building one.
CompiledFrameGraph describeFrame({
  bool directionalShadows = true,
  bool pointShadows = true,
  bool reflections = false,
  bool bloom = true,
  int overlays = 0,
}) {
  final graph = FrameGraph();

  graph.addNode(PlannedPass(
    'directional shadows',
    writes: const <ResourceId>[FrameResourceIds.shadowMap],
    isActive: directionalShadows,
  ));
  graph.addNode(PlannedPass(
    'point shadows',
    writes: const <ResourceId>[
      FrameResourceIds.cubeShadow,
      FrameResourceIds.cubeShadowStatic,
    ],
    isActive: pointShadows,
  ));

  // The shadow maps are *optional* reads, and finding out why is what this
  // description was written for. A hard read culls the scene when shadows are
  // off, which would draw nothing at all; no read at all culls the shadow
  // passes instead, because nothing would want what they produce. The first
  // attempt did the second and the frame came out as scene plus composite.
  //
  // It always declares the surface buffer, even when nothing wants one. Making
  // that write conditional would not compile: reflections declare a read on
  // it, and a resource nobody can write is an error by construction. Declaring
  // it always and letting [CompiledFrameGraph.isRead] decide whether to attach
  // it is simpler, and it is exactly what `RenderSettings.needsSurfaceBuffer`
  // computes by hand today.
  graph.addNode(const PlannedPass(
    'scene',
    optionalReads: <ResourceId>[
      FrameResourceIds.shadowMap,
      FrameResourceIds.cubeShadow,
      FrameResourceIds.cubeShadowStatic,
    ],
    writes: <ResourceId>[
      FrameResourceIds.hdrColour,
      FrameResourceIds.surfaceBuffer,
    ],
  ));

  for (var i = 0; i < overlays; i++) {
    graph.addNode(PlannedPass(
      'overlay $i',
      reads: const <ResourceId>[FrameResourceIds.hdrColour],
      writes: const <ResourceId>[FrameResourceIds.hdrColour],
    ));
  }

  // Before bloom, because a reflection is scene light and a reflected torch
  // that does not glow reads as a sticker on the floor.
  graph.addNode(PlannedPass(
    'reflections',
    reads: const <ResourceId>[
      FrameResourceIds.hdrColour,
      FrameResourceIds.surfaceBuffer,
    ],
    writes: const <ResourceId>[FrameResourceIds.hdrColour],
    isActive: reflections,
  ));

  graph.addNode(PlannedPass(
    'bloom',
    reads: const <ResourceId>[FrameResourceIds.hdrColour],
    writes: const <ResourceId>[FrameResourceIds.bloom],
    isActive: bloom,
  ));

  // The glow is optional for the same reason the shadow maps are: with bloom
  // off the composite still has to run, and with bloom on the bloom pass has
  // to survive. It already treats a missing glow the way the shader does, as
  // an intensity of zero.
  graph.addNode(const PlannedPass(
    'composite',
    reads: <ResourceId>[FrameResourceIds.hdrColour],
    optionalReads: <ResourceId>[FrameResourceIds.bloom],
    writes: <ResourceId>[FrameResourceIds.frame],
  ));

  return graph.compile(outputs: const <ResourceId>[FrameResourceIds.frame]);
}
