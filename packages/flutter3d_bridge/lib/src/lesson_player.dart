/// `edu-02`: the same `edu-00` lesson document `edu-06`'s [StereoRig] version
/// plays back (`flutter3d_stereo`'s `applyLessonStep`/`LessonPlayer`), for a
/// flat screen instead of a headset. Lives here rather than in a new package
/// for the reason that file's own docstring names: this is where an
/// `EntityDef` already meets a `SceneNode` — level geometry to mesh nodes,
/// an actor to its visual — and a lesson step naming which of the scene's
/// nodes are visible is the same kind of mapping, just driven by a step
/// instead of a brush.
///
/// **Not a second way to read a step.** `orderedSteps`
/// (`flutter3d_editor_core`'s `lesson_authoring.dart`) already resolves an
/// `edu_sequence.steps` list to the `edu_step` entities themselves; this file
/// only says what a step *means* to a flat scene — where the camera stands,
/// and which named nodes are visible.
///
/// **What this does not do**, by the same honest-scope convention
/// `doc/tooling-plan.md` uses for every `edu-*` entry: no `offsets` (layered
/// teardown — `edu-00` §6), no `edu_clip_plane` rendering (nothing in this
/// tree draws a clip plane yet), no `bindings`/`edu_data_source` (live data —
/// `edu-05` built the data side, no renderer reads it here), no `check`
/// (the quiz question). Each is a real, separate step, not a silently
/// dropped corner.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';

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
