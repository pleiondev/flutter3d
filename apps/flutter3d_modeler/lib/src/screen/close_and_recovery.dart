/// `_ModelerScreenState`'s own close-confirmation and autosave-recovery
/// halves of `ui-24` and `ui-18`.
///
/// A `part of 'main.dart'` for the same reason `device.dart` beside it is:
/// every method here opens a dialog against `context`, reads `mounted`
/// after the `await`, and reaches `_cubit`/`_history` directly.
part of '../../main.dart';

extension _CloseAndRecovery on _ModelerScreenState {
  /// Answers the OS's own "can you close now?" — `ui-24`'s "при isDirty —
  /// диалог" on the platforms that ask this way rather than through a
  /// `Navigator` pop.
  Future<ui.AppExitResponse> _onExitRequested() async {
    if (!needsConfirmation(isDirty: _history.isDirty)) {
      return ui.AppExitResponse.exit;
    }
    final UnsavedChoice? choice = await _askUnsavedChoice();
    if (choice == null) return ui.AppExitResponse.cancel;
    final closed = await shouldClose(choice, write: _saveFile);
    return closed ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
  }

  /// `PopScope`'s own callback when [canPop] blocked a pop — the in-app-nav
  /// half of `ui-24`'s dialog, for whatever platform routes an exit attempt
  /// through a `Navigator` pop rather than asking the OS directly.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    final UnsavedChoice? choice = await _askUnsavedChoice();
    if (choice == null) return;
    final closed = await shouldClose(choice, write: _saveFile);
    if (closed && mounted) await SystemNavigator.pop();
  }

  /// The three answers `close_guard.dart`'s own [UnsavedChoice] names, put
  /// in front of a person once — every caller that finds the document
  /// dirty on the way out asks through this one dialog rather than each
  /// growing a slightly different one.
  Future<UnsavedChoice?> _askUnsavedChoice() =>
      UnsavedChangesDialog.show(context);

  /// `ui-18`'s own "предложение восстановить": an autosave from a session
  /// that never closed cleanly, offered once, right after the ordinary open
  /// already put a cube on screen — never in place of it, since a recovery
  /// copy that itself fails to read (it should not, `_autosave` is the only
  /// thing that ever wrote this key) is not a reason to keep someone looking
  /// at a blank screen.
  Future<void> _offerRecovery(GraphicsDevice device) async {
    final storage = _autosave?.storage;
    if (storage == null) return;
    final read = await findRecovery(storage, _kAutosaveSessionId);
    if (read == null || !mounted) return;

    final restore = await RestoreAutosaveDialog.show(
      context,
      objectCount: read.project.objects.length,
    );
    if (!mounted) return;

    if (restore != true) {
      await storage.remove(
        recoveryPathFor(null, sessionId: _kAutosaveSessionId),
      );
      return;
    }
    final stage = ModelerStage.fromProject(
      device: device,
      project: read.project,
    );
    // Unlike every other opening path, this one must not forget the old
    // materials — there is no old scene here to have painted anything, and
    // `_offerRecovery` runs right after the ordinary open already built one.
    _installOpened(
      ModelHistory(read.project),
      stage,
      documentName: 'recovered',
      said: 'restored an autosave from a session that did not close cleanly',
      forgetSurfaces: false,
    );
  }
}
