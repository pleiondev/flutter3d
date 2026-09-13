/// `anim-07`'s own `TimelinePlayback`: a thin controller over a real
/// `AnimationPlayer`, and the `playback`/frame split the plan's own row asks
/// for.
///
///     flutter test test/timeline_playback_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One clip, one second long at 30fps, translating node 0 from the origin to
/// (1, 0, 0).
AnimationClip _walk() => AnimationClip(
  name: 'walk',
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
      componentCount: 3,
    ),
  ],
);

({AnimationPlayer player, SceneNode target}) _rig() {
  final target = SceneNode(name: 'root');
  final player = AnimationPlayer(
    clips: <AnimationClip>[_walk()],
    targets: <SceneNode?>[target],
  );
  return (player: player, target: target);
}

void main() {
  test('play starts the clip and reports a coarse playback change', () {
    final rig = _rig();
    final changes = <Playback>[];
    final playback = TimelinePlayback(
      player: rig.player,
      onPlaybackChanged: changes.add,
    );

    playback.play(0);

    expect(playback.playback.isPlaying, isTrue);
    expect(playback.playback.clipIndex, 0);
    expect(changes, <Playback>[
      const Playback(status: PlaybackStatus.playing, clipIndex: 0),
    ]);
  });

  test('tick advances the real player and fires the frame hook once a '
      'whole frame has passed', () {
    final rig = _rig();
    final frames = <int>[];
    final playback = TimelinePlayback(
      player: rig.player,
      fps: 30.0,
      onFrameChanged: frames.add,
    )..play(0);
    frames.clear(); // Drop play()'s own initial frame-0 notification.

    // One thirtieth of a second is exactly one frame at 30fps.
    playback.tick(1 / 30);

    expect(playback.frame, 1);
    expect(frames, <int>[1]);
  });

  test(
    'tick is a no-op while paused: the underlying player never advances',
    () {
      final rig = _rig();
      final playback = TimelinePlayback(player: rig.player, fps: 30.0)..play(0);
      playback.pause();
      final timeBefore = rig.player.time;

      playback.tick(0.5);

      // Mutation: call `player.update` regardless of `_playback.status`.
      expect(rig.player.time, timeBefore);
    },
  );

  test('pause reports a coarse change without moving the frame', () {
    final rig = _rig();
    final changes = <Playback>[];
    final playback = TimelinePlayback(
      player: rig.player,
      onPlaybackChanged: changes.add,
    )..play(0);
    changes.clear();

    playback.pause();

    expect(playback.playback.status, PlaybackStatus.paused);
    expect(changes, <Playback>[
      const Playback(status: PlaybackStatus.paused, clipIndex: 0),
    ]);
  });

  test('stop rewinds to frame 0 and reports both hooks', () {
    final rig = _rig();
    final frames = <int>[];
    final playback = TimelinePlayback(
      player: rig.player,
      fps: 30.0,
      onFrameChanged: frames.add,
    )..play(0);
    playback.tick(0.5);
    frames.clear();

    playback.stop();

    expect(playback.playback.status, PlaybackStatus.stopped);
    expect(playback.frame, 0);
    expect(frames, <int>[0]);
  });

  test('seekFrame lands on the same time KeyTable.timeOfFrame would', () {
    final rig = _rig();
    final playback = TimelinePlayback(player: rig.player, fps: 30.0)..play(0);

    playback.seekFrame(15);

    expect(playback.time, closeTo(0.5, 1e-9));
    expect(playback.frame, 15);
  });

  test('setSpeed changes the player\'s own speed and reports it', () {
    final rig = _rig();
    final changes = <Playback>[];
    final playback = TimelinePlayback(
      player: rig.player,
      onPlaybackChanged: changes.add,
    );

    playback.setSpeed(2.0);

    expect(rig.player.speed, 2.0);
    expect(changes.single.speed, 2.0);
  });

  test('a clip that finishes once-wrapped reports itself stopped', () {
    final rig = _rig();
    rig.player.wrap = AnimationWrap.once;
    final changes = <Playback>[];
    final playback = TimelinePlayback(
      player: rig.player,
      onPlaybackChanged: changes.add,
    )..play(0);
    changes.clear();

    playback.tick(10.0); // Far past the clip's own 1-second duration.

    expect(playback.playback.status, PlaybackStatus.stopped);
    expect(changes.last.status, PlaybackStatus.stopped);
  });

  test('the target actually moved: this is driving the real AnimationPlayer, '
      'not a double', () {
    final rig = _rig();
    final playback = TimelinePlayback(player: rig.player, fps: 30.0)..play(0);

    playback.seek(1.0);

    expect(rig.target.readWorldPosition().x, closeTo(1.0, 1e-6));
  });

  group('buildPreviewPlayer — anim-07\'s own scene wiring', () {
    /// A project of one cube, with a clip that walks it from the origin to
    /// (1, 0, 0) over a second, keyed by the cube's own object id rather
    /// than by a node index — [ProjectClip]'s own addressing.
    (ModelProject, int cubeId) walkingCube() {
      var project = const ModelProject();
      late int id;
      project = project.added((int i) {
        id = i;
        return ModelObject(
          id: i,
          name: 'cube',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        );
      });
      project = project.copyWith(
        clips: <ProjectClip>[
          ProjectClip(
            name: 'walk',
            tracks: <ProjectTrack>[
              ProjectTrack(
                objectId: id,
                track: AnimationTrack(
                  nodeIndex: 0, // Unread — see ProjectTrack's own doc comment.
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
      return (project, id);
    }

    test(
      'the real scene node the project\'s own cube got moves, not a copy',
      () {
        final (project, cubeId) = walkingCube();
        final it = cpuTestDevice(width: 8, height: 8);
        final stage = ModelerStage.fromProject(
          device: it.device,
          project: project,
        );
        final sync = stage.sync!;

        final playback = TimelinePlayback(
          player: buildPreviewPlayer(project, sync),
        )..play(0);
        playback.seek(1.0);

        expect(sync.nodeOf(cubeId)!.readWorldPosition().x, closeTo(1.0, 1e-6));
      },
    );

    test('an object with no clip is simply not among the targets', () {
      final it = cpuTestDevice(width: 8, height: 8);
      final project = const ModelProject().added(
        (int i) => ModelObject(
          id: i,
          name: 'bystander',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final stage = ModelerStage.fromProject(
        device: it.device,
        project: project,
      );

      final player = buildPreviewPlayer(project, stage.sync!);

      expect(player.clips, isEmpty);
      expect(player.targets, isEmpty);
    });
  });
}
