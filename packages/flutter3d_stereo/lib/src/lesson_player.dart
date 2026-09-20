/// `edu-06`: the same `edu-00` lesson document a step panel authors
/// (`edu_sequence`/`edu_step`, `packages/flutter3d_editor_core/lib/src/
/// lesson_authoring.dart`'s `orderedSteps`), played back through a
/// [StereoRig] instead of edited through one.
///
/// **Nothing here is a second way to read a step.** `orderedSteps` already
/// resolves `edu_sequence.steps` to the `edu_step` entities themselves; this
/// file only says what a step *means* to a rig — where the stage stands, and
/// which of the scene's named nodes are visible — the way `flutter3d_bridge`
/// says what an entity means to a mesh. Advancing between steps is a button,
/// not a keystroke or a scroll: `wg-01` found both of those unreachable
/// inside a `WidgetSurface`, and a phone in a Cardboard holder has no
/// keyboard to reach for regardless.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'stereo_rig.dart';

/// Moves [rig]'s stage to [step]'s own `at`/`yaw`, shows or hides whichever
/// of [nodes] the step names in its `visible`/`hidden` lists, and places
/// every node in [restPositions] at its rest position plus whatever offset
/// [step] names for it — `edu-00` §6's layered teardown, the same mechanic
/// `flutter3d_bridge`'s own `applyLessonStepToCamera` plays back for a flat
/// screen. Duplicated rather than shared, on purpose: this file's own doc
/// comment already draws the line — a rig's stage is a different rendering
/// primitive from a flat camera, and the two files exist precisely so
/// neither has to know about the other's renderer.
///
/// A name step does not mention is left exactly as the previous step left
/// it — the same "each step states only what it touches, once, in full"
/// convention `edu-00` §5 already sets for the panel that authors these
/// documents; a lesson step that had to repeat every unrelated node's
/// visibility every time would drift out of sync with the model the moment
/// somebody added a part.
///
/// **`offsets` is the one exception to that rule, by `edu-00` §5's own
/// design.** A step's `offsets` is read as the *whole* disassembled state
/// of the model, not a diff from the step before — see
/// `flutter3d_bridge`'s own `applyLessonStepToCamera` doc comment for the
/// full reasoning, identical here.
void applyLessonStep(
  StereoRig rig,
  EntityDef step, {
  Map<String, SceneNode> nodes = const <String, SceneNode>{},
  Map<String, Vector3> restPositions = const <String, Vector3>{},
}) {
  rig.stage
    ..setPositionFrom(step.position)
    ..setRotationYawPitchRoll(step.yaw, 0.0, 0.0);

  void showEach(Object? raw, bool visible) {
    if (raw is! List) return;
    for (final name in raw) {
      if (name is String) nodes[name]?.visible = visible;
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

/// Parses one `offsets` entry — a JSON `[x, y, z]` under a nested key, the
/// same shape `flutter3d_bridge`'s own `_offsetVector` reads for the flat
/// player. Missing or malformed reads as no offset, never a thrown format
/// error over one bad entry in an otherwise fine step.
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
/// wrapping — a Cardboard viewer who presses past the last step should see
/// the last step held, not the first step returning unannounced.
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

  /// Applies [current] to [rig], [nodes] and [restPositions] — a no-op on
  /// an empty lesson, the same way an empty `edu_sequence` already resolves
  /// to no steps in `orderedSteps` rather than throwing.
  void applyCurrent(
    StereoRig rig, {
    Map<String, SceneNode> nodes = const <String, SceneNode>{},
    Map<String, Vector3> restPositions = const <String, Vector3>{},
  }) {
    final step = current;
    if (step != null) {
      applyLessonStep(rig, step, nodes: nodes, restPositions: restPositions);
    }
  }
}
