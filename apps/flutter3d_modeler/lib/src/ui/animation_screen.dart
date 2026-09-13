/// `anim-07`'s own screen 07: composing `ActionsList`, `SkeletonTree`,
/// `ConstraintsList` and `TimelinePanel` around the 3D view — the four
/// widgets the plan's own row names, each already built and tested on its
/// own (`actions_list_test.dart`, `skeleton_tree_test.dart`,
/// `constraints_list_test.dart`, `timeline_panel_test.dart`), put together
/// the way `UvScreen`/`LodScreen` already compose their own rows' widgets.
///
/// **The viewport is handed in, not built here** — the same reason
/// `UvScreen`'s own doc comment gives: a real one needs a `Renderer` and a
/// `ModelerStage` this screen has no business owning, so a caller wires the
/// real 3D view exactly as it does for every other screen and this widget's
/// own job stops at composing screens.
///
/// **What is not here.** `AnimationPlayer` running on a live instance, and
/// `playback`/the current frame living in a `Cubit`/`State` rather than
/// being handed in as plain data — both still `anim-07`'s own row, not
/// built yet. A caller wiring this screen into the running app supplies
/// [time] and [onSeek] from wherever that state ends up living; this
/// screen does not assume where that is, the same way `UvScreen` does not
/// assume where its own `method`/`margin` state lives.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'actions_list.dart';
import 'constraints_list.dart';
import 'skeleton_tree.dart';
import 'theme.dart';
import 'timeline_panel.dart';

/// Screen 07: the 3D view on the left; clips, the skeleton and its
/// constraints on the right; the timeline along the bottom.
final class AnimationScreen extends StatelessWidget {
  const AnimationScreen({
    super.key,
    required this.viewport,
    required this.objects,
    required this.clips,
    this.selectedClip,
    required this.onSelectClip,
    required this.onAddClip,
    required this.skeleton,
    this.selectedJoint,
    required this.onSelectJoint,
    required this.constraints,
    this.selectedConstraint,
    required this.onSelectConstraint,
    this.onRemoveConstraint,
    required this.clipIndex,
    required this.clip,
    required this.time,
    this.selectedTrack,
    this.selectedKey,
    this.onMoveKeys,
    this.onSeek,
    this.onSelectKey,
  });

  /// The 3D view, already wired with the mesh and skeleton this screen is
  /// animating — whatever this app calls its own `RenderView`, today
  /// `ModelerViewport`. Handed in rather than built here; see this file's
  /// own doc comment.
  final Widget viewport;

  /// Read only for [SkeletonTree]'s and [ConstraintsList]'s own joint-name
  /// lookups, the same reason [SkeletonTree.objects] takes a plain list
  /// rather than a whole [ModelProject].
  final List<ModelObject> objects;

  final List<ProjectClip> clips;
  final int? selectedClip;
  final ValueChanged<int> onSelectClip;
  final VoidCallback onAddClip;

  final ProjectSkeleton skeleton;
  final int? selectedJoint;
  final ValueChanged<int> onSelectJoint;

  final List<IkConstraint> constraints;
  final int? selectedConstraint;
  final ValueChanged<int> onSelectConstraint;
  final ValueChanged<int>? onRemoveConstraint;

  final int clipIndex;
  final ProjectClip clip;
  final double time;
  final int? selectedTrack;
  final int? selectedKey;
  final ValueChanged<MoveKeys>? onMoveKeys;
  final ValueChanged<double>? onSeek;
  final void Function(int trackIndex, int keyIndex)? onSelectKey;

  String _jointName(int jointId) {
    for (final object in objects) {
      if (object.id == jointId) return object.name;
    }
    return 'joint $jointId';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelEdge =
        theme.extension<ModelerColors>()?.panelEdge ?? theme.dividerColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: viewport),
              Container(width: 1, color: panelEdge),
              SizedBox(
                width: ModelerMetrics.propertiesMax,
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 120,
                      child: ActionsList(
                        clips: clips,
                        selectedClip: selectedClip,
                        onSelectClip: onSelectClip,
                        onAddClip: onAddClip,
                      ),
                    ),
                    Container(height: 1, color: panelEdge),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SkeletonTree(
                          objects: objects,
                          skeleton: skeleton,
                          selectedJoint: selectedJoint,
                          onSelectJoint: onSelectJoint,
                        ),
                      ),
                    ),
                    Container(height: 1, color: panelEdge),
                    Expanded(
                      child: SingleChildScrollView(
                        child: ConstraintsList(
                          constraints: constraints,
                          nameOf: _jointName,
                          selected: selectedConstraint,
                          onSelect: onSelectConstraint,
                          onRemove: onRemoveConstraint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: panelEdge),
        SizedBox(
          height: 200,
          child: TimelinePanel(
            clipIndex: clipIndex,
            clip: clip,
            time: time,
            selectedTrack: selectedTrack,
            selectedKey: selectedKey,
            onMoveKeys: onMoveKeys,
            onSeek: onSeek,
            onSelectKey: onSelectKey,
          ),
        ),
      ],
    );
  }
}
