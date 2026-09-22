/// `anim-07`'s own `AnimationPlayer` wiring: a small, pure controller class
/// around one already-built [AnimationPlayer] — one per posed instance, the
/// same way a [Skeleton] is one per instance rather than one per asset — with
/// its own [Playback] state value type, ready for a `Cubit` to adopt without
/// redesign.
///
/// **`playback` in a `Cubit`, the frame in `State` — the plan's own split,
/// kept here rather than glossed over.** [onPlaybackChanged] fires only when
/// something coarse moves — play, pause, stop, which clip, the speed — the
/// handful of transitions a `Cubit`'s own `emit` is built for.
/// [onFrameChanged] fires on every frame the playhead crosses, which is
/// `fps` times a second while playing: too often for a `Cubit`'s own
/// listeners to rebuild a whole screen over, and exactly the granularity a
/// `State.setState` repainting one playhead line is built for.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'scene_sync.dart';

/// The coarse half of a timeline's own transport — what a `Cubit` would hold
/// as `playback`.
enum PlaybackStatus {
  stopped,
  playing,
  paused;

  bool get isPlaying => this == playing;
}

/// A playback snapshot: immutable, value-equal, and small enough that a
/// `Cubit` comparing two of them is comparing three fields, not two whole
/// `AnimationPlayer`s.
@immutable
final class Playback {
  const Playback({
    this.status = PlaybackStatus.stopped,
    this.clipIndex = -1,
    this.speed = 1.0,
    this.wrap = AnimationWrap.loop,
  });

  final PlaybackStatus status;

  /// [AnimationPlayer.clipIndex] as of the last change this class made —
  /// `-1` before anything has ever played, the same "nothing selected yet"
  /// [AnimationPlayer.clipIndex] itself starts at.
  final int clipIndex;

  final double speed;

  /// [AnimationPlayer.wrap] as of the last change this class made — `S2`'s
  /// own row, [TimelinePlayback.setWrap]'s coarse half. Defaults to
  /// [AnimationWrap.loop], the same default [AnimationPlayer.wrap] itself
  /// starts at, so a `Playback` built before anyone has touched the loop
  /// toggle already agrees with the player it describes.
  final AnimationWrap wrap;

  bool get isPlaying => status.isPlaying;

  Playback copyWith({
    PlaybackStatus? status,
    int? clipIndex,
    double? speed,
    AnimationWrap? wrap,
  }) => Playback(
    status: status ?? this.status,
    clipIndex: clipIndex ?? this.clipIndex,
    speed: speed ?? this.speed,
    wrap: wrap ?? this.wrap,
  );

  @override
  bool operator ==(Object other) =>
      other is Playback &&
      other.status == status &&
      other.clipIndex == clipIndex &&
      other.speed == speed &&
      other.wrap == wrap;

  @override
  int get hashCode => Object.hash(status, clipIndex, speed, wrap);

  @override
  String toString() => 'Playback($status, clip $clipIndex, ${speed}x, $wrap)';
}

/// An [AnimationPlayer] over [project]'s own clips, targeting the live scene
/// [sync] tracks — the same [ProjectTrack.objectId] → node remap
/// `ProjectModelDocument.toModelDocument` already does for an export, done
/// here against [SceneSync.nodeOf] instead of a fresh [ModelNode] list.
///
/// **One player for every clip, not one per clip**, because
/// [AnimationPlayer.targets] is shared across whichever of [AnimationPlayer.clips]
/// is playing — the same reason [AnimationPanel.onSelectClip] hands this
/// class a clip *index* rather than asking for a new player each time.
///
/// A target is null wherever [SceneSync] has not built a node for that
/// object — closed over a socket, say, or a track outliving the object it
/// named — and [AnimationPlayer] already skips a null target on its own.
AnimationPlayer buildPreviewPlayer(ModelProject project, SceneSync sync) {
  final ids = <int>{
    for (final ProjectClip clip in project.clips)
      for (final ProjectTrack track in clip.tracks) track.objectId,
  }.toList(growable: false);
  final indexOfId = <int, int>{for (var i = 0; i < ids.length; i++) ids[i]: i};

  return AnimationPlayer(
    clips: <AnimationClip>[
      for (final ProjectClip clip in project.clips)
        AnimationClip(
          name: clip.name,
          extras: clip.extras,
          tracks: <AnimationTrack>[
            for (final ProjectTrack track in clip.tracks)
              AnimationTrack(
                nodeIndex: indexOfId[track.objectId]!,
                path: track.track.path,
                interpolation: track.track.interpolation,
                times: track.track.times,
                values: track.track.values,
                componentCount: track.track.componentCount,
              ),
          ],
        ),
    ],
    targets: <AnimationTarget?>[for (final int id in ids) sync.nodeOf(id)],
  );
}

/// Drives one [AnimationPlayer] — play, pause, seek, and a per-frame tick a
/// `Ticker` (or a test) calls — and reports the two granularities of change
/// [Playback]'s own class comment describes.
final class TimelinePlayback {
  TimelinePlayback({
    required this.player,
    this.fps = 30.0,
    this.onPlaybackChanged,
    this.onFrameChanged,
  });

  final AnimationPlayer player;

  /// Frames a second — [KeyTable.timeOfFrame]/[KeyTable.frameOfTime]'s own
  /// `fps`, so a frame number this class reports lands on the identical
  /// frame a [KeyTable]-backed command would key.
  final double fps;

  final ValueChanged<Playback>? onPlaybackChanged;
  final ValueChanged<int>? onFrameChanged;

  Playback _playback = const Playback();

  Playback get playback => _playback;

  /// The playhead, in whole frames at [fps] — [KeyTable.frameOfTime] applied
  /// to [AnimationPlayer.time].
  int get frame => KeyTable.frameOfTime(player.time, fps);

  double get time => player.time;

  /// Starts [clipIndex], or resumes the current clip when it is null —
  /// [AnimationPlayer.play]'s own contract, carried through unchanged.
  void play([int? clipIndex]) {
    player.play(clipIndex);
    _setPlayback(
      _playback.copyWith(
        status: PlaybackStatus.playing,
        clipIndex: player.clipIndex,
      ),
    );
    _notifyFrame();
  }

  void pause() {
    player.pause();
    _setPlayback(_playback.copyWith(status: PlaybackStatus.paused));
  }

  /// Stops and rewinds — [AnimationPlayer.stop]'s own "leaves the first pose
  /// applied", so the frame hook fires too: a rewind moves the playhead.
  void stop() {
    player.stop();
    _setPlayback(_playback.copyWith(status: PlaybackStatus.stopped));
    _notifyFrame();
  }

  void seek(double seconds) {
    player.seek(seconds);
    _notifyFrame();
  }

  /// [seek], at a frame number rather than a time — [KeyTable.timeOfFrame]
  /// applied before handing it to [AnimationPlayer.seek].
  void seekFrame(int targetFrame) =>
      seek(KeyTable.timeOfFrame(targetFrame, fps));

  void setSpeed(double speed) {
    player.speed = speed;
    _setPlayback(_playback.copyWith(speed: speed));
  }

  /// Sets [AnimationPlayer.wrap] — the loop toggle's own transport control —
  /// and folds it into the coarse [playback] the same way [setSpeed] does
  /// for the speed control beside it.
  void setWrap(AnimationWrap wrap) {
    player.wrap = wrap;
    _setPlayback(_playback.copyWith(wrap: wrap));
  }

  /// [AnimationPlayer.crossFadeTo], reported through the same coarse/frame
  /// split every other transition on this class uses — a transport's own
  /// "switch action" is a play, not a seek, so both hooks fire the way
  /// [play] itself makes them.
  void crossFadeTo(int index, {double duration = 0.15}) {
    player.crossFadeTo(index, duration: duration);
    _setPlayback(
      _playback.copyWith(
        status: PlaybackStatus.playing,
        clipIndex: player.clipIndex,
      ),
    );
    _notifyFrame();
  }

  /// Advances by [deltaSeconds] while playing; a no-op otherwise, so a
  /// `Ticker` can call this every frame regardless of whether playback is
  /// actually running.
  void tick(double deltaSeconds) {
    if (!_playback.isPlaying) return;
    final before = frame;
    player.update(deltaSeconds);
    if (!player.isPlaying) {
      _setPlayback(_playback.copyWith(status: PlaybackStatus.stopped));
    }
    if (frame != before) _notifyFrame();
  }

  void _notifyFrame() => onFrameChanged?.call(frame);

  void _setPlayback(Playback next) {
    if (next == _playback) return;
    _playback = next;
    onPlaybackChanged?.call(next);
  }
}
