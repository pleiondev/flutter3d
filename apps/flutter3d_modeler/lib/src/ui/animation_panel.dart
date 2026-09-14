/// `anim-07`'s own screen: [ActionsList] to pick a clip, and — for the held
/// object's own skeleton, when it has one — [SkeletonTree] and
/// [ConstraintsList].
///
/// **A stateless pass-through, as of `S2`.** This panel used to keep the
/// clip/track/key selection and the scrub position as its own local state,
/// with the reasoning that none of it belongs on [ModelHistory] — undoing a
/// click that only changed what a person was looking at would be a step of
/// "undo" that visibly does nothing. That reasoning still holds; only where
/// the state lives changed. `S2` moved [TimelinePanel] out of this panel and
/// into `ModelerShell.bottom` (`ui-41d`'s own slot) so the transport bar and
/// the curve editor beside it can share the same playhead and clip — a
/// widget the panel had no way to reach while it was the only thing holding
/// which clip was open. What was `_selectedClip`/`_selectedTrack`/
/// `_selectedKey`/`_selectedJoint`/`_selectedConstraint` on this class's own
/// `State` are now `_ModelerScreenState`'s own fields instead, the same
/// "one screen, one place selection lives" this application already keeps
/// [pivot]/[space]/[selectedLight] in.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;

import 'actions_list.dart';
import 'constraints_list.dart';
import 'skeleton_tree.dart';

class AnimationPanel extends StatelessWidget {
  const AnimationPanel({
    super.key,
    required this.clips,
    required this.objects,
    this.skeleton,
    required this.onAddClip,
    this.selectedClip,
    required this.onSelectClip,
    this.selectedJoint,
    required this.onSelectJoint,
    this.selectedConstraint,
    required this.onSelectConstraint,
    this.onRemoveConstraint,
  });

  /// The project's own actions — [ModelProject.clips].
  final List<ProjectClip> clips;

  /// Every object in the project, for [SkeletonTree]'s own joint names and
  /// this panel's own [ConstraintsList] labels.
  final List<ModelObject> objects;

  /// The held object's own skeleton, or null when it has none —
  /// [ModelObject.skeletonIndex] into [ModelProject.skeletons], resolved by
  /// the caller since this panel has no [ModelProject] of its own to index.
  final ProjectSkeleton? skeleton;

  /// "Add" was pressed under the action list — [AddClip], `anim-04`'s own
  /// row.
  final VoidCallback onAddClip;

  /// Which clip is open — the caller's own selection, so the timeline in
  /// `ModelerShell.bottom` and this panel's own action list always agree on
  /// it.
  final int? selectedClip;
  final ValueChanged<int> onSelectClip;

  final int? selectedJoint;
  final ValueChanged<int> onSelectJoint;

  final int? selectedConstraint;
  final ValueChanged<int> onSelectConstraint;
  final ValueChanged<int>? onRemoveConstraint;

  String _jointName(int jointId) {
    for (final object in objects) {
      if (object.id == jointId) return object.name;
    }
    return 'joint $jointId';
  }

  @override
  Widget build(BuildContext context) {
    final ProjectSkeleton? skeleton = this.skeleton;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel('Actions'),
        ActionsList(
          clips: clips,
          selectedClip: selectedClip,
          onSelectClip: onSelectClip,
          onAddClip: onAddClip,
        ),
        if (skeleton != null) ...<Widget>[
          const SizedBox(height: 6),
          SectionLabel('Skeleton'),
          SkeletonTree(
            objects: objects,
            skeleton: skeleton,
            selectedJoint: selectedJoint,
            onSelectJoint: onSelectJoint,
          ),
          const SizedBox(height: 6),
          SectionLabel('Constraints'),
          ConstraintsList(
            constraints: skeleton.constraints,
            nameOf: _jointName,
            selected: selectedConstraint,
            onSelect: onSelectConstraint,
            onRemove: onRemoveConstraint,
          ),
        ],
      ],
    );
  }
}
