/// `S2`'s own `ModelerShell.bottom` content for the animation mode's pose
/// sub-mode — the transport bar above, and, the `Keys`/`Curves` toggle's own
/// choice, [TimelinePanel] or [CurveEditor] below.
///
/// **The playhead is read through a `ValueListenable`, not a plain field.**
/// [frame] ticks at up to sixty a second while a clip plays; wrapping only
/// the two widgets that actually draw it in their own
/// [ValueListenableBuilder] is what keeps a running clip from rebuilding the
/// component chips, the loop toggle or the speed menu sixty times a second
/// for a number none of them show.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;

import '../timeline_playback.dart';
import 'curve_editor.dart';
import 'theme.dart';
import 'timeline_panel.dart';
import 'transport_bar.dart';

class AnimationBottom extends StatelessWidget {
  const AnimationBottom({
    super.key,
    this.clipIndex,
    this.clip,
    required this.frame,
    required this.fps,
    required this.playback,
    required this.editMode,
    required this.onEditMode,
    required this.onPlayPause,
    this.onLoopChanged,
    this.onSpeedChanged,
    this.selectedTrack,
    this.selectedKey,
    this.onMoveKeys,
    this.onSeek,
    this.onSelectKey,
    this.onSetKey,
    this.onSetKeyValue,
    this.onSetTangent,
  });

  /// Null when nothing is selected yet — [AnimationBottom] still reserves
  /// its own 270-tall slot in that state (a fixed-height region that never
  /// pops the viewport when a clip is picked), but draws the transport bar
  /// alone over a placeholder in place of [TimelinePanel]/[CurveEditor].
  final int? clipIndex;
  final ProjectClip? clip;

  /// The playhead, in whole frames — see this file's own class comment for
  /// why this is a `ValueListenable` rather than a plain `int`.
  final ValueListenable<int> frame;

  final double fps;

  final Playback playback;
  final TimelineEditMode editMode;
  final ValueChanged<TimelineEditMode> onEditMode;
  final VoidCallback onPlayPause;

  /// The loop toggle — null disables it rather than guessing at a wrap mode
  /// nobody wired.
  final ValueChanged<bool>? onLoopChanged;
  final ValueChanged<double>? onSpeedChanged;

  final int? selectedTrack;
  final int? selectedKey;

  final ValueChanged<MoveKeys>? onMoveKeys;
  final ValueChanged<double>? onSeek;
  final void Function(int trackIndex, int keyIndex)? onSelectKey;

  /// [TimelinePanel.onSetKey]'s own tap-to-key, forwarded straight through —
  /// a caller turns `(trackIndex, time)` into the real `PoseJoint` through
  /// `animation_wiring.dart`'s own `poseJointForSetKey`.
  final void Function(int trackIndex, double time)? onSetKey;

  /// [CurveEditor.onSetKey] — a key dragged vertically in `Curves` mode.
  final ValueChanged<SetKey>? onSetKeyValue;
  final ValueChanged<SetTangent>? onSetTangent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelEdge =
        theme.extension<ModelerColors>()?.panelEdge ?? theme.dividerColor;
    final int? openClipIndex = clipIndex;
    final ProjectClip? openClip = clip;
    final int? trackIndex = selectedTrack;
    final ProjectTrack? track =
        openClip != null &&
            trackIndex != null &&
            trackIndex >= 0 &&
            trackIndex < openClip.tracks.length
        ? openClip.tracks[trackIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: ModelerMetrics.transport,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ValueListenableBuilder<int>(
              valueListenable: frame,
              builder: (BuildContext context, int frameValue, Widget? _) =>
                  TransportBar(
                    playback: playback,
                    frame: frameValue,
                    editMode: editMode,
                    onPlayPause: onPlayPause,
                    onEditMode: onEditMode,
                    onLoopChanged: onLoopChanged,
                    onSpeedChanged: onSpeedChanged,
                  ),
            ),
          ),
        ),
        Container(height: 1, color: panelEdge),
        Expanded(
          child: _timelineOrCurves(openClipIndex, openClip, track, trackIndex),
        ),
      ],
    );
  }

  /// The `Keys`/`Curves` toggle's own choice, or a placeholder for whichever
  /// of the two has nothing to show yet — no open clip for [TimelinePanel],
  /// no selected track for [CurveEditor].
  Widget _timelineOrCurves(
    int? openClipIndex,
    ProjectClip? openClip,
    ProjectTrack? track,
    int? trackIndex,
  ) {
    if (openClipIndex == null || openClip == null) {
      return const Center(
        child: Text('Select or add an action to see its timeline'),
      );
    }
    if (editMode == TimelineEditMode.keys) {
      return ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (BuildContext context, int frameValue, Widget? _) =>
            TimelinePanel(
              clipIndex: openClipIndex,
              clip: openClip,
              time: KeyTable.timeOfFrame(frameValue, fps),
              fps: fps,
              labelWidth: 180,
              selectedTrack: selectedTrack,
              selectedKey: selectedKey,
              onMoveKeys: onMoveKeys,
              onSeek: onSeek,
              onSelectKey: onSelectKey,
              onSetKey: onSetKey,
            ),
      );
    }
    if (track == null || trackIndex == null) {
      return const Center(
        child: Text('Select a track in Keys mode to see its curve'),
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: frame,
      builder: (BuildContext context, int frameValue, Widget? _) => CurveEditor(
        clipIndex: openClipIndex,
        trackIndex: trackIndex,
        track: track.track,
        selectedKeyIndex: selectedKey,
        currentTime: KeyTable.timeOfFrame(frameValue, fps),
        onSelectKey: (int keyIndex) => onSelectKey?.call(trackIndex, keyIndex),
        onSetKey: onSetKeyValue,
        onSetTangent: onSetTangent,
      ),
    );
  }
}
