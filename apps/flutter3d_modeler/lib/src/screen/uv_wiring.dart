/// `_ModelerScreenState`'s own UV half — `pro-uv-07`, screen 06: what the
/// method, the margin, an island and the two layout tools do when pressed.
///
/// **A file of its own rather than a fifth section of `pro_modes_wiring`.**
/// That file's own header says what its four modes share — a panel of
/// settings docked in the properties slot, over a command or two. This mode
/// shares the second half and not the first: its panel rides inside
/// `UvScreen` beside the layout it describes, and its picture is the mesh
/// mode's own, element picking and all.
///
/// **Every edit is one command, so every edit is one undo step.** Marking a
/// seam, clearing one, unwrapping and packing each go through
/// `ModelerCubit.ran` the way an extrusion does; nothing here writes to a
/// mesh. The same four are what an agent reaches through `markSeam`,
/// `unwrap` and `packAtlas` over MCP, with the same arguments meaning the
/// same things — the panel's margin is `UnwrapCommand.margin`, not a number
/// of this application's own that is converted on the way.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _UvWiring on _ModelerScreenState {
  void _setUnwrapMethod(UnwrapMethod to) => setState(() => _uv.method = to);

  /// Held to what both commands accept — `PackAtlas` refuses a margin past a
  /// quarter of the square, and a negative one means nothing to either. A
  /// number field takes whatever is typed; clamping here is what keeps the
  /// refusal for the cases a person could not have seen coming.
  void _setUnwrapMargin(double to) =>
      setState(() => _uv.margin = to.clamp(0.0, 0.25));

  void _setUnwrapAutoPack(bool to) => setState(() => _uv.autoPack = to);

  /// A tap on the layout and a tap on the list both land here — the one
  /// field `UvScreen.onIslandSelected` promises its caller. Tapping the lit
  /// island puts it out again, since there is no background in a list to
  /// click on instead.
  void _selectUvIsland(int id) =>
      setState(() => _uv.selectedIsland = _uv.selectedIsland == id ? null : id);

  /// Why Unwrap cannot run, or null.
  ///
  /// Asked before the press rather than after it, the bargain `_bakeRefusal`
  /// makes: the button is disabled and says which of the two it is. What is
  /// *not* asked here is whether any face is selected — `UnwrapCommand`
  /// unwraps the whole mesh when none is, which is what somebody who has
  /// just marked their seams and pressed the button means.
  String? _unwrapRefusal(ModelerReady state) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ModelObject? object =
        state.project[state.selection.activeObject ?? -1];
    if (object == null) return l.uvRefusalNoObject;
    if (object.geometry is! EditedGeometry) {
      return l.uvRefusalNoMesh(object.name);
    }
    return null;
  }

  /// The rail's `uv.unwrap` and the panel's own button: one `UnwrapCommand`,
  /// carrying the three settings the panel shows.
  ///
  /// **And a sentence when what landed covers nothing.** `lscm` flattens a
  /// closed surface with no seam on it onto a line — every corner of the cube
  /// a launch opens on comes back with `u = 0` — and `UnwrapCommand` reports
  /// that as done, which it is: the step is on the history and undo takes it
  /// back. But the square stays empty, the status line says "unwrap", and a
  /// person pressing the button on their first model has been told nothing
  /// about why. Whether the command should refuse instead is a question for
  /// the package it lives in; what the interface owes meanwhile is what to do
  /// next, and "mark seams" is it.
  void _unwrapUv() {
    final state = _state;
    if (state is! ModelerReady) return;
    if (_unwrapRefusal(state) case final String refusal) {
      _cubit.say(refusal, important: true, refusal: true);
      return;
    }
    final bool landed = _cubit.ran(
      UnwrapCommand(
        method: _uv.method,
        margin: _uv.margin,
        autoPack: _uv.autoPack,
      ),
    );
    if (!landed) return;
    final ModelObject? held =
        _history.project[_history.selection.activeObject ?? -1];
    if (_uv.readingOf(_editMesh, held?.version ?? 0).islands.isEmpty) {
      _cubit.say(AppLocalizations.of(context).uvUnwrapFlat, important: true);
    }
  }

  /// The rail's `uv.pack`: `PackAtlas` over every selected object, at the
  /// panel's own margin.
  ///
  /// **Refused here for fewer than two, in the interface's own language.**
  /// The command refuses the same thing in English — "an atlas is shared" —
  /// and would be reached a moment later; but it is the most likely press in
  /// this mode, made by somebody who unwrapped one object and expects Pack
  /// to tidy it, and the sentence that tells them what Pack is for is worth
  /// translating. Everything else it can refuse — an object with no UVs, no
  /// material to share — is the command's own to say.
  void _packUvAtlas() {
    final state = _state;
    if (state is! ModelerReady) return;
    final List<int> objects = state.selection.objects;
    if (objects.length < 2) {
      _cubit.say(
        AppLocalizations.of(context).uvPackNeedsTwo,
        important: true,
        refusal: true,
      );
      return;
    }
    _cubit.ran(PackAtlas(objectIds: objects, margin: _uv.margin));
  }
}
