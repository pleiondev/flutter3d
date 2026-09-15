/// `_ModelerScreenState`'s own `S2` half: the clip/track/key/joint/
/// constraint selection [AnimationPanel] and `TimelinePanel` used to keep to
/// themselves before this, now that the transport bar, the timeline and the
/// curve editor all need to agree on it, plus the transport's own play/
/// pause/loop/speed controls and the tap-to-key gesture — see
/// `animation_wiring.dart` for the pure command-building half of this file,
/// and `main.dart`'s own class comment on [_frame] for why the playhead
/// itself is not among the fields below.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: every method here reaches `_cubit`, `_history`,
/// `_timelinePreview` or `setState` directly, and a `part` is what lets it
/// keep doing that as an `extension` method rather than turning every one of
/// those into a parameter or a public setter.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of '../../main.dart';

extension _AnimationWiring on _ModelerScreenState {
  /// [_selectedAnimationClip], clamped against the live project — a clip
  /// removed from under the current selection (an undo past `AddClip`, say)
  /// reads as nothing selected rather than as a stale index the timeline
  /// would have to guard against on every read.
  int? get _animationClip =>
      _selectedAnimationClip != null &&
          _selectedAnimationClip! < _history.project.clips.length
      ? _selectedAnimationClip
      : null;

  /// `AnimationPanel.onSelectClip`: opens clip [index] and starts previewing
  /// its first pose, paused — [TimelinePreviewWiring.selectClip]'s own
  /// "scrubbing is what plays it" rule. A fresh clip means whatever track or
  /// key the timeline had highlighted named a row in a *different* clip's
  /// own track list, so both are cleared the same way picking a fresh clip
  /// always has been.
  void _selectAnimationClip(int index) {
    setState(() {
      _selectedAnimationClip = index;
      _selectedAnimationTrack = null;
      _selectedAnimationKey = null;
    });
    if (_state case ModelerReady(:final project, :final stage)) {
      _timelinePreview.selectClip(project, stage.sync, index);
    }
  }

  /// `TimelinePanel.onSelectKey`/`CurveEditor.onSelectKey`: a diamond or a
  /// curve point was picked.
  void _selectAnimationTrackKey(int trackIndex, int keyIndex) => setState(() {
    _selectedAnimationTrack = trackIndex;
    _selectedAnimationKey = keyIndex;
  });

  /// `SkeletonTree.onSelectJoint`, and `S5`'s own `WeightPaintPanel`'s
  /// "Bones" list — the same joint either sub-mode is picking.
  void _selectAnimationJoint(int id) {
    setState(() => _selectedJoint = id);
    _refreshWeightGradient();
  }

  /// `ConstraintsList.onSelect`.
  void _selectAnimationConstraint(int index) =>
      setState(() => _selectedConstraint = index);

  /// `TransportBar.onEditMode`: screen 07's own `Keys`/`Curves` switch.
  void _setTimelineEditMode(TimelineEditMode mode) =>
      setState(() => _timelineEditMode = mode);

  /// `TransportBar.onPlayPause`.
  ///
  /// **No `setState` of its own.** [TimelinePreviewWiring.togglePlay] moves
  /// the real `AnimationPlayer`; its own `onPlaybackChanged` hook — wired
  /// once, on [_timelinePreview] itself — is what reaches
  /// [ModelerCubit.playback] from there, the same coarse/frame split this
  /// whole file exists to keep.
  void _toggleAnimationPlayback() => _timelinePreview.togglePlay();

  /// `TransportBar.onLoopChanged`.
  void _setAnimationLoop(bool looping) => _timelinePreview.setLooping(looping);

  /// `TransportBar.onSpeedChanged`.
  void _setAnimationSpeed(double speed) => _timelinePreview.setSpeed(speed);

  /// `TimelinePanel.onSetKey`: a tap on empty track space — `S2`'s own row,
  /// resolved into the one `PoseJoint` it means through
  /// `animation_wiring.dart`'s own `poseJointForSetKey`, then run exactly
  /// like every other single-command edit on this screen: [ModelerCubit.ran],
  /// never a direct write to the project.
  void _setAnimationKey(int trackIndex, double time) {
    final int? clipIndex = _animationClip;
    if (clipIndex == null) {
      _cubit.say('select an action first');
      return;
    }
    final PoseJoint? command = poseJointForSetKey(
      clip: _history.project.clips[clipIndex],
      clipIndex: clipIndex,
      trackIndex: trackIndex,
      time: time,
      fps: _history.project.profile.fps,
    );
    if (command == null) return;
    _cubit.ran(command);
  }

  /// `CurveEditor.onSetKey`: a key dragged vertically in `Curves` mode.
  void _setAnimationKeyValue(SetKey command) => _cubit.ran(command);

  /// `CurveEditor.onSetTangent`: a tangent handle dragged in `Curves` mode.
  void _setAnimationTangent(SetTangent command) => _cubit.ran(command);
}
