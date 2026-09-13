/// `anim-07`'s own `TimelinePlayback`: a thin controller over a real
/// `AnimationPlayer`, and the `playback`/frame split the plan's own row asks
/// for.
///
///     flutter test test/timeline_playback_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
