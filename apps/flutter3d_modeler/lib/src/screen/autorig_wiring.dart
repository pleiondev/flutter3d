/// `_ModelerScreenState`'s own `S8` half: opening screen 16's auto-rig
/// dialog for the currently held object.
///
/// **A `part of 'main.dart'`, not a file of its own** — every method here
/// reaches `_cubit`/`_state`/`context` directly, the same reason every file
/// in this directory is a `part`; see `retarget_wiring.dart`'s own class
/// comment for the fuller version of this rationale.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _AutorigWiring on _ModelerScreenState {
  /// `pose.autoRig`: opens `autorig_dialog.dart` for the held object — the
  /// same "select something first" refusal `_autoMapRetarget` gives when
  /// there is nothing to answer for.
  Future<void> _openAutorigDialog() async {
    final ModelerState state = _state;
    if (state is! ModelerReady) return;
    final int? id = state.selection.activeObject;
    if (id == null) {
      _cubit.say('select a mesh to rig first');
      return;
    }
    final ModelObject? object = state.project[id];
    if (object == null || object.geometry is! EditedGeometry) {
      _cubit.say('select a mesh to rig first');
      return;
    }
    await showAutorigDialog(
      context,
      cubit: _cubit,
      renderer: state.renderer,
      project: state.project,
      skinObjectId: id,
    );
  }
}
