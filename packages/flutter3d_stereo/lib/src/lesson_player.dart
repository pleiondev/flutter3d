/// `edu-06`: the `edu-00` lesson document a step panel authors
/// (`edu_sequence`/`edu_step`, read in order by `flutter3d_education`'s
/// `orderedSteps`), played back: through a [StereoRig]'s stage in a holder,
/// or through a camera on a flat screen.
///
/// **One player for both.** A step says where the viewer stands and which
/// named nodes are visible; whether the node that stands there is a rig's
/// stage or a flat camera changes nothing in what the step means, so the
/// flat lesson viewer and the stereo one play a lesson through this file.
/// Advancing between steps is a button, not a keystroke or a scroll:
/// `wg-01` found both of those unreachable inside a `WidgetSurface`, and a
/// phone in a Cardboard holder has no keyboard to reach for regardless.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'stereo_rig.dart';

/// Moves [viewer] — a flat screen's camera, or a rig's stage — to [step]'s
/// own `at`/`yaw`, shows or hides whichever of [nodes] the step names in
/// its `visible`/`hidden` lists, and places every node in [restPositions]
/// at its rest position plus whatever offset [step] names for it: `edu-00`
/// §6's layered teardown.
///
/// A name a step does not mention is left exactly as the previous step left
/// it — the same "each step states only what it touches, once, in full"
/// convention `edu-00` §5 already sets for the panel that authors these
/// documents; a lesson step that had to repeat every unrelated node's
/// visibility every time would drift out of sync with the model the moment
/// somebody added a part.
///
/// **`offsets` is the one exception to that rule, by `edu-00` §5's own
/// design.** A step's `offsets` is the whole disassembled state, not a diff
/// from the step before, because a viewer can jump: pressing past three
/// steps and back again has to land on the same picture as walking through
/// them, which a per-step delta cannot promise. So every node with a rest
/// position is placed at that rest position plus whatever this step names
/// for it, and a node the step does not name goes home.
void applyLessonStepTo(
  SceneNode viewer,
  EntityDef step, {
  Map<String, SceneNode> nodes = const <String, SceneNode>{},
  Map<String, Vector3> restPositions = const <String, Vector3>{},
}) {
  viewer
    ..setPositionFrom(step.position)
    ..setRotationYawPitchRoll(step.yaw, 0.0, 0.0);

  void showEach(Object? raw, bool visible) {
    if (raw is! List) return;
    for (final name in raw) {
      if (name is String) nodes[name]?.isVisible = visible;
    }
  }

  showEach(step.properties['visible'], true);
  showEach(step.properties['hidden'], false);

  if (restPositions.isNotEmpty) {
    final rawOffsets = step.properties['offsets'];
    final offsets = rawOffsets is Map ? rawOffsets : const <String, Object?>{};
    for (final entry in restPositions.entries) {
      final node = nodes[entry.key];
      if (node == null) continue;
      final offset = _offsetVector(offsets[entry.key]);
      final rest = entry.value;
      node.setPosition(rest.x + offset.x, rest.y + offset.y, rest.z + offset.z);
    }
  }
}

/// [applyLessonStepTo] with [rig]'s stage as the viewer.
void applyLessonStep(
  StereoRig rig,
  EntityDef step, {
  Map<String, SceneNode> nodes = const <String, SceneNode>{},
  Map<String, Vector3> restPositions = const <String, Vector3>{},
}) => applyLessonStepTo(
  rig.stage,
  step,
  nodes: nodes,
  restPositions: restPositions,
);

/// Parses one `offsets` entry, a JSON `[x, y, z]`. Missing or malformed
/// reads as no offset: a lesson is authored by hand and read at run time, so
/// one bad entry in an otherwise fine step is a node that does not move, not
/// a thrown format error.
Vector3 _offsetVector(Object? raw) {
  if (raw is! List || raw.length < 3) return Vector3.zero();
  final x = raw[0];
  final y = raw[1];
  final z = raw[2];
  if (x is! num || y is! num || z is! num) return Vector3.zero();
  return Vector3(x.toDouble(), y.toDouble(), z.toDouble());
}

/// Which step of an `edu_sequence` a lesson is on, and the two moves a
/// button gives a viewer: `next`/`previous`, both clamped rather than
/// wrapping — a viewer who presses past the last step should see the last
/// step held, not the first step returning unannounced.
final class LessonPlayer {
  LessonPlayer(this.steps, {int start = 0})
    : index = steps.isEmpty ? 0 : start.clamp(0, steps.length - 1);

  final List<EntityDef> steps;
  int index;

  EntityDef? get current => steps.isEmpty ? null : steps[index];

  bool get isFirst => index <= 0;
  bool get isLast => steps.isEmpty || index >= steps.length - 1;

  void next() {
    if (!isLast) index++;
  }

  void previous() {
    if (!isFirst) index--;
  }

  /// Applies [current] to [viewer], [nodes] and [restPositions] — a no-op
  /// on an empty lesson, the same way an empty `edu_sequence` already
  /// resolves to no steps in `orderedSteps` rather than throwing.
  void applyCurrentTo(
    SceneNode viewer, {
    Map<String, SceneNode> nodes = const <String, SceneNode>{},
    Map<String, Vector3> restPositions = const <String, Vector3>{},
  }) {
    final step = current;
    if (step != null) {
      applyLessonStepTo(
        viewer,
        step,
        nodes: nodes,
        restPositions: restPositions,
      );
    }
  }

  /// [applyCurrentTo] with [rig]'s stage as the viewer.
  void applyCurrent(
    StereoRig rig, {
    Map<String, SceneNode> nodes = const <String, SceneNode>{},
    Map<String, Vector3> restPositions = const <String, Vector3>{},
  }) => applyCurrentTo(rig.stage, nodes: nodes, restPositions: restPositions);
}
