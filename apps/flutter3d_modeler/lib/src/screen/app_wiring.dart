/// `_ModelerScreenState`'s own surroundings: the app shell, the one-document
/// autosave/crash wiring around it, and the pure recovery lookup that both
/// draw on.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: [_onUncaughtError] reaches `_liveCrashScreen`'s
/// own `_cubit`/`_autosave` directly, and [ModelerApp] reaches
/// `_rootNavigatorKey`, both private to this library. See `device.dart` in
/// this same directory for the fuller version of this rationale.
part of 'modeler_screen.dart';

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
      environment: reportEnvironmentFor(environmentSummary()),
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
  const ModelerScreen({
    super.key,
    this.autosaveStorage,
    this.settingsStorage,
    this.mcpPort,
    this.mcpSessionPath,
    this.cabinetLink,
    this.cabinetSourceSender,
    this.previewCapturer,
  });

  /// Where `ui-18`'s own autosave writes — null in every real build, which
  /// falls back to the platform's own `defaultBinaryStorage`. A test hands
  /// in a fake here instead of standing up a real filesystem or IndexedDB.
  final BinaryStorage? autosaveStorage;

  /// Where `ux-09`'s own settings document lives — null in every real build,
  /// which falls back to the platform's own `defaultStorage`. A test hands in
  /// a map in memory, the same shape [autosaveStorage] already is.
  final Storage? settingsStorage;

  /// Which port the agent server listens on — null in every real build,
  /// which reads `--dart-define=mcpPort` the way it always has.
  ///
  /// **Injected for the same reason [autosaveStorage] is.** A define is not
  /// reachable from a test, so the whole agent path — a client connecting,
  /// the badge appearing, the panel opening on a real tool call — could only
  /// be exercised by standing the server up by hand beside the application
  /// rather than through it. Zero is a real value here and means "any free
  /// port", which is what a test wants.
  final int? mcpPort;

  /// Where that server writes its own `mcp-session.json` — null in every
  /// real build, which asks the platform for its application-support
  /// directory.
  ///
  /// A path rather than a `Directory`, because this file compiles for the
  /// web too and `dart:io` does not exist there. A headless test has no
  /// `path_provider` plugin behind it, so a caller that injects [mcpPort]
  /// injects this beside it.
  final String? mcpSessionPath;

  /// `tut-19`/`tut-20`'s own cabinet id/mode — null in every real build,
  /// which falls back to `CabinetLink.fromQuery(Uri.base.queryParameters)`
  /// the moment `_open()` runs, the same place `model`/`name` already come
  /// from. A test hands in one directly instead of needing a query string on
  /// `Uri.base`, which nothing in a `flutter test` process can set.
  final CabinetLink? cabinetLink;

  /// Where `_saveToCabinet` POSTs — null in every real build, which falls
  /// back to `postSourceToCabinet`, the platform's own real `HttpClient`/
  /// `fetch` send. A test hands in a fake here instead of reaching for a
  /// real network call, the same "fake stands in for the real platform call"
  /// shape [autosaveStorage] already is for `defaultBinaryStorage`.
  final CabinetSourceSender? cabinetSourceSender;

  /// Where `tut-19`'s own preview capture POSTs a picture — null in every
  /// real build, which falls back to `capturePreview`, the platform's own
  /// real canvas-and-`fetch` send. A test hands in a fake here instead, the
  /// same door [cabinetSourceSender] already is for `postSourceToCabinet`.
  final PreviewCapturer? previewCapturer;

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
