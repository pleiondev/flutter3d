/// A frame-graph node that owns a pass and draws something.
///
/// Split from [FrameGraphNode] so the scheduling half stays free of GPU types:
/// `frame_graph.dart` works out the order, the culling and the lifetimes with
/// no device in sight and thirty-one unit tests to show for it, and this is
/// where that meets a render pass.
///
/// A node **owns** its pass, which is the difference between it and a
/// [PassContributor]. A contributor is handed a pass and draws into it; a node
/// builds its own, so handing it one would be meaningless — and for a while it
/// was worse than meaningless, because the overlay stage was handed the scene's
/// pass after that pass's command buffer had already been submitted.
///
/// That is why [NodeFrame] carries no pass. It is not an omission.
library;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'frame_graph.dart';
import 'frame_resources.dart';
import 'pass_contributor.dart';
import 'renderer.dart';

/// Everything a node is given to build its pass from.
///
/// No pass, deliberately — see the note on [RenderNode]. The scene's colour is
/// here instead, because a node that draws over the world needs to read what
/// the world came out as, and that is a resource rather than a pass.
final class NodeFrame {
  NodeFrame({
    required this.device,
    required this.resources,
    required this.services,
    required this.state,
    required this.settings,
    required this.width,
    required this.height,
    this.sceneColor,
  });

  /// The backend, which is how a node opens the pass it owns.
  ///
  /// Where the pass itself would be if a node were a contributor. It arrives as
  /// a value rather than being reached for, which is what makes a node's
  /// drawing assertable by a test: hand it a recording device and the pass it
  /// built, its attachments and its draws are all readable with no GPU in the
  /// room. See `test/node_encoding_test.dart`.
  final GraphicsDevice device;

  /// The textures behind this frame's declared resources.
  ///
  /// Handed in rather than held by the node, which is not a style choice: the
  /// node has to exist before the graph can be compiled, and the resources
  /// cannot exist until it is. A node that stored them could not be built.
  final FrameResources resources;

  final RenderServices services;

  /// Counters the whole frame shares. A node that binds its own pipeline must
  /// say so through [FramePassState.invalidatePipeline], or the next thing
  /// drawn will trust a stale answer.
  final FramePassState state;

  final RenderSettings settings;

  final int width;
  final int height;

  /// The HDR target the scene was drawn into.
  final TextureHandle? sceneColor;
}

/// Something that declares what it touches, owns a pass, and draws it.
abstract base class RenderNode extends FrameGraphNode {
  const RenderNode();

  /// Draws this node's part of the frame.
  ///
  /// Called only if the graph kept it: a node whose outputs nobody reads is
  /// never asked, which is the difference between an effect that is switched
  /// off and an effect that costs a pass and is then discarded.
  void execute(NodeFrame frame);
}

/// Where in the frame an application's node is registered.
///
/// Not a priority number — the thing the frame graph exists to replace — and
/// not an ordering the graph could derive either. Registration order is what
/// turns a chain of writes to one name into a chain of versions, so *where* a
/// node is registered decides which version it reads, and no declaration a node
/// could make would say that on its own.
///
/// Two positions, because there are two, and each is defined by what has
/// already been drawn when the node runs.
enum FramePhase {
  /// Before the post chain: the scene is drawn, in HDR, and nothing has been
  /// tone mapped.
  ///
  /// Where every application node went before this enum existed, and still the
  /// default. A node here writes light — decals, a held weapon, anything that
  /// belongs to the world and should bloom and tone map with it.
  overlay,

  /// After the composite: the image is tone mapped, sRGB, and is what the
  /// caller is about to be handed.
  ///
  /// Registration here was impossible rather than merely awkward, which is the
  /// gap this closes. Registered in the [overlay] slot, a node declaring
  /// `reads: [frame]` bound to a version the composite had not written yet;
  /// declaring only `writes: [frame]` put it *first*, where the composite then
  /// overwrote it with `LoadAction.dontCare`. So the pass ran, cost its time,
  /// and left nothing — the failure mode that looks exactly like working code.
  ///
  /// A node here reads display-referred colour. Anything physical — a light, a
  /// glow, anything meant to blow out — belongs in [overlay]; this is for
  /// things that are honestly about the finished picture: a colour grade, a
  /// vignette, a letterbox, a watermark.
  present,
}

/// The nodes a renderer runs, and the order it runs them in.
///
/// Ordering *within* a phase is derived by the frame graph from what each node
/// declares, not by a priority number — that is the whole reason the graph
/// exists. What a phase decides is something the graph cannot: which of the
/// engine's own passes have already produced their versions. This holds the
/// set; `Renderer` compiles it.
final class RenderNodeRegistry {
  final List<RenderNode> _nodes = <RenderNode>[];
  final Map<RenderNode, FramePhase> _phases = <RenderNode, FramePhase>{};

  List<RenderNode> get all => List<RenderNode>.unmodifiable(_nodes);

  /// The nodes registered for [phase], in the order they were added.
  List<RenderNode> of(FramePhase phase) => <RenderNode>[
        for (final node in _nodes)
          if ((_phases[node] ?? FramePhase.overlay) == phase) node,
      ];

  int get length => _nodes.length;

  T add<T extends RenderNode>(T node,
      {FramePhase phase = FramePhase.overlay}) {
    _nodes.add(node);
    _phases[node] = phase;
    return node;
  }

  bool remove(RenderNode node) {
    _phases.remove(node);
    return _nodes.remove(node);
  }

  void clear() {
    _phases.clear();
    _nodes.clear();
  }
}
