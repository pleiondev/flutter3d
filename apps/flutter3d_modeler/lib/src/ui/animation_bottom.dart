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
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../../l10n/app_localizations.dart';
import '../timeline_playback.dart';
import 'curve_editor.dart';
import 'theme.dart';
import 'timeline_panel.dart';
import 'transport_bar.dart';

/// The animation mode's bottom strip: a [TransportBar] on top and, below
/// it, the open clip's keys or the selected track's curves, as [editMode]
/// says. Holds no state; every edit is reported through a callback.
class AnimationBottom extends StatelessWidget {
  /// A strip for the clip at [clipIndex], or for no clip when both it and
  /// [clip] are null.
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
    this.selectedKeys = const <(int, int)>{},
    this.frameSnap = false,
    this.pixelsPerSecond = 120.0,
    this.onZoom,
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

  /// The clip at [clipIndex] in the project, or null alongside it.
  final ProjectClip? clip;

  /// The playhead, in whole frames — see this file's own class comment for
  /// why this is a `ValueListenable` rather than a plain `int`.
  final ValueListenable<int> frame;

  /// The clip's frame rate, in frames per second: what turns [frame] into a
  /// time in seconds for the timeline and the curves.
  final double fps;

  /// Whether the clip is playing, and its loop and speed, as the transport
  /// bar shows them.
  final Playback playback;

  /// Whether the lower half shows keys ([TimelinePanel]) or curves
  /// ([CurveEditor]).
  final TimelineEditMode editMode;

  /// Called when the `Keys`/`Curves` toggle is flipped.
  final ValueChanged<TimelineEditMode> onEditMode;

  /// Called by the play/pause button.
  final VoidCallback onPlayPause;

  /// The loop toggle — null disables it rather than guessing at a wrap mode
  /// nobody wired.
  final ValueChanged<bool>? onLoopChanged;

  /// Called with the speed picked from the transport bar's menu, a
  /// multiplier of the clip's own rate. Null disables the menu.
  final ValueChanged<double>? onSpeedChanged;

  /// The index of the selected track in [clip], or null. The curves view
  /// draws only this track and shows a placeholder while it is null.
  final int? selectedTrack;

  /// The index of the selected key within [selectedTrack], or null.
  final int? selectedKey;

  /// Called when keys are dragged along the timeline; moving them is the
  /// caller's.
  final ValueChanged<MoveKeys>? onMoveKeys;

  /// Called with a time in seconds when the timeline's ruler is scrubbed.
  final ValueChanged<double>? onSeek;

  /// `ux-46`: [add] is shift, "and this one too" rather than "instead".
  final void Function(int trackIndex, int keyIndex, {bool add})? onSelectKey;

  /// `ux-46`'s own three, handed straight to `TimelinePanel` — see that
  /// widget for what each is and why it is reported rather than kept.
  final Set<(int, int)> selectedKeys;

  /// Whether a dragged key snaps to whole frames.
  final bool frameSnap;

  /// The timeline's horizontal zoom: how many logical pixels one second of
  /// the clip takes.
  final double pixelsPerSecond;

  /// Called with a new [pixelsPerSecond] when the timeline is zoomed.
  final ValueChanged<double>? onZoom;

  /// [TimelinePanel.onSetKey]'s own tap-to-key, forwarded straight through —
  /// a caller turns `(trackIndex, time)` into the real `PoseJoint` through
  /// `animation_wiring.dart`'s own `poseJointForSetKey`.
  final void Function(int trackIndex, double time)? onSetKey;

  /// [CurveEditor.onSetKey] — a key dragged vertically in `Curves` mode.
  final ValueChanged<SetKey>? onSetKeyValue;

  /// [CurveEditor.onSetTangent] — a key's tangent handle dragged in
  /// `Curves` mode.
  final ValueChanged<SetTangent>? onSetTangent;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
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
          child: _timelineOrCurves(
            l,
            openClipIndex,
            openClip,
            track,
            trackIndex,
          ),
        ),
      ],
    );
  }

  /// The `Keys`/`Curves` toggle's own choice, or a placeholder for whichever
  /// of the two has nothing to show yet — no open clip for [TimelinePanel],
  /// no selected track for [CurveEditor].
  Widget _timelineOrCurves(
    AppLocalizations l,
    int? openClipIndex,
    ProjectClip? openClip,
    ProjectTrack? track,
    int? trackIndex,
  ) {
    if (openClipIndex == null || openClip == null) {
      return Center(child: Text(l.animPickAction));
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
              pixelsPerSecond: pixelsPerSecond,
              selectedTrack: selectedTrack,
              selectedKey: selectedKey,
              selectedKeys: selectedKeys,
              frameSnap: frameSnap,
              onZoom: onZoom,
              onMoveKeys: onMoveKeys,
              onSeek: onSeek,
              onSelectKey: onSelectKey,
              onSetKey: onSetKey,
            ),
      );
    }
    if (track == null || trackIndex == null) {
      return Center(child: Text(l.animPickTrack));
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
