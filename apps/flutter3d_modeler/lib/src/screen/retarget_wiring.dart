/// `_ModelerScreenState`'s own `S7` half: importing a source clip, mapping
/// its bones onto the held object's own skeleton, and applying the retarget
/// — screen 14. See `retarget_source.dart` for why the imported file is its
/// own `ModelProject` rather than something merged into this one, and
/// `rig_job.dart`'s own `RetargetClipJobRequest`/`ModelerCubit.
/// retargetInBackground` for what actually runs the algorithm.
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

extension _RetargetWiring on _ModelerScreenState {
  /// `retarget.import`: opens the same picker `_openFile` uses, decodes it
  /// the same way, and reads it as a [RetargetSource] — never merged into
  /// [_history]'s own project. Cancelling the picker or a file that decodes
  /// empty are both said rather than thrown, the same tone `_openFile`
  /// already keeps for either.
  Future<void> _importRetargetSource() async {
    _cubit.say('choosing a source clip…');
    try {
      final PickedFile? picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      final ModelDocument document = await decodeBytes(
        picked.bytes,
        picked.name,
      );
      final String? empty = emptyDecodeRefusal(document, picked.name);
      if (empty != null) {
        if (mounted) _cubit.say(empty);
        return;
      }
      final RetargetSource source = RetargetSource.fromDocument(
        picked.name,
        document,
      );
      if (!mounted) return;
      setState(() {
        _retargetSource = source;
        _retargetSourceClipIndex = source.clips.isEmpty ? null : 0;
        _retargetBoneMap = const BoneMap(<String, String>{});
        _retargetAppliedClipIndex = null;
        _retargetAppliedClipName = null;
      });
      _cubit.say(
        source.warning ?? 'imported ${picked.name}',
        important: source.warning != null,
      );
    } catch (error) {
      if (mounted) _cubit.say('could not import it: $error');
    }
  }

  /// `ClipLibrary.onSelectClip`: which of the source's own clips the two
  /// viewports and `retarget.apply` read next.
  void _selectRetargetClip(int index) =>
      setState(() => _retargetSourceClipIndex = index);

  /// The held object's own skeleton — `retarget.autoMap`/`retarget.apply`
  /// both read it as the retarget's own `targetSkeleton`. Null with nothing
  /// rigged selected, the same "select a rigged object first" refusal both
  /// actions give for it.
  ProjectSkeleton? _retargetTargetSkeleton(ModelerReady state) =>
      heldSkeletonOf(
        state.project,
        state.project[state.selection.activeObject ?? -1],
      );

  /// `retarget.autoMap`/`BoneMapTable.onAutoMap`: `looseAutoMap` over the
  /// source's own joint names and the held object's own — `anim-18`'s row,
  /// kept apart from the exact `autoMap` `anim-17`'s retarget test already
  /// covers.
  void _autoMapRetarget() {
    final RetargetSource? source = _retargetSource;
    final ModelerState state = _state;
    if (source == null || state is! ModelerReady) return;
    final ProjectSkeleton? target = _retargetTargetSkeleton(state);
    if (target == null) {
      _cubit.say('select a rigged object first');
      return;
    }
    final List<String> sourceNames = <String>[
      for (final int id in source.skeleton.joints)
        source.project[id]?.name ?? 'joint $id',
    ];
    final List<String> targetNames = <String>[
      for (final int id in target.joints)
        state.project[id]?.name ?? 'joint $id',
    ];
    setState(() => _retargetBoneMap = looseAutoMap(sourceNames, targetNames));
  }

  /// Every joint name on the imported source's own skeleton — empty before
  /// `retarget.import` has run — for [BoneMapTable]'s own left column.
  List<String> get _retargetSourceNames {
    final RetargetSource? source = _retargetSource;
    if (source == null) return const <String>[];
    return <String>[
      for (final int id in source.skeleton.joints)
        source.project[id]?.name ?? 'joint $id',
    ];
  }

  /// Whether `retarget.apply` has a source clip and a rigged target to run
  /// against — [RetargetPanel.canApply]'s own value.
  bool get _retargetCanApply {
    final ModelerState state = _state;
    if (state is! ModelerReady) return false;
    if (_retargetSource == null || _retargetSourceClipIndex == null) {
      return false;
    }
    return _retargetTargetSkeleton(state) != null;
  }

  /// `retarget.apply`: `retargetClipJobRequestFor` through `ModelerCubit.
  /// retargetInBackground`, always appending — `anim-18`'s own row never
  /// replaces a clip already on the target. Root motion left `inCode` runs
  /// `ExtractRootMotion` on the freshly appended clip right after it lands.
  Future<void> _applyRetarget() async {
    final RetargetSource? source = _retargetSource;
    final ModelerState state = _state;
    final int? clipIndex = _retargetSourceClipIndex;
    if (source == null || state is! ModelerReady || clipIndex == null) return;
    final int? targetObjectId = state.selection.activeObject;
    final int? targetSkeletonIndex = targetObjectId == null
        ? null
        : state.project[targetObjectId]?.skeletonIndex;
    if (targetSkeletonIndex == null) {
      _cubit.say('select a rigged object first');
      return;
    }
    final RetargetClipJobRequest? request = retargetClipJobRequestFor(
      sourceProject: source.project,
      sourceSkeletonIndex: source.skeletonIndex,
      sourceClipIndex: clipIndex,
      targetProject: state.project,
      targetSkeletonIndex: targetSkeletonIndex,
      boneMap: _retargetBoneMap,
      lockFeet: _retargetLockFeet,
      groundY: _retargetGroundY,
      footTolerance: _retargetFootTolerance,
    );
    if (request == null) {
      _cubit.say('nothing to retarget');
      return;
    }
    final ApplyClipResult? applied = await _cubit.retargetInBackground(request);
    if (applied == null || !mounted) return;
    final ModelerReady after = _state as ModelerReady;
    final int newClipIndex = after.project.clips.length - 1;
    setState(() {
      _retargetAppliedClipIndex = newClipIndex;
      _retargetAppliedClipName = applied.clip.name ?? 'retargeted';
    });
    if (_retargetRootMotion == RetargetRootMotion.inCode) {
      final ProjectSkeleton? target = _retargetTargetSkeleton(after);
      if (target != null && target.joints.isNotEmpty) {
        _cubit.ran(
          ExtractRootMotion(
            clipIndex: newClipIndex,
            rootJoint: target.joints.first,
          ),
        );
      }
    }
  }

  /// `RetargetPanel.onRootMotionChanged`: re-runs `ExtractRootMotion`/
  /// `BakeRootMotionIntoClip` on the already-applied clip when there is one,
  /// so flipping the switch after `retarget.apply` still does something —
  /// [_applyRetarget] itself only reads this at the moment a fresh clip
  /// lands.
  void _setRetargetRootMotion(RetargetRootMotion mode) {
    final int? clipIndex = _retargetAppliedClipIndex;
    final ModelerState state = _state;
    if (clipIndex != null && state is ModelerReady) {
      final ProjectSkeleton? target = _retargetTargetSkeleton(state);
      if (target != null && target.joints.isNotEmpty) {
        _cubit.ran(
          mode == RetargetRootMotion.inCode
              ? ExtractRootMotion(
                  clipIndex: clipIndex,
                  rootJoint: target.joints.first,
                )
              : BakeRootMotionIntoClip(
                  clipIndex: clipIndex,
                  rootJoint: target.joints.first,
                ),
        );
      }
    }
    setState(() => _retargetRootMotion = mode);
  }

  void _setRetargetLockFeet(bool v) => setState(() => _retargetLockFeet = v);
  void _setRetargetGroundY(double v) => setState(() => _retargetGroundY = v);
  void _setRetargetFootTolerance(double v) =>
      setState(() => _retargetFootTolerance = v);
  void _setRetargetBlend(double v) => setState(() => _retargetBlendSeconds = v);

  /// `ClipTracksBar.onPreview`: crossfades the live preview onto the
  /// applied clip over the blend slider's own duration.
  void _previewRetargetBlend() {
    final ModelerState state = _state;
    final int? clipIndex = _retargetAppliedClipIndex;
    if (state is! ModelerReady || clipIndex == null) return;
    _timelinePreview.crossFadeTo(
      state.project,
      state.stage.sync,
      clipIndex,
      duration: _retargetBlendSeconds,
    );
  }

  /// The retarget sub-mode's own viewport slot: the clip library at
  /// [ModelerMetrics.clipLibrary] wide, then the source/target pair —
  /// replaces the ordinary single [ModelerViewport] entirely, the same way
  /// `S8`'s own autorig dialog stands up a second stage rather than
  /// reusing the shell's one viewport slot for something it was never
  /// built to show two of at once.
  Widget _retargetViewport(ModelerReady state) => Row(
    children: <Widget>[
      SizedBox(
        width: ModelerMetrics.clipLibrary,
        child: ClipLibrary(
          source: _retargetSource,
          selectedClipIndex: _retargetSourceClipIndex,
          onSelectClip: _selectRetargetClip,
          onImport: () => unawaited(_importRetargetSource()),
        ),
      ),
      Expanded(
        child: RetargetViewports(
          renderer: state.renderer,
          targetStage: state.stage,
          source: _retargetSource,
        ),
      ),
    ],
  );

  /// The retarget sub-mode's own bottom slot — `ModelerMetrics.
  /// retargetTracksBar` tall.
  Widget _retargetBottom() => ClipTracksBar(
    clipName: _retargetAppliedClipName,
    blendSeconds: _retargetBlendSeconds,
    onBlendChanged: _setRetargetBlend,
    onPreview: _retargetAppliedClipIndex == null ? null : _previewRetargetBlend,
  );
}
