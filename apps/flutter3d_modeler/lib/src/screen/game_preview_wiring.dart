/// `_ModelerScreenState`'s own `S9` half: opening screen 19's full-screen
/// preview for the document currently held.
///
/// **A `part of 'main.dart'`, not a file of its own** — every method here
/// reaches `_cubit`/`_state`/`_frame`/`_timelinePreview`/`context` directly,
/// the same reason every file in this directory is; see
/// `retarget_wiring.dart`'s own class comment for the fuller version of this
/// rationale.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of '../../main.dart';

extension _GamePreviewWiring on _ModelerScreenState {
  /// `TopBarActions.onPreview`: opens `game_preview_screen.dart` over the
  /// document currently held.
  Future<void> _openGamePreview() async {
    final ModelerState state = _state;
    if (state is! ModelerReady) return;
    await showGamePreviewScreen(
      context,
      renderer: state.renderer,
      stage: state.stage,
      project: state.project,
      readiness: state.readiness,
      // `tut-07`'s own fix: the same `LightingSync.apply` fold the main
      // viewport's own `RenderSettings` already gets, so this screen's
      // "the same `Renderer`/`ModelerStage` as the editor" promise (this
      // file's own class comment) holds for the document's real lighting
      // too, not only for its geometry.
      baseSettings: (state.stage.lighting ?? LightingSync()).apply(
        const RenderSettings(),
        state.project.lighting,
      ),
      playback: state.playback,
      frame: _frame,
      onPlayPause: _toggleAnimationPlayback,
      // The same per-frame call `_onTick` makes while this route is not the
      // one on top — see `GamePreviewScreen`'s own class comment for why its
      // own `Ticker` is what keeps calling this at all while the editor's is
      // muted underneath it.
      onTick: (double seconds) {
        state.stage.orbit.advance(seconds);
        _timelinePreview.tick(_history.project, state.stage.sync, seconds);
      },
    );
  }

  /// `ux-50`: the document walked in, on [template].
  ///
  /// **The live project, not a copy.** `PlaySession` builds its scene with
  /// the same `SceneSync` the viewport uses, so an edit made behind this
  /// route reaches it on the frame the document emits — which is the row's
  /// own "a colour change shows in the running game without a restart", and
  /// it is what choosing in-process bought.
  Future<void> _openPlay(PlayTemplate template) async {
    final ModelerState state = _state;
    if (state is! ModelerReady) return;
    // `ux-51`: the same gate Export keeps. A document that will not export
    // will not play either — Play hands it over exactly as an export does —
    // and it refuses in Export's own sentence rather than a second one
    // written for this button.
    if (!state.readiness.canExport) {
      _cubit.say('Play: ${state.readiness.says}', important: true);
      return;
    }
    await showPlay(
      context,
      renderer: state.renderer,
      // Read on every Reload rather than captured: the document keeps being
      // edited — by a person behind the route, by an agent over MCP — while
      // Play is open.
      projectNow: () => _history.project,
      template: template,
      control: _play,
    );
  }
}
