/// `anim-07`'s own live pose binding: whichever clip [AnimationPanel] has
/// open, sampled onto the scene nodes [ModelerStage.sync] tracks.
///
/// Rebuilt only when [ModelProject.clips] or the [SceneSync] it targets
/// change identity, not every frame: an `AnimationPlayer` is a small object,
/// but a fresh one forgets which clip was open and where the playhead was,
/// and a frame is drawn far more often than either of those actually moves.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter3d/flutter3d.dart' show AnimationWrap;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import 'scene_sync.dart';
import 'timeline_playback.dart';

/// Holds the one [TimelinePlayback] a document's clips are previewed
/// through, and rebuilds it exactly when the project or the scene it targets
/// stop being the ones it was last built against.
class TimelinePreviewWiring {
  TimelinePreviewWiring({this.onPlaybackChanged, this.onFrameChanged});

  /// `S2`'s own coarse half — [ModelerCubit.playback]'s own row, fired once
  /// per play/pause/clip/speed/loop change and never per frame. Forwarded
  /// straight through to whichever [TimelinePlayback] this wiring is holding
  /// at the time, fresh one included — see [_previewFor]'s own note on why a
  /// rebuilt player still carries it.
  final ValueChanged<Playback>? onPlaybackChanged;

  /// `S2`'s own fine half — a `ValueNotifier<int>` in `_ModelerScreenState`'s
  /// own row, fired every frame the playhead crosses. Kept off
  /// [onPlaybackChanged] on purpose: a `Cubit`'s `emit` this often would
  /// repaint the whole shell sixty times a second for a number only the
  /// transport bar and the timeline's own playhead read.
  final ValueChanged<int>? onFrameChanged;

  TimelinePlayback? _preview;
  List<ProjectClip>? _previewClips;
  SceneSync? _previewSync;

  /// The live preview player for [project]/[sync] — built fresh if either has
  /// changed identity since the last call, reused otherwise. Null when there
  /// is nothing to preview yet (no clips) or nowhere to draw one onto (the
  /// stage has not synced a scene).
  ///
  /// **A fresh player still carries the old one's own time, clip and wrap.**
  /// `project.clips` changes identity on every edit that touches an
  /// animation — a key dragged, a clip renamed — not only when a whole clip
  /// is added or removed, so this runs far more often than "the document
  /// this preview describes actually changed", and a person mid-scrub whose
  /// playhead snapped back to frame 0 because they nudged a keyframe would
  /// call that a bug, not a rebuild. [buildPreviewPlayer] itself has no way
  /// to carry this across — it is handed a fresh [AnimationPlayer] with
  /// nothing played yet — so this restores the three fields by hand once the
  /// new one exists, through the same [TimelinePlayback] calls a person
  /// pressing play or dragging the scrubber would have made.
  TimelinePlayback? _previewFor(ModelProject project, SceneSync? sync) {
    if (sync == null || project.clips.isEmpty) return null;
    if (!identical(project.clips, _previewClips) ||
        !identical(sync, _previewSync)) {
      final TimelinePlayback? was = _preview;
      _previewClips = project.clips;
      _previewSync = sync;
      _preview = TimelinePlayback(
        player: buildPreviewPlayer(project, sync),
        fps: project.profile.fps,
        onPlaybackChanged: onPlaybackChanged,
        onFrameChanged: onFrameChanged,
      );
      final int savedClip = was?.playback.clipIndex ?? -1;
      if (was != null && savedClip >= 0 && savedClip < project.clips.length) {
        _preview!.player.wrap = was.player.wrap;
        _preview!.play(savedClip);
        if (!was.playback.isPlaying) _preview!.pause();
        _preview!.seek(was.time);
      }
    }
    return _preview;
  }

  /// `AnimationPanel.onSelectClip`: shows [index]'s first pose, paused —
  /// scrubbing is what plays it, not a transport this panel does not have —
  /// or the rest pose again once nothing is selected. A no-op when there is
  /// nothing to preview yet.
  void selectClip(ModelProject project, SceneSync? sync, int? index) {
    final TimelinePlayback? preview = _previewFor(project, sync);
    if (preview == null) return;
    if (index == null) {
      preview.stop();
    } else {
      preview.play(index);
      preview.pause();
    }
  }

  /// `AnimationPanel.onTimeChanged`: the scrubber moved, so the pose it names
  /// is applied straight onto the live scene — no `setState` here, because
  /// `SceneNode.setPosition` and its neighbours are mutations the next tick's
  /// own repaint already picks up, the same way dragging the orbit camera
  /// does.
  ///
  /// **Through [_previewFor], not [_preview] directly** — `S2`'s own row:
  /// a drag that landed a `MoveKeys`/`SetKey` on the open clip a moment ago
  /// changed `project.clips`' own identity, and a scrub reading a player
  /// built before that would show the pose the track had *before* the drag,
  /// not the one it has now.
  void scrub(ModelProject project, SceneSync? sync, double time) =>
      _previewFor(project, sync)?.seek(time);

  /// The transport bar's own play/pause button, toggling whatever clip is
  /// already open — starting clip 0 when nothing has been selected yet, the
  /// same "nothing selected" fallback [AnimationPlayer.play] itself answers
  /// with. A no-op when there is nothing to preview.
  void togglePlay() {
    final TimelinePlayback? preview = _preview;
    if (preview == null) return;
    if (preview.playback.isPlaying) {
      preview.pause();
    } else {
      preview.play();
    }
  }

  /// The loop toggle: [AnimationWrap.loop] on, [AnimationWrap.once] off.
  void setLooping(bool looping) =>
      _preview?.setWrap(looping ? AnimationWrap.loop : AnimationWrap.once);

  /// The speed control.
  void setSpeed(double speed) => _preview?.setSpeed(speed);

  /// `S7`'s own row: the retarget screen's blend slider — crossfades the
  /// preview onto clip [index] over [duration] seconds, through
  /// [TimelinePlayback.crossFadeTo]. A no-op when there is nothing to
  /// preview yet, the same guard every other method here already gives its
  /// own [_preview]/[_previewFor] call.
  void crossFadeTo(
    ModelProject project,
    SceneSync? sync,
    int index, {
    double duration = 0.15,
  }) => _previewFor(project, sync)?.crossFadeTo(index, duration: duration);

  /// One tick of whatever clip is currently playing — through [_previewFor]
  /// for the same reason [scrub] is: called every frame, so a rebuild the
  /// instant `project.clips` moves under a playing clip is what keeps a
  /// live edit visible in the preview rather than frozen at whatever the
  /// track looked like when the player was last built.
  void tick(ModelProject project, SceneSync? sync, double seconds) =>
      _previewFor(project, sync)?.tick(seconds);

  /// The current coarse playback state, for whatever built this wiring to
  /// hand a freshly-opened `ModelerReady` before any real change has fired
  /// [onPlaybackChanged] yet.
  Playback get playback => _preview?.playback ?? const Playback();
}
