/// `_ModelerScreenState`'s own surroundings: the app shell, the one-document
/// autosave/crash wiring around it, and the pure recovery lookup that both
/// draw on.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: [_onUncaughtError] reaches `_liveCrashScreen`'s
/// own `_cubit`/`_autosave` directly, and [ModelerApp] reaches
/// `_rootNavigatorKey`, both private to this library. See `device.dart` in
/// this same directory for the fuller version of this rationale.
part of '../../main.dart';

/// Reaches whatever `ModelerScreen` is on screen right now — see
/// [_liveCrashScreen]'s own doc comment for why a top-level error handler
/// needs a door like this at all.
Future<void> _onUncaughtError(Object error, StackTrace stackTrace) =>
    handleCrash(
      error: error,
      stackTrace: stackTrace,
      cubit: _liveCrashScreen?._cubit,
      storage: _liveCrashScreen?._autosave?.storage,
      sessionId: _kAutosaveSessionId,
      environment: 'Flutter, ${environmentSummary()}',
      dialogContext: () => _rootNavigatorKey.currentContext,
    );

/// Where the dialog [_onUncaughtError] shows actually opens — a
/// `Navigator` above every route this application ever pushes, rather than
/// `ModelerScreen`'s own `BuildContext`: the crash that needs showing might
/// be the one that unmounted a dialog already open on top of it.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Set for as long as one `_ModelerScreenState` is alive, cleared on
/// `dispose` — [_onUncaughtError] is a top-level function with no `State` of
/// its own, and this is how it reaches the one document this single-window
/// application ever has open, the same single-instance reasoning
/// `_kAutosaveSessionId`'s own doc comment already relies on.
_ModelerScreenState? _liveCrashScreen;

class ModelerApp extends StatelessWidget {
  const ModelerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _rootNavigatorKey,
    title: 'flutter3d modeller',
    debugShowCheckedModeBanner: false,
    theme: modelerTheme(),
    // `ui-22`: Russian and English both from the first version. What
    // `_cubit.say(...)` shows stays English on purpose — that is the
    // diagnostic language this repository already uses in core and MCP,
    // not the interface language.
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ModelerScreen(),
  );
}

/// What the screen is doing. Three states, and no more until there is a
/// document to have states about.
class ModelerScreen extends StatefulWidget {
  const ModelerScreen({super.key, this.autosaveStorage});

  /// Where `ui-18`'s own autosave writes — null in every real build, which
  /// falls back to the platform's own `defaultBinaryStorage`. A test hands
  /// in a fake here instead of standing up a real filesystem or IndexedDB.
  final BinaryStorage? autosaveStorage;

  @override
  State<ModelerScreen> createState() => _ModelerScreenState();
}

/// `ui-18`'s own autosave key, for the one document this single-window app
/// ever has open at a time.
///
/// **A fixed string, not one minted per launch.** `recoveryPathFor`'s own
/// doc comment warns two different new documents must not collide on the
/// session id the way two openings of one saved file are meant to — but
/// that is a worry for an app that can hold several unsaved documents at
/// once, and this one cannot: there is exactly one `ModelerScreen`, so
/// exactly one autosave slot is exactly what a crash-recovery key needs. A
/// fresh id every launch would instead lose the previous session's own
/// autosave the moment the app that wrote it closed — the one case
/// autosave exists for.
const String _kAutosaveSessionId = 'single-window';

/// Whatever `sessionId`'s own autosave slot in `storage` holds, decoded —
/// null when there is nothing there, or when what is there does not read
/// back as a project at all.
///
/// **Pure IO and decode, no `BuildContext`, no dialog** — the part of
/// `ui-18`'s own "предложение восстановить" that a test can drive with
/// `FakeBinaryStorage` directly, the same split `autosave.dart`'s own
/// `shouldSave`/`decideRecovery` already make between deciding and doing.
/// A stale entry (one `readProject` refuses) is removed here rather than
/// left for the caller to notice twice — there is nothing for a person to
/// decide about a recovery copy this build itself could not have written.
Future<ProjectOpened?> findRecovery(
  BinaryStorage storage,
  String sessionId,
) async {
  final key = recoveryPathFor(null, sessionId: sessionId);
  final bytes = await storage.read(key);
  if (bytes == null) return null;
  final read = readProject(bytes);
  if (read is ProjectOpened) return read;
  await storage.remove(key);
  return null;
}
