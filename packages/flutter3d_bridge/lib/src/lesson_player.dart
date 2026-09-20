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
/// `doc/tooling-plan.md` uses for every `edu-*` entry: no `edu_clip_plane`
/// rendering. **Investigated 2026-09-15, not just repeated:** the shader
/// authoring itself is smaller than "every backend" suggests — one GLSL
/// source compiles to Impeller, translates to WebGL and to WGSL for WebGPU
/// (`flutter3d_shaders`'s own "one copy" skill), and `flutter3d_cpu`'s
/// hand-transcribed Dart is the only second copy that would need writing by
/// hand, the same shape `fog`/`camera_position` already take through
/// `renderer_mesh_encode.dart`'s shared `FragInfo` block. What actually
/// blocks it is not code volume: a uniform-layout mismatch between what a
/// shader declares and what a backend's own reflection expects is a
/// documented, undebuggable failure mode on Impeller specifically
/// ("`SIGSEGV` inside the driver with no Dart stack trace" —
/// `flutter3d_shaders`'s own skill file), and this environment has no GPU to
/// catch that at runtime before it ships — `impellerc`/`naga` can confirm a
/// shader compiles, not that binding it is safe. A real, separate step,
/// needing real hardware, not a silently dropped corner.
///
/// `offsets` (layered teardown — `edu-00` §6) is done: [applyLessonStepToCamera]'s
/// `restPositions` parameter. `check` (§10's quiz question) is done too, but
/// not here: `apps/flutter3d_lesson_viewer/lib/src/check_prompt.dart` reads
/// a step's own `check` property directly — a step's UI dressing, not a
/// second way to place a node, so it never needed this file at all.
/// `bindings`/`edu_data_source` (§9's live data) is done here, too:
/// [applyLessonStepBindings] is the write half of `edu-05`'s own
/// `resolveBindings` — that function only ever answered "what value", never
/// "written where", by its own doc comment's design.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

/// Moves [camera] to [step]'s own position and yaw, shows or hides whichever
/// of [nodes] the step names in its `visible`/`hidden` lists, and places
/// every node in [restPositions] at its rest position plus whatever offset
/// [step] names for it — `edu-00` §6's layered teardown.
///
/// A name the step does not mention in `visible`/`hidden` is left exactly as
/// the previous step left it — the same "each step states only what it
/// touches, once, in full" convention `edu-00` §5 sets for the panel that
/// authors these documents, and the same rule `flutter3d_stereo`'s version
/// already applies for a rig's stage.
///
/// **`offsets` is the one exception to that rule, by `edu-00` §5's own
/// design, not an inconsistency introduced here.** A step's `offsets` is
/// read as the *whole* disassembled state of the model, not a diff from the
/// step before: "каждый шаг несёт полное состояние того, что он трогает...
/// не «плюс к предыдущему»" (`doc/edu-00-interactive-format.md` §5). So this
/// function sets every node named in [restPositions] on every call — a node
/// with no entry in this step's own `offsets` goes back to its rest
/// position, exactly as `doc/edu-00-interactive-format.md` §6 says a node
/// "without a record in offsets" already stands: "узел... без записи в
/// offsets стоит там, где стоит в самой модели."
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

/// Parses one `offsets` entry the same way [EntityDef.vector] parses a
/// top-level property — a JSON `[x, y, z]` — but `offsets`'s own values sit
/// under a nested key rather than directly on the entity, so `EntityDef`'s
/// own parser (which only reads its own flat [EntityDef.properties]) does
/// not reach them. Missing or malformed reads as no offset, the same as
/// `edu-00` §6 already treats "no record in offsets" — never a thrown
/// format error over one bad entry in an otherwise fine step.
Vector3 _offsetVector(Object? raw) {
  if (raw is! List || raw.length < 3) return Vector3.zero();
  final x = raw[0];
  final y = raw[1];
  final z = raw[2];
  if (x is! num || y is! num || z is! num) return Vector3.zero();
  return Vector3(x.toDouble(), y.toDouble(), z.toDouble());
}

/// Writes every binding [step] resolves through [sources] at [atStep] into
/// [nodes] — `edu-00` §9's own two target shapes, `"entity.at"`/`"entity.yaw"`
/// for a transform and `"entity.material.<field>"` for a material, the same
/// `сущность.путь-свойства` the format itself names ("для свойства
/// материала это материал.поле, для трансформа — at/yaw"). A target naming
/// a node this document has none for, or a material field this function
/// does not know how to write, is skipped rather than thrown — a content
/// typo should not stop the rest of the step's bindings from landing, the
/// same choice [applyLessonStepToCamera]'s own `offsets` parsing already
/// makes for one bad entry.
void applyLessonStepBindings(
  EntityDef step,
  int atStep,
  DataSourceRegistry sources, {
  Map<String, SceneNode> nodes = const <String, SceneNode>{},
}) {
  final resolved = resolveBindings(step, atStep, sources);
  for (final entry in resolved.entries) {
    final dot = entry.key.indexOf('.');
    if (dot < 0) continue;
    final node = nodes[entry.key.substring(0, dot)];
    if (node == null) continue;
    _writeBindingTarget(node, entry.key.substring(dot + 1), entry.value);
  }
}

void _writeBindingTarget(SceneNode node, String property, Object? value) {
  switch (property) {
    case 'at':
      final vector = _numericVector(value);
      if (vector != null) node.setPositionFrom(vector);
    case 'yaw':
      final yaw = _asDouble(value);
      if (yaw != null) {
        node.setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw));
      }
    case 'material.emissiveColor':
      if (node case MeshNode(:final material)) {
        final vector = _numericVector(value);
        if (vector != null) material.emissive.setFrom(vector);
      }
    case 'material.baseColor':
      if (node case MeshNode(:final material)) {
        final rgb = _numericVector(value);
        if (rgb != null) {
          material.baseColor.setValues(
            rgb.x,
            rgb.y,
            rgb.z,
            material.baseColor.a,
          );
        }
      }
    case 'material.emissiveStrength':
      if (node case MeshNode(:final material)) {
        final strength = _asDouble(value);
        if (strength != null) material.emissiveStrength = strength;
      }
    case 'material.roughness':
      if (node case MeshNode(:final material)) {
        final roughness = _asDouble(value);
        if (roughness != null) material.roughness = roughness;
      }
    case 'material.metallic':
      if (node case MeshNode(:final material)) {
        final metallic = _asDouble(value);
        if (metallic != null) material.metallic = metallic;
      }
  }
}

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

/// A binding's own value read as a 3-vector — a `[r, g, b]`/`[x, y, z]` list,
/// the same shape `offsets`'s own values already carry, since a live data
/// source's payload is arbitrary JSON and this is the one shape both a
/// colour and a position can honestly share.
Vector3? _numericVector(Object? value) {
  if (value is! List || value.length < 3) return null;
  final x = value[0];
  final y = value[1];
  final z = value[2];
  if (x is! num || y is! num || z is! num) return null;
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
    Map<String, Vector3> restPositions = const <String, Vector3>{},
  }) {
    final step = current;
    if (step != null) {
      applyLessonStepToCamera(
        camera,
        step,
        nodes: nodes,
        restPositions: restPositions,
      );
    }
  }
}
