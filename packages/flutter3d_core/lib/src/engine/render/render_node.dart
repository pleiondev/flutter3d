/// The one place a frame is extended: a node that owns a pass, placed at a
/// [RenderAnchor] through `RendererSteps.addNode`, and the view-aware frame
/// context every node and contributor is handed.
///
/// Split from [FrameGraphNode] so the scheduling half stays free of GPU types:
/// `frame_graph.dart` works out the order, the culling and the lifetimes with
/// no device in sight, and this is where that meets a render pass.
///
/// **One way to add a pass, since 1.0.** Before it there were five:
/// `Renderer.addContributor`, `Renderer.addNode` with a `FramePhase`,
/// `RenderNodeRegistry`, `RendererSteps.addNode(at:)` and `FullscreenEffect`
/// registering itself. Now a pass is a [RenderNode] added with
/// `RendererSteps.addNode` (at its [RenderNode.defaultAnchor], or at any
/// anchor, the engine's or a plugin's own); a `FullscreenEffect` is one such
/// node; and draws that belong *inside* the engine's own passes — particles,
/// splats — are a `PassContributor` added through the same registry with
/// `RendererSteps.addContributor`. Both are handed a [FrameContext].
///
/// A node **owns** its pass, which is the difference between it and a
/// `PassContributor`. A contributor is handed a pass and draws into it; a node
/// builds its own, so handing it one would be meaningless. That is why
/// [RenderFrame] carries no pass. It is not an omission.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor, WorldPosition;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/projection.dart' show jitterOffset;
import 'frame_graph.dart';
import 'frame_resources.dart';
import 'pass_contributor.dart';
import 'render_view.dart';
import 'renderer.dart';

/// What every node and contributor is told about the frame it is drawing in:
/// the view, its matrices and jitter, the clock, and the device.
///
/// **View-aware since 1.0** (rendering review, Must 5). A node used to be
/// handed a device, the resources and a size, and had to find the camera on
/// its own; one that wanted the projection, the jitter the temporal resolve
/// drew with, or how long the renderer had been running had nowhere to ask.
/// Every one of those is here, for the frame's [view].
abstract base class FrameContext {
  /// The context of a frame drawn on [device] at [width] × [height] with
  /// [settings], through [view] — null for a frame with no camera, such as
  /// `Renderer.renderPost`'s.
  FrameContext({
    required this.device,
    required this.services,
    required this.settings,
    required this.width,
    required this.height,
    this.view,
    this.frameIndex = 0,
    this.time = 0.0,
    this.origin = WorldPosition.origin,
  });

  /// The backend: how a node opens the pass it owns.
  ///
  /// It arrives as a value rather than being reached for, which is what makes
  /// a node's drawing assertable by a test: hand it a recording device and
  /// the pass it built, its attachments and its draws are all readable with
  /// no GPU in the room.
  final GraphicsDevice device;

  /// What the renderer does for a node: drawing the scene into a pass, and
  /// drawing a full-screen stage.
  final RenderServices services;

  /// The settings this frame is drawn with.
  final RenderSettings settings;

  /// The size of what is being drawn into, in pixels.
  final int width;

  /// See [width].
  final int height;

  /// The view this frame is drawn through — the first of the `render` call's
  /// — or null for a frame with no camera.
  final RenderView? view;

  /// How many frames the renderer has drawn before this one.
  final int frameIndex;

  /// Seconds since the renderer drew its first frame — the clock an
  /// animated effect reads.
  final double time;

  /// Where the scene's own space starts in the world (`Scene.origin`): what
  /// a node that holds a [WorldPosition] subtracts to draw it. Every matrix
  /// and position a frame hands out is in that scene space (see "Space" in
  /// `docs/CONTRACTS.md`).
  final WorldPosition origin;

  FramePassState _state = FramePassState();

  /// Counts one draw a node or contributor issued itself, in the frame's
  /// report (`FrameResult.drawCalls`), with the [triangles] and [instances]
  /// it drew when it knows them.
  void noteDraw({int triangles = 0, int instances = 0}) {
    _state
      ..drawCalls += 1
      ..triangles += triangles
      ..instances += instances;
  }

  /// How many draws the frame has issued so far.
  int get drawCalls => _state.drawCalls;

  /// Says that a pipeline of the caller's own is bound now, so the next
  /// thing the renderer draws binds its own again rather than trusting the
  /// one it last bound — what a contributor calls after binding a pipeline.
  void invalidatePipeline() => _state.invalidatePipeline();

  /// The [view]'s camera's view matrix: world (the scene's space) to eye.
  /// Identity without a view.
  vm.Matrix4 get viewMatrix =>
      view?.camera.viewMatrix.clone() ?? vm.Matrix4.identity();

  /// The [view]'s projection at its own aspect, without the jitter. Identity
  /// without a view.
  vm.Matrix4 get projection {
    final camera = view?.camera;
    if (camera == null) return vm.Matrix4.identity();
    return camera.projection.toMatrix(_aspect);
  }

  /// [projection] times [viewMatrix]: the unjittered view-projection.
  vm.Matrix4 get unjitteredViewProjection => projection * viewMatrix;

  /// The inverse of [unjitteredViewProjection]: clip space back to the
  /// scene's space, for a node that reconstructs positions from depth.
  vm.Matrix4 get inverseViewProjection =>
      vm.Matrix4.copy(unjitteredViewProjection)..invert();

  /// The sub-pixel offset the temporal resolve drew this frame's scene with,
  /// in pixels; zero when temporal anti-aliasing is off.
  ({double x, double y}) get jitter {
    final temporal = settings.antiAlias.temporal;
    if (!temporal.enabled) return (x: 0.0, y: 0.0);
    final (x, y) = jitterOffset(frameIndex, temporal.sequenceLength);
    return (x: x, y: y);
  }

  double get _aspect {
    final fraction = view?.viewportFraction;
    final w = width * (fraction?.width ?? 1.0);
    final h = height * (fraction?.height ?? 1.0);
    return h <= 0.0 ? 1.0 : w / h;
  }
}

/// What the renderer hands the passes it runs, and nobody else needs. Not
/// exported by `flutter3d_core.dart`.
extension FrameContextInternals on FrameContext {
  /// Counters the whole frame shares. A node that binds its own pipeline
  /// must say so through [FramePassState.invalidatePipeline], or the next
  /// thing drawn will trust a stale answer.
  FramePassState get state => _state;

  /// Shares [state] with the rest of the frame: the renderer hands every
  /// pass of a frame the one set of counters.
  set state(FramePassState state) => _state = state;
}

/// Everything a node is given to build its pass from: the [FrameContext],
/// and the frame's resources.
///
/// No pass, deliberately — see the note on [RenderNode]. The scene's colour is
/// here instead, because a node that draws over the world needs to read what
/// the world came out as, and that is a resource rather than a pass. What
/// was `NodeFrame` before 1.0.
final class RenderFrame extends FrameContext {
  /// A frame for a node to draw in; the renderer's to make.
  RenderFrame({
    required super.device,
    required this.resources,
    required super.services,
    required super.settings,
    required super.width,
    required super.height,
    super.view,
    super.frameIndex,
    super.time,
    super.origin,
    this.sceneColor,
  });

  /// The textures and buffers behind this frame's declared resources: what
  /// a node reads and writes by the [ResourceId]s it declared.
  ///
  /// Handed in rather than held by the node, which is not a style choice: the
  /// node has to exist before the graph can be compiled, and the resources
  /// cannot exist until it is. A node that stored them could not be built.
  final FrameResources resources;

  /// The HDR target the scene was drawn into, for a node that declared it.
  final TextureHandle? sceneColor;

  /// The unjittered view-projection, as a node drawing into the world needs
  /// it: [projection] times [viewMatrix].
  vm.Matrix4 get viewProjection => unjitteredViewProjection;
}

/// Something that declares what it touches, owns a pass, and draws it — the
/// one kind of pass an application or a plugin adds to a frame, with
/// `RendererSteps.addNode`.
///
/// What it touches is [reads] and [writes] of [ResourceId]s: textures, and
/// since 1.0 buffers too (`FrameResources.provideBuffer` and `buffer`), so a
/// compute pass that fills a buffer a later draw reads is ordered by the
/// graph like any other producer and consumer.
abstract base class RenderNode extends FrameGraphNode {
  /// A node; a subclass declares what it touches.
  const RenderNode();

  /// Draws this node's part of the frame.
  ///
  /// Called only if the graph kept it: a node whose outputs nobody reads is
  /// never asked, which is the difference between an effect that is switched
  /// off and an effect that costs a pass and is then discarded.
  void execute(RenderFrame frame);

  /// Where this node goes when whoever adds it does not say —
  /// `RendererSteps.addNode` without `at`.
  ///
  /// [RenderAnchor.afterScene] for anything that does not know better: the
  /// scene is drawn in HDR and nothing has been tone mapped, which is where
  /// light belongs. A node built for the finished picture — a colour grade,
  /// a vignette, a watermark — says [RenderAnchor.beforePresent] here once,
  /// in its own class, instead of relying on every caller to know. (It was
  /// `preferredPhase` before 1.0.)
  RenderAnchor get defaultAnchor => RenderAnchor.afterScene;
}
