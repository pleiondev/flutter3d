/// A frame-graph node that actually draws something.
///
/// Split from [FrameGraphNode] so the scheduling half stays free of GPU types:
/// `frame_graph.dart` works out the order, the culling and the lifetimes with
/// no device in sight and twenty-two unit tests to show for it, and this is
/// where that meets a render pass.
///
/// The context is [PluginFrame] rather than something invented for the
/// occasion. It was shaped by two real clients — the particle system and the
/// weapon view model — and an argument list that already survived contact with
/// both is a better starting point than one designed from the outside. The
/// same reasoning kept `CommandEncoder` out of this step: it is in the plan,
/// but abstracting over a command buffer before a second backend exists to
/// check the abstraction against is how a seam ends up in the wrong place.
library;

import 'render_plugin.dart';
import 'frame_graph.dart';

/// Something that declares what it touches and then draws it.
abstract base class RenderNode extends FrameGraphNode {
  const RenderNode();

  /// Draws this node's part of the frame.
  ///
  /// Called only if the graph kept it: a node whose outputs nobody reads is
  /// never asked, which is the difference between an effect that is switched
  /// off and an effect that costs a pass and is then discarded.
  void execute(PluginFrame frame);
}

/// Adapts an existing [RenderPlugin] to a graph node.
///
/// The bridge for the migration rather than a permanent fixture. Everything on
/// the old seam moves across one at a time, and until a thing has moved it can
/// still be scheduled — otherwise the migration is one commit that changes
/// every pass at once, which is the commit where a regression hides.
///
/// [reads] and [writes] have to be supplied here because a plugin never
/// declared them; that is the whole difference between the two, and it is why
/// the adapter cannot be automatic.
final class PluginNode extends RenderNode {
  const PluginNode(
    this.plugin, {
    required this.name,
    this.reads = const <ResourceId>[],
    this.writes = const <ResourceId>[],
  });

  final RenderPlugin plugin;

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> writes;

  @override
  bool get isActive => plugin.isActive;

  @override
  void execute(PluginFrame frame) => plugin.encode(frame);
}
