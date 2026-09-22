/// `edu-02`: the same `edu-00` lesson document `edu-06`'s [StereoRig] version
/// plays back (`flutter3d_stereo`'s `applyLessonStep`/`LessonPlayer`), for a
/// flat screen instead of a headset. It lives in the one application that
/// plays a lesson on a flat screen: it was in `flutter3d_bridge` while that
/// package was where an `EntityDef` met a `SceneNode`, and nothing but this
/// viewer ever called it.
///
/// **Not a second way to read a step.** `orderedSteps`
/// (`flutter3d_editor_core`'s `lesson_authoring.dart`) already resolves an
/// `edu_sequence.steps` list to the `edu_step` entities themselves; this file
/// only says what a step *means* to a flat scene — where the camera stands,
/// and which named nodes are visible.
///
/// **What this does not do**, by the same honest-scope convention
/// `doc/tooling-plan.md` uses for every `edu-*` entry: no `edu_clip_plane`
/// rendering (nothing in this
/// tree draws a clip plane yet), no `bindings`/`edu_data_source` (live data —
/// `edu-05` built the data side, no renderer reads it here), no `check`
/// (the quiz question). Each is a real, separate step, not a silently
/// dropped corner.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// Moves [camera] to [step]'s own position and yaw, and shows or hides
/// whichever of [nodes] the step names in its `visible`/`hidden` lists.
///
/// A name the step does not mention is left exactly as the previous step
/// left it — the same "each step states only what it touches, once, in
/// full" convention `edu-00` §5 sets for the panel that authors these
/// documents, and the same rule `flutter3d_stereo`'s version already applies
/// for a rig's stage.
void applyLessonStepToCamera(
  SceneNode camera,
  EntityDef step, {
  Map<String, SceneNode> nodes = const <String, SceneNode>{},
  Map<String, Vector3> restPositions = const <String, Vector3>{},
}) {
  camera
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

  // **A step's `offsets` is the whole disassembled state, not a diff from the
  // step before.** `edu-00` §5 settles it that way, and the reason is that a
  // viewer can jump: pressing past three steps and back again has to land on
  // the same picture as walking through them, which a per-step delta cannot
  // promise. So every node with a rest position is placed at that rest
  // position plus whatever this step names for it, and a node the step does
  // not name goes home rather than staying where the last step left it.
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

/// One `offsets` entry as a vector, or zero where the document holds
/// something else.
///
/// A lesson is authored by hand and read at run time, so a malformed entry
/// is a node that does not move rather than an exception over one bad entry
/// in an otherwise fine step.
Vector3 _offsetVector(Object? raw) {
  if (raw is! List || raw.length < 3) return Vector3.zero();
  final x = raw[0];
  final y = raw[1];
  final z = raw[2];
  if (x is! num || y is! num || z is! num) return Vector3.zero();
  return Vector3(x.toDouble(), y.toDouble(), z.toDouble());
}

/// Which step of an `edu_sequence` a lesson is on, and the two moves a
/// viewer has: `next`/`previous`, both clamped rather than wrapping — a
/// viewer who clicks past the last step should see the last step held, not
/// the first step returning unannounced.
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

  /// Applies [current] to [camera] and [nodes] — a no-op on an empty lesson,
  /// the same way an empty `edu_sequence` already resolves to no steps in
  /// `orderedSteps` rather than throwing.
  void applyCurrent(
    SceneNode camera, {
    Map<String, SceneNode> nodes = const <String, SceneNode>{},
  }) {
    final step = current;
    if (step != null) applyLessonStepToCamera(camera, step, nodes: nodes);
  }
}
