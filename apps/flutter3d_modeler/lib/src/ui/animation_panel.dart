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
/// **The live pose is reported, not applied, here.** [onSelectClip] and
/// [onTimeChanged] fire alongside this panel's own local selection and
/// scrub state, so a caller holding the real scene — `main.dart`'s own
/// `TimelinePlayback` — can sample the clip onto it. This widget still has
/// no `ModelProject` and no scene of its own to apply a pose to; it only
/// ever names which clip and which moment. `anim-08`'s own skeleton overlay
/// still draws the rest pose regardless — a played pose moving the mesh and
/// an overlay drawn over it are two different screens' worth of work.
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
    this.onSelectClip,
    this.onTimeChanged,
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

  /// Which clip is open changed — including to null, when a clip closes or
  /// the selection is clamped out from under it — so a caller previewing a
  /// pose knows to stop.
  final ValueChanged<int?>? onSelectClip;

  /// The scrub position moved, in seconds into the open clip. Never fires
  /// with no clip open, the same way [TimelinePanel] itself only exists then.
  final ValueChanged<double>? onTimeChanged;

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
      widget.onSelectClip?.call(null);
    }
  }

  void _selectClip(int index) {
    setState(() {
      _selectedClip = index;
      _selectedTrack = null;
      _selectedKey = null;
      _time = 0.0;
    });
    widget.onSelectClip?.call(index);
  }

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
              onSeek: (double t) {
                setState(() => _time = t);
                widget.onTimeChanged?.call(t);
              },
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
