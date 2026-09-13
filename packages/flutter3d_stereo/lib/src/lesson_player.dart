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

import 'stereo_rig.dart';

/// Moves [rig]'s stage to [step]'s own `at`/`yaw`, and shows or hides
/// whichever of [nodes] the step names in its `visible`/`hidden` lists.
///
/// A name step does not mention is left exactly as the previous step left
/// it — the same "each step states only what it touches, once, in full"
/// convention `edu-00` §5 already sets for the panel that authors these
/// documents; a lesson step that had to repeat every unrelated node's
/// visibility every time would drift out of sync with the model the moment
/// somebody added a part.
void applyLessonStep(
  StereoRig rig,
  EntityDef step, {
  Map<String, SceneNode> nodes = const <String, SceneNode>{},
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

  /// Applies [current] to [rig] and [nodes] — a no-op on an empty lesson,
  /// the same way an empty `edu_sequence` already resolves to no steps in
  /// `orderedSteps` rather than throwing.
  void applyCurrent(StereoRig rig, {Map<String, SceneNode> nodes = const <String, SceneNode>{}}) {
    final step = current;
    if (step != null) applyLessonStep(rig, step, nodes: nodes);
  }
}
