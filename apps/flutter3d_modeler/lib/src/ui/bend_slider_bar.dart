/// Полоса 74 — `anim-12`'s own bar: a slider that bends one joint by
/// dragging its live [SceneNode], plus "Сбросить позу" back to [Pose.restOf].
///
/// **Why the joint moves outside `ModelHistory`.** `ModelHistory` keeps
/// `ModelCommand`s run against a `ModelProject` — `HistoryStep`, `run`,
/// `transaction`. A joint's [SceneNode] is neither; it is the live scene
/// graph the renderer reads every frame, the same graph `transform_gizmo.dart`
/// and `joint_picking.dart` already work against without ever naming a
/// `ModelCommand`. So there is nothing here to route through `ModelHistory`
/// in the first place: this file never imports it, never calls `.run` or
/// `.amend`, and the undo/redo stacks (`ModelHistory._done`/`_undone`) are
/// untouched by construction — sixty frames of a drag cost nothing on that
/// stack, the same freedom `operation_card.dart`'s own slider gets from
/// `ModelHistory.amend` for a *document* edit, arrived at here by simply
/// never touching the document at all.
///
/// **Why nothing here "bumps" `poseVersion` by hand.** [Skeleton.poseVersion]
/// is not a field — it is a sum of every joint's [SceneNode.worldVersion],
/// recomputed on every read. Calling [SceneNode.setRotation] on [joint]
/// marks its local transform dirty; the next time anything reads
/// [skeleton]'s `poseVersion` — this widget's own degree readout, a
/// renderer, `mesh_node.dart`'s bounds cache — that read is what recomputes
/// the world matrix and folds the change into the sum. [onPoseChanged] is
/// offered purely as a convenience for a caller that wants to know the new
/// number without reading the getter itself; nothing internal depends on it.
///
/// **Why `pose`/`jointIndex` rather than a bare rest [Quaternion].** The
/// acceptance line is explicit: reset goes "через `Pose.restOf`". [Pose] is
/// `anim-01`'s scene-graph-free rest/sample data — the same object
/// `ProjectSkeleton` (`anim-03`) already builds from a document's skins —
/// and [jointIndex] is that pose's own node index for the joint this bar
/// bends. Bending is expressed relative to that same rest orientation, so a
/// slider at 0 always means "exactly at rest" regardless of where in its own
/// hierarchy the joint sits.
library;

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, radians;

import '../../l10n/app_localizations.dart';
import 'theme.dart';

/// One joint's bend control: a label, a slider, a degree readout and a
/// "Сбросить позу" link, 74 logical pixels tall — the row height `Полоса 74`
/// names.
class BendSliderBar extends StatefulWidget {
  const BendSliderBar({
    super.key,
    required this.joint,
    required this.jointIndex,
    required this.pose,
    required this.skeleton,
    this.axis,
    this.minDegrees = -120.0,
    this.maxDegrees = 120.0,
    this.label = 'Bend',
    this.onPoseChanged,
  });

  /// The live joint this bar bends. Rotated directly — never through a
  /// `ModelCommand` — so dragging never touches `ModelHistory`.
  final SceneNode joint;

  /// [joint]'s index into [pose]'s own node arrays — what [Pose.restOf]
  /// and [Pose.localMatrix] index by.
  final int jointIndex;

  /// The rest/reference data [jointIndex] is read against. Never mutated by
  /// this widget: [Pose] itself is scene-graph-free, and only [joint] (a
  /// live [SceneNode]) ever changes here.
  final Pose pose;

  /// The skeleton [joint] belongs to, read only for [Skeleton.poseVersion]
  /// after a change — never mutated directly.
  final Skeleton skeleton;

  /// The hinge axis a bend turns around, in the frame [Pose.restOf]'s own
  /// rotation is composed on top of. Null defaults to the local X axis, the
  /// ordinary hinge for an elbow or a knee — [Vector3] itself is not a
  /// `const` type, so the default lives in the state's own initializer
  /// rather than here.
  final Vector3? axis;

  final double minDegrees;
  final double maxDegrees;

  /// What the bar reads as: `Elbow`, `Knee L`.
  final String label;

  /// Called with [Skeleton.poseVersion] after every change to [joint] —
  /// a convenience for a caller that wants the new stamp without reading
  /// the getter itself; nothing here depends on this being set.
  final ValueChanged<int>? onPoseChanged;

  @override
  State<BendSliderBar> createState() => _BendSliderBarState();
}

class _BendSliderBarState extends State<BendSliderBar> {
  late final Vector3 _axis = widget.axis ?? Vector3(1.0, 0.0, 0.0);

  double _degrees = 0.0;

  /// [widget.joint]'s local rotation at [degrees] of bend: [Pose.restOf]'s
  /// own rotation with an extra turn of [degrees] about [_axis] composed
  /// underneath it, so 0 degrees reproduces the rest orientation exactly and
  /// the axis reads the same regardless of how the rest pose itself is
  /// turned — the same order `SceneNode.lookAt` composes a parent's rotation
  /// on top of a locally-computed one.
  Quaternion _bentRotation(double degrees) {
    final Matrix4 rest = widget.pose.restOf(widget.jointIndex);
    final Quaternion restRotation = Quaternion.fromRotation(rest.getRotation())
      ..normalize();
    return restRotation * Quaternion.axisAngle(_axis, radians(degrees));
  }

  void _drag(double degrees) {
    widget.joint.setRotation(_bentRotation(degrees));
    setState(() => _degrees = degrees);
    widget.onPoseChanged?.call(widget.skeleton.poseVersion);
  }

  void _resetPose() {
    widget.joint.setLocalMatrix(widget.pose.restOf(widget.jointIndex));
    setState(() => _degrees = 0.0);
    widget.onPoseChanged?.call(widget.skeleton.poseVersion);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String shown = '${_degrees.round()}°';
    return SizedBox(
      height: 74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: ModelerMetrics.row - 12,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  shown,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Slider(
              value: _degrees.clamp(widget.minDegrees, widget.maxDegrees),
              min: widget.minDegrees,
              max: widget.maxDegrees,
              onChanged: _drag,
              label: shown,
              semanticFormatterCallback: (double v) =>
                  '${widget.label} ${v.round()} degrees',
            ),
          ),
          SizedBox(
            height: 22,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetPose,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(AppLocalizations.of(context).resetPoseButtonLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
