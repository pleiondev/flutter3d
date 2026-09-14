/// `anim-07`'s own live pose binding: whichever clip [AnimationPanel] has
/// open, sampled onto the scene nodes [ModelerStage.sync] tracks.
///
/// Rebuilt only when [ModelProject.clips] or the [SceneSync] it targets
/// change identity, not every frame: an `AnimationPlayer` is a small object,
/// but a fresh one forgets which clip was open and where the playhead was,
/// and a frame is drawn far more often than either of those actually moves.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import 'scene_sync.dart';
import 'timeline_playback.dart';

/// Holds the one [TimelinePlayback] a document's clips are previewed
/// through, and rebuilds it exactly when the project or the scene it targets
/// stop being the ones it was last built against.
class TimelinePreviewWiring {
  TimelinePlayback? _preview;
  List<ProjectClip>? _previewClips;
  SceneSync? _previewSync;

  /// The live preview player for [project]/[sync] — built fresh if either has
  /// changed identity since the last call, reused otherwise. Null when there
  /// is nothing to preview yet (no clips) or nowhere to draw one onto (the
  /// stage has not synced a scene).
  TimelinePlayback? _previewFor(ModelProject project, SceneSync? sync) {
    if (sync == null || project.clips.isEmpty) return null;
    if (!identical(project.clips, _previewClips) ||
        !identical(sync, _previewSync)) {
      _previewClips = project.clips;
      _previewSync = sync;
      _preview = TimelinePlayback(player: buildPreviewPlayer(project, sync));
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
  void scrub(double time) => _preview?.seek(time);

  /// One tick of whatever clip is currently playing.
  void tick(double seconds) => _preview?.tick(seconds);
}
