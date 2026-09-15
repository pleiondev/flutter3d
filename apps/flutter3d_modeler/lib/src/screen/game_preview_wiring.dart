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
      // A bare default — see `game_preview_settings.dart`'s own doc comment
      // on `GamePreviewSettings.applyTo` for why nothing richer is threaded
      // through here yet.
      baseSettings: const RenderSettings(),
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
}
