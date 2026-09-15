/// `_ModelerScreenState`'s own `S5` half: the weight-paint brush's pointer
/// wiring, its own plain settings (radius/strength/mirror/normalize), and
/// keeping the weights view's own vertex-colour gradient in step with the
/// joint a person has selected and the strokes they have painted — see
/// `weight_paint_session.dart` for the transaction/`PaintWeights` half of
/// this, and `weight_gradient.dart`'s own class comment for why nothing
/// called `paintWeightGradient`/`WeightGradientShading` before this file.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: every method here reaches `_cubit`, `_history`,
/// `_device`, `_selectedJoint` or `setState` directly, and a `part` is what
/// lets it keep doing that as an `extension` method rather than turning every
/// one of those into a parameter or a public setter.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of '../../main.dart';

extension _WeightPaintWiring on _ModelerScreenState {
  /// `ModelerViewport.onStroke`, wired only while the weights sub-mode's own
  /// tool is armed — see `ready_parts.dart`'s own `strokeTool`/`onStroke`.
  void _onWeightStroke(StrokeEvent event) {
    final state = _state;
    if (state is! ModelerReady) return;
    final PaintWeightsMode mode = paintWeightsModeOf(state.tool);

    switch (event.phase) {
      case StrokePhase.start:
        final int? objectId = state.selection.activeObject;
        final int? skeletonIndex = objectId == null
            ? null
            : state.project[objectId]?.skeletonIndex;
        final int? joint = _selectedJoint;
        if (objectId == null || skeletonIndex == null || joint == null) {
          return;
        }
        final int? hit = _weightPaintSession.pointerDown(
          view: event.view,
          at: event.at,
          objectId: objectId,
          skeletonIndex: skeletonIndex,
          joint: joint,
          radiusPixels: _weightBrushRadius,
          strength: _weightBrushStrength * event.force,
          mode: mode,
          mirror: _weightMirror,
          normalize: _weightNormalize,
        );
        setState(() => _selectedWeightVertex = hit);
        _refreshWeightGradient();
      case StrokePhase.move:
        final int? hit = _weightPaintSession.pointerMove(
          view: event.view,
          at: event.at,
          radiusPixels: _weightBrushRadius,
          strength: _weightBrushStrength * event.force,
          mode: mode,
          mirror: _weightMirror,
          normalize: _weightNormalize,
        );
        if (hit != null) setState(() => _selectedWeightVertex = hit);
        _refreshWeightGradient();
      case StrokePhase.end:
        _weightPaintSession.pointerUp();
    }
  }

  /// `WeightPaintPanel.onModeChanged`: arms `weights.paint`/`weights.assign`
  /// the same way pressing either rail button already does.
  void _setWeightBrushMode(PaintWeightsMode mode) => _ranTool(
    mode == PaintWeightsMode.assign ? 'weights.assign' : 'weights.paint',
  );

  void _setWeightBrushRadius(double v) =>
      setState(() => _weightBrushRadius = v);

  void _setWeightBrushStrength(double v) =>
      setState(() => _weightBrushStrength = v);

  void _setWeightMirror(bool v) => setState(() => _weightMirror = v);

  void _setWeightNormalize(bool v) => setState(() => _weightNormalize = v);

  /// `ModelerModeSwitcher`'s own second segmented control, wrapped so
  /// switching into the weights sub-mode brings the gradient with it rather
  /// than waiting for the first joint pick or the first stroke.
  void _setAnimationSubmode(AnimationSubmode submode) {
    _cubit.animationSubmode(submode);
    if (submode == AnimationSubmode.weights) _refreshWeightGradient();
  }

  /// The bottom slot's own content in the weights sub-mode: `BendSliderBar`
  /// over the joint a stroke paints onto, for judging a paint job against a
  /// bent pose without leaving the sub-mode — or a placeholder before
  /// there is a joint to bend at all. Never touches [ModelHistory] — see
  /// `bend_slider_bar.dart`'s own class comment for why there is nothing
  /// here to route through it.
  Widget _weightBottom(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    final int? jointId = _selectedJoint;
    final Skeleton? engineSkeleton = objectId == null
        ? null
        : state.stage.sync?.nodeOf(objectId)?.skeleton;
    final int? skeletonIndex = objectId == null
        ? null
        : state.project[objectId]?.skeletonIndex;
    final SceneNode? jointNode = jointId == null
        ? null
        : state.stage.sync?.nodeOf(jointId);
    final ProjectSkeleton? projectSkeleton =
        skeletonIndex != null && skeletonIndex < state.project.skeletons.length
        ? state.project.skeletons[skeletonIndex]
        : null;
    final int jointIndex = jointId == null || projectSkeleton == null
        ? -1
        : projectSkeleton.joints.indexOf(jointId);

    if (engineSkeleton == null ||
        jointNode == null ||
        projectSkeleton == null ||
        jointIndex < 0) {
      return const Center(child: Text('Select a bone to test its bend'));
    }
    return BendSliderBar(
      joint: jointNode,
      jointIndex: jointIndex,
      pose: poseOf(state.project, projectSkeleton),
      skeleton: engineSkeleton,
      label: jointNode.name ?? 'Bend',
    );
  }

  /// Recomputes the weights view's own vertex-colour gradient for the held
  /// object's own [_selectedJoint] — after a stroke, after picking a
  /// different bone, or after switching into the sub-mode itself. A no-op
  /// outside the weights sub-mode, or when any one of the object/skeleton/
  /// joint/mesh/upload it needs is missing — the honest "nothing to colour
  /// yet" rather than a crash on a document mid-way through being rigged.
  void _refreshWeightGradient() {
    final state = _state;
    if (state is! ModelerReady) return;
    if (state.mode != ModelerMode.animation ||
        state.animationSubmode != AnimationSubmode.weights) {
      return;
    }
    final GraphicsDevice? device = _device;
    if (device == null) return;
    final int? objectId = state.selection.activeObject;
    final int? joint = _selectedJoint;
    if (objectId == null || joint == null) return;
    final ModelObject? held = state.project[objectId];
    final int? skeletonIndex = held?.skeletonIndex;
    if (skeletonIndex == null ||
        skeletonIndex >= state.project.skeletons.length) {
      return;
    }
    final EditMesh? mesh = switch (held?.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    if (mesh == null) return;
    final int localJoint = state.project.skeletons[skeletonIndex].joints
        .indexOf(joint);
    if (localJoint < 0) return;
    // `SceneSync` always uploads a skinned object's own geometry through
    // `DeviceMesh.upload` — see `scene_sync.dart`'s own `_dataOf` — so the
    // node's `MeshGeometry` is always the concrete type `paintWeightGradient`
    // itself needs; the `switch` is the honest way to say so rather than a
    // cast that would throw on whichever future `MeshGeometry` this is not.
    final DeviceMesh? deviceMesh = switch (state.stage.sync
        ?.nodeOf(objectId)
        ?.mesh) {
      final DeviceMesh dm => dm,
      _ => null,
    };
    if (deviceMesh == null) return;

    final plan = MeshLayoutPlan()..build(mesh);
    paintWeightGradient(
      device: device,
      mesh: deviceMesh,
      plan: plan,
      vertexWeights: vertexWeightsForJoint(mesh, localJoint),
    );
  }
}
