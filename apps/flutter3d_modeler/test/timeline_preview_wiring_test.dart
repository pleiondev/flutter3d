/// `anim-07`'s own live pose binding: rebuilt only when the project's clips
/// or the scene they target change identity, not every frame.
///
///     flutter test test/timeline_preview_wiring_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/timeline_preview_wiring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/fake_graphics_backend.dart';

/// One cube, with a clip translating it from the origin to (1, 0, 0) over a
/// second.
({ModelProject project, ModelerStage stage, int objectId}) rigged() {
  final it = fakeTestDevice(width: 8, height: 8);
  var project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  final objectId = project.objects.single.id;
  project = project.copyWith(
    clips: <ProjectClip>[
      ProjectClip(
        name: 'walk',
        tracks: <ProjectTrack>[
          ProjectTrack(
            objectId: objectId,
            track: AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.translation,
              interpolation: AnimationInterpolation.linear,
              times: Float32List.fromList(<double>[0.0, 1.0]),
              values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
              componentCount: 3,
            ),
          ),
        ],
      ),
    ],
  );
  final stage = ModelerStage.fromProject(device: it.device, project: project);
  return (project: project, stage: stage, objectId: objectId);
}

void main() {
  test('selecting a clip with nothing to preview is a no-op', () {
    final wiring = TimelinePreviewWiring();
    const empty = ModelProject();

    // Neither a null sync nor an empty-clip project has anything to build a
    // player against — both must fall through without throwing.
    wiring.selectClip(empty, null, 0);
    wiring.scrub(empty, null, 0.5);
    wiring.tick(empty, null, 0.1);
  });

  test('selecting a clip plays it to its first pose, paused', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    final node = rig.stage.sync!.nodeOf(rig.objectId)!;

    wiring.selectClip(rig.project, rig.stage.sync, 0);

    // Mutation: leave the clip playing instead of pausing it. Selecting a
    // clip is meant to show its first pose, not start it running before
    // anyone has touched the scrubber.
    expect(node.localMatrix.getTranslation(), Vector3.zero());
  });

  test('scrubbing applies the pose straight onto the live scene', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    final node = rig.stage.sync!.nodeOf(rig.objectId)!;

    wiring.selectClip(rig.project, rig.stage.sync, 0);
    wiring.scrub(rig.project, rig.stage.sync, 1.0);

    expect(node.localMatrix.getTranslation().x, closeTo(1.0, 1e-6));
  });

  test('selecting null stops the preview and returns the rest pose', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    final node = rig.stage.sync!.nodeOf(rig.objectId)!;

    wiring.selectClip(rig.project, rig.stage.sync, 0);
    wiring.scrub(rig.project, rig.stage.sync, 1.0);
    wiring.selectClip(rig.project, rig.stage.sync, null);

    expect(node.localMatrix.getTranslation(), Vector3.zero());
  });

  test('a scrub after an edit changed project.clips keeps the playhead — '
      'the rebuild trap', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    final node = rig.stage.sync!.nodeOf(rig.objectId)!;

    wiring.selectClip(rig.project, rig.stage.sync, 0);
    wiring.scrub(rig.project, rig.stage.sync, 0.5);

    // A `copyWith` with the identical clip list content — the shape a
    // command like `Rename` or an edit to an *unrelated* track leaves
    // behind, `List.of` under the hood giving `clips` a new identity
    // without changing what is in it.
    final edited = rig.project.copyWith(
      clips: List<ProjectClip>.of(rig.project.clips),
    );

    // Mutation: rebuild the player from scratch here and forget the old
    // one's own time — the playhead would silently jump back to frame 0,
    // which a person mid-scrub would read as a bug, not a rebuild.
    wiring.tick(edited, rig.stage.sync, 0.0);

    expect(node.localMatrix.getTranslation().x, closeTo(0.5, 1e-6));
  });

  test('the coarse playback getter answers "nothing yet" before a clip is '
      'ever selected', () {
    final wiring = TimelinePreviewWiring();

    expect(wiring.playback.isPlaying, isFalse);
    expect(wiring.playback.clipIndex, -1);
  });

  test('togglePlay starts a paused preview and pauses a playing one', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    wiring.selectClip(rig.project, rig.stage.sync, 0);

    wiring.togglePlay();
    expect(wiring.playback.isPlaying, isTrue);

    wiring.togglePlay();
    expect(wiring.playback.isPlaying, isFalse);
  });

  test('setLooping toggles between loop and once', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    wiring.selectClip(rig.project, rig.stage.sync, 0);

    wiring.setLooping(false);
    expect(wiring.playback.wrap, AnimationWrap.once);

    wiring.setLooping(true);
    expect(wiring.playback.wrap, AnimationWrap.loop);
  });

  test('setSpeed changes the coarse playback\'s own speed', () {
    final rig = rigged();
    final wiring = TimelinePreviewWiring();
    wiring.selectClip(rig.project, rig.stage.sync, 0);

    wiring.setSpeed(2.0);

    expect(wiring.playback.speed, 2.0);
  });
}
