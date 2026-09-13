/// `anim-07`'s own screen: [ActionsList] to pick a clip, [TimelinePanel] to
/// scrub and drag its keys, and — for the held object's own skeleton, when
/// it has one — [SkeletonTree] and [ConstraintsList].
///
/// **Selection and the scrub position are this widget's own state, not the
/// project's.** Which clip is open, which track or joint is highlighted and
/// where the playhead sits are exactly the facts [ModelHistory] must never
/// carry — undoing a click that only changed what a person was looking at
/// would be a step of "undo" that visibly does nothing. [onMoveKeys] and
/// [onAddClip] are the only two things this panel ever asks a caller to run
/// as a real command.
///
/// **Not built here: a live pose.** Nothing in this application yet
/// evaluates a sampled clip back onto the scene nodes a `ModelInstance`
/// holds — `anim-08`'s own skeleton overlay draws the rest pose, not a
/// played one. Wiring an `AnimationPlayer` to the viewport so scrubbing this
/// timeline moves the mesh on screen is real, separate work this row's own
/// acceptance does not ask for: `MoveKeys` reaching history and the
/// `modeler-timeline` golden are both already true of [TimelinePanel] on
/// its own, and this file's job is only to give the four widgets `anim-07`
/// names a screen to share.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;

import 'actions_list.dart';
import 'constraints_list.dart';
import 'section_label.dart';
import 'skeleton_tree.dart';
import 'timeline_panel.dart';

class AnimationPanel extends StatefulWidget {
  const AnimationPanel({
    super.key,
    required this.clips,
    required this.objects,
    this.skeleton,
    required this.onMoveKeys,
    required this.onAddClip,
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

  /// A drag on a diamond ended — [TimelinePanel.onMoveKeys]'s own callback,
  /// passed straight through to whichever history a caller keeps.
  final ValueChanged<MoveKeys> onMoveKeys;

  /// "Add" was pressed under the action list — [AddClip], `anim-04`'s own
  /// row.
  final VoidCallback onAddClip;

  @override
  State<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends State<AnimationPanel> {
  int? _selectedClip;
  int? _selectedTrack;
  int? _selectedKey;
  int? _selectedJoint;
  int? _selectedConstraint;
  double _time = 0.0;

  @override
  void didUpdateWidget(covariant AnimationPanel old) {
    super.didUpdateWidget(old);
    // A clip [AddClip] appended, or one removed from further up the
    // history, can leave a stale index behind — clamped rather than left to
    // throw the next time [build] indexes [widget.clips] with it.
    if (_selectedClip != null && _selectedClip! >= widget.clips.length) {
      _selectedClip = null;
      _selectedTrack = null;
      _selectedKey = null;
    }
  }

  void _selectClip(int index) => setState(() {
    _selectedClip = index;
    _selectedTrack = null;
    _selectedKey = null;
    _time = 0.0;
  });

  String _jointName(int jointId) {
    for (final object in widget.objects) {
      if (object.id == jointId) return object.name;
    }
    return 'joint $jointId';
  }

  @override
  Widget build(BuildContext context) {
    final int? clipIndex = _selectedClip;
    final ProjectClip? clip =
        clipIndex != null && clipIndex < widget.clips.length
        ? widget.clips[clipIndex]
        : null;
    final ProjectSkeleton? skeleton = widget.skeleton;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel('Actions'),
        ActionsList(
          clips: widget.clips,
          selectedClip: _selectedClip,
          onSelectClip: _selectClip,
          onAddClip: widget.onAddClip,
        ),
        if (clip != null) ...<Widget>[
          const SizedBox(height: 6),
          SectionLabel('Timeline'),
          SizedBox(
            height: 180,
            child: TimelinePanel(
              clipIndex: clipIndex!,
              clip: clip,
              time: _time,
              selectedTrack: _selectedTrack,
              selectedKey: _selectedKey,
              onMoveKeys: widget.onMoveKeys,
              onSeek: (double t) => setState(() => _time = t),
              onSelectKey: (int track, int key) => setState(() {
                _selectedTrack = track;
                _selectedKey = key;
              }),
            ),
          ),
        ],
        if (skeleton != null) ...<Widget>[
          const SizedBox(height: 6),
          SectionLabel('Skeleton'),
          SkeletonTree(
            objects: widget.objects,
            skeleton: skeleton,
            selectedJoint: _selectedJoint,
            onSelectJoint: (int id) => setState(() => _selectedJoint = id),
          ),
          const SizedBox(height: 6),
          SectionLabel('Constraints'),
          ConstraintsList(
            constraints: skeleton.constraints,
            nameOf: _jointName,
            selected: _selectedConstraint,
            onSelect: (int index) =>
                setState(() => _selectedConstraint = index),
          ),
        ],
      ],
    );
  }
}
