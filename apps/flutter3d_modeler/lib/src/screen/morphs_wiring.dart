/// `_ModelerScreenState`'s own `S6` half: the morphs sub-mode's own
/// `MorphsPanel` callbacks — a shape's weight, its key dot, which shape is
/// selected, and its driver rows — every one of them a single [ModelCommand]
/// through [ModelerCubit.ran], never a direct write to the project, the same
/// rule every other sub-mode's own wiring file here keeps.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: every method here reaches `_cubit`, `_history`,
/// `_frame` or `setState` directly, and a `part` is what lets it keep doing
/// that as an `extension` method rather than turning every one of those into
/// a parameter or a public setter.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _MorphsWiring on _ModelerScreenState {
  /// `MorphsPanel.onSetWeight`.
  void _setShapeWeight(int id, int shapeIndex, double weight) => _cubit.ran(
    SetShapeWeight(id: id, shapeIndex: shapeIndex, weight: weight),
  );

  /// `MorphsPanel.onKeyShape`: every one of [id]'s own shape weights, keyed
  /// at the timeline's own current frame — `KeyShape`'s own "capture the
  /// live state" shape, the same as `_setAnimationKey`'s row for a pose.
  void _keyShape(int id) {
    final int? clipIndex = _animationClip;
    if (clipIndex == null) {
      _cubit.say('select an action first');
      return;
    }
    _cubit.ran(
      KeyShape(
        id: id,
        clipIndex: clipIndex,
        time: KeyTable.timeOfFrame(_frame.value, _history.project.profile.fps),
      ),
    );
  }

  /// `MorphsPanel.onSelectShape`.
  void _selectShape(int index) => setState(() => _selectedShape = index);

  /// `MorphsPanel.onAddDriver`: a new [ShapeDriver] for shape [shapeIndex],
  /// on whichever of [id]'s own skeleton joints comes first — a starting
  /// point a person edits from the row's own bone picker straight after,
  /// the same "something real rather than nothing to pick from" default
  /// `_addLight`'s own row already gives a fresh light.
  void _addShapeDriver(int id, int shapeIndex) {
    final ProjectSkeleton? skeleton = heldSkeletonOf(
      _history.project,
      _history.project[id],
    );
    final List<int> joints = skeleton?.joints ?? const <int>[];
    if (joints.isEmpty) {
      _cubit.say('rig this object before adding a shape driver');
      return;
    }
    _cubit.ran(
      AddShapeDriver(
        id: id,
        driver: ShapeDriver(
          shapeIndex: shapeIndex,
          jointId: joints.first,
          axis: DriverAxis.x,
          from: 0.0,
          to: math.pi / 2,
        ),
      ),
    );
  }

  /// `MorphsPanel.onRemoveDriver`.
  void _removeShapeDriver(int id, int index) =>
      _cubit.ran(RemoveShapeDriver(id: id, index: index));

  /// `MorphsPanel.onSetDriverField`.
  void _setShapeDriverField(int id, int index, String field, Object? value) =>
      _cubit.ran(
        SetShapeDriverField(id: id, index: index, field: field, value: value),
      );
}
