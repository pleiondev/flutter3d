/// Two views of one document, side by side — `ux-38`.
///
/// **One scene, two cameras, and nothing copied.** `ModelerStage.
/// secondViewOf` adds a camera and an orbit to the stage the shell already
/// draws; everything else — the scene graph, the `SceneSync` keeping it in
/// step, the material pool — is the same object. So an edit shows in both
/// views on the frame the document emits, and neither view can drift from
/// the other because there is nothing for them to drift between.
///
/// **`multi_split_view` rather than a `Row` and a drag handle.** The handle
/// is the easy half; what that package has that a hand-rolled one does not
/// is a divider a keyboard can reach, weights that survive a rebuild, and
/// minimum sizes that hold while a window is being resized rather than only
/// while it is being dragged. It is pure Dart over `Flex`, so the web build
/// gets exactly what the desktop one does — which is the half of this row's
/// acceptance that tear-off cannot satisfy.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:multi_split_view/multi_split_view.dart';

import '../modeler_viewport.dart';
import '../staging.dart';

/// The smallest either view may be dragged to, in logical pixels — below
/// this a viewport is a stripe nobody can judge a model in.
const double kViewportSmallest = 160;

/// The document, drawn twice.
class SplitViewports extends StatefulWidget {
  const SplitViewports({
    super.key,
    required this.renderer,
    required this.stage,
    required this.primary,
    required this.split,
    required this.onSplit,
  });

  final Renderer renderer;

  /// The stage the first view already draws — the second is built from it.
  final ModelerStage stage;

  /// The shell's own viewport widget, whatever it has been configured with:
  /// gizmos, the grid, picking, the overlay. The second view deliberately
  /// gets none of that — see [_second].
  final Widget primary;

  /// Where the divide sits, as the first view's own share.
  final double split;

  /// The divide was dragged. Reported rather than kept, so the layout the
  /// settings file holds and the layout on screen are one number.
  final ValueChanged<double> onSplit;

  @override
  State<SplitViewports> createState() => _SplitViewportsState();
}

class _SplitViewportsState extends State<SplitViewports> {
  late final ModelerStage _other = ModelerStage.secondViewOf(widget.stage);
  late final MultiSplitViewController _controller = MultiSplitViewController(
    areas: <Area>[
      Area(flex: widget.split, min: kViewportSmallest, builder: _left),
      Area(flex: 1 - widget.split, min: kViewportSmallest, builder: _right),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _left(BuildContext context, Area area) => widget.primary;

  /// **No gizmo, no grid, no picking.** A second view is for looking from
  /// somewhere else while working in the first one; two views that both
  /// answered a click would leave "which one is the selection in" as a
  /// question a person has to hold in their head.
  Widget _right(BuildContext context, Area area) => ModelerViewport(
    key: const ValueKey<String>('secondViewport'),
    renderer: widget.renderer,
    stage: _other,
    onFrame: () {},
    grid: null,
    overlay: false,
  );

  void _dragged() {
    final List<Area> areas = _controller.areas;
    if (areas.length != 2) return;
    final double first = areas[0].flex ?? 1;
    final double second = areas[1].flex ?? 1;
    final double total = first + second;
    if (total <= 0) return;
    widget.onSplit((first / total).clamp(0.15, 0.85));
  }

  @override
  Widget build(BuildContext context) => MultiSplitView(
    controller: _controller,
    onDividerDragEnd: (_) => _dragged(),
    axis: Axis.horizontal,
  );
}
