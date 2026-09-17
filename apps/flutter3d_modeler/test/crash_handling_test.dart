/// `ui-30n`: an exception nobody caught still gets an emergency autosave, a
/// "what happened" dialog, and a log naming the command it broke on.
///
///     flutter test test/crash_handling_test.dart
///
/// **Why the crash is simulated rather than thrown from a real `apply()`.**
/// `ModelCommand` (`flutter3d_model_core`) is `sealed` to its own library, so
/// nothing outside `command.dart` can hand it a case that throws. What is
/// simulated instead is the exact sequence `ModelerCubit.ran` runs: it sets
/// [lastAttemptedCommand] on the line before calling `ModelHistory.run`, so a
/// button whose callback does the same thing and then throws leaves the
/// world in exactly the state a real `apply()` throwing would have left it
/// in — which is the only thing [handleCrash] ever reads.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/crash_handling.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A storage kept in memory — the same fake `autosaving_test.dart` and
/// `main_recovery_test.dart` already use for `BinaryStorage`.
final class FakeBinaryStorage implements BinaryStorage {
  final Map<String, Uint8List> documents = <String, Uint8List>{};

  /// Refuses every write, the way a real storage with nowhere to write does —
  /// `ux-01`'s own case, where the dialog used to promise a recovery copy
  /// anyway.
  bool refuse = false;

  @override
  Future<Uint8List?> read(String name) async => documents[name];

  @override
  Future<bool> write(String name, Uint8List contents) async {
    if (refuse) return false;
    documents[name] = contents;
    return true;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: String.fromCharCode(97 + i),
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

ModelerCubit opened({int count = 2}) {
  final it = cpuTestDevice(width: 8, height: 8);
  final history = ModelHistory(cubes(count));
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  return ModelerCubit()..opened(
    history,
    renderer: Renderer.create(device: it.device),
    stage: stage,
  );
}

ModelerReady ready(ModelerCubit cubit) => cubit.state as ModelerReady;

void main() {
  // `FlutterError.onError` is a mutable static the test framework itself
  // relies on to fail a test that throws — every test here replaces it on
  // purpose, so it has to come back for whichever test runs next.
  final void Function(FlutterErrorDetails)? defaultOnError =
      FlutterError.onError;
  // `ux-08` folds a repeated error into one dialog, and the memory that does
  // it is a top-level one — which is right for an application and wrong for a
  // file of tests that all crash on purpose. Cleared between them, so the
  // second test's own crash is its first sight of it.
  setUp(resetCrashDialogMemory);
  tearDown(() {
    FlutterError.onError = defaultOnError;
    lastAttemptedCommand = null;
    resetCrashDialogMemory();
  });

  testWidgets(
    'a crash reached through FlutterError.onError writes an emergency '
    'autosave, shows the dialog, and names the command that threw',
    (WidgetTester tester) async {
      final cubit = opened();
      final storage = FakeBinaryStorage();
      final ids = ready(cubit).project.objects.map((o) => o.id).toList();

      // Two commands that land before the crash — the journal's own "last N
      // commands", read back by the dialog's own log.
      cubit.ran(Rename(id: ids[0], to: 'first'));
      cubit.ran(Rename(id: ids[1], to: 'second'));

      final navigatorKey = GlobalKey<NavigatorState>();

      FlutterError.onError = (FlutterErrorDetails details) {
        unawaited(
          handleCrash(
            error: details.exception,
            stackTrace: details.stack ?? StackTrace.current,
            cubit: cubit,
            storage: storage,
            sessionId: 'crash-test-session',
            environment: 'Flutter, test',
            dialogContext: () => navigatorKey.currentContext,
          ),
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () {
                  // Mirrors `ModelerCubit.ran`'s own first line — see the
                  // library comment for why this cannot instead be a real
                  // `ModelCommand.apply()` throwing.
                  lastAttemptedCommand = Rename(id: ids[0], to: 'crashed');
                  throw StateError('the mesh library blew up mid-apply');
                },
                child: const Text('crash'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('crash'));
      await tester.pumpAndSettle();

      // The emergency autosave landed before the dialog was even asked for.
      expect(
        storage.documents.containsKey(
          recoveryPathFor(null, sessionId: 'crash-test-session'),
        ),
        isTrue,
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      // Mutation: read `command.says` ("rename to ...") instead of
      // `command.name` ("rename") for the crash log. `says` carries whatever
      // a person typed as an argument, which is not a stable label a bug
      // report should be filtered or grouped by.
      expect(find.textContaining('Command: rename'), findsOneWidget);
      expect(
        find.textContaining('Recent commands: rename, rename'),
        findsOneWidget,
      );
    },
  );

  testWidgets('no open document: the dialog still shows, with nothing to log', (
    WidgetTester tester,
  ) async {
    final storage = FakeBinaryStorage();
    final navigatorKey = GlobalKey<NavigatorState>();

    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(
        handleCrash(
          error: details.exception,
          stackTrace: details.stack ?? StackTrace.current,
          cubit: null,
          storage: storage,
          sessionId: 'crash-test-session',
          environment: 'Flutter, test',
          dialogContext: () => navigatorKey.currentContext,
        ),
      );
    };

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => throw StateError('no document was open yet'),
              child: const Text('crash'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('crash'));
    await tester.pumpAndSettle();

    expect(storage.documents, isEmpty);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('Command:'), findsNothing);
  });

  // `ux-01`: the live run ended a session in which not one autosave had been
  // written, and this dialog still said "an emergency autosave was written".
  testWidgets('a write that failed is said so, not promised', (
    WidgetTester tester,
  ) async {
    const report = CrashReport(error: 'boom', stackTrace: StackTrace.empty);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: CrashDialog(
            report: report,
            environment: 'Flutter, test',
            autosaved: false,
          ),
        ),
      ),
    );

    // Mutation: keep the one unconditional sentence. The dialog then makes
    // the promise on the day it is false, which is the whole finding.
    expect(find.textContaining('could not be written'), findsOneWidget);
    expect(find.textContaining('save your work now'), findsOneWidget);
    expect(find.textContaining('should not be lost'), findsNothing);
  });

  testWidgets('and a write that landed still says so', (
    WidgetTester tester,
  ) async {
    const report = CrashReport(error: 'boom', stackTrace: StackTrace.empty);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: CrashDialog(report: report, environment: 'Flutter, test'),
        ),
      ),
    );

    expect(find.textContaining('should not be lost'), findsOneWidget);
  });

  testWidgets('a storage that refuses reaches the dialog as the honest text', (
    WidgetTester tester,
  ) async {
    final cubit = opened();
    final storage = FakeBinaryStorage()..refuse = true;
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: navigatorKey,
        home: const Scaffold(),
      ),
    );

    // Not awaited: `handleCrash` only returns once the dialog it shows has
    // been dismissed, and dismissing it is what this test does last.
    unawaited(
      handleCrash(
        error: 'boom',
        stackTrace: StackTrace.empty,
        cubit: cubit,
        storage: storage,
        sessionId: 'crash-test-session',
        environment: 'Flutter, test',
        dialogContext: () => navigatorKey.currentContext,
      ),
    );
    await tester.pumpAndSettle();

    // Mutation: ignore what `emergencyAutosave` answered and pass `true`.
    // The document really is not in the storage, and the dialog says it is.
    expect(storage.documents, isEmpty);
    expect(find.textContaining('could not be written'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
  });

  // `ux-08`: an assert thrown from a build throws again on the next build,
  // and the next. The live run got a crash dialog per frame stacked over a
  // black window, with Dismiss unable to keep up.
  testWidgets('the same error twice shows one dialog', (
    WidgetTester tester,
  ) async {
    resetCrashDialogMemory();
    addTearDown(resetCrashDialogMemory);
    final cubit = opened();
    final storage = FakeBinaryStorage();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: navigatorKey,
        home: const Scaffold(),
      ),
    );

    Future<void> crash(Object error) async {
      unawaited(
        handleCrash(
          error: error,
          stackTrace: StackTrace.empty,
          cubit: cubit,
          storage: storage,
          sessionId: 'crash-test-session',
          environment: 'Flutter, test',
          dialogContext: () => navigatorKey.currentContext,
        ),
      );
      await tester.pumpAndSettle();
    }

    await crash('the same assert');
    await crash('the same assert');
    await crash('the same assert');

    // Mutation: show one per call, which is what this did. Three dialogs
    // stack, and the count below reads three.
    expect(find.text('Something went wrong'), findsOne);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('and a different error still gets its own', (
    WidgetTester tester,
  ) async {
    resetCrashDialogMemory();
    addTearDown(resetCrashDialogMemory);
    final cubit = opened();
    final storage = FakeBinaryStorage();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: navigatorKey,
        home: const Scaffold(),
      ),
    );

    Future<void> crash(Object error) async {
      unawaited(
        handleCrash(
          error: error,
          stackTrace: StackTrace.empty,
          cubit: cubit,
          storage: storage,
          sessionId: 'crash-test-session',
          environment: 'Flutter, test',
          dialogContext: () => navigatorKey.currentContext,
        ),
      );
      await tester.pumpAndSettle();
    }

    await crash('the first problem');
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    await crash('a different problem');

    // Mutation: fold on any second crash rather than on the same one. The
    // second, unrelated fault is then silent, which is worse than a stack of
    // dialogs — a person is left with a window that quietly stopped working.
    expect(find.textContaining('a different problem'), findsOne);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
  });

  test('describe() puts the command and the trail in one paragraph', () {
    const report = CrashReport(
      error: 'boom',
      stackTrace: StackTrace.empty,
      commandThatThrew: 'extrude',
      recentCommands: <String>['moveBy', 'rename'],
    );

    final said = report.describe();

    expect(said, contains('boom'));
    expect(said, contains('Command: extrude'));
    expect(said, contains('Recent commands: moveBy, rename'));
  });

  test('an empty trail is left out rather than printed as nothing', () {
    const report = CrashReport(error: 'boom', stackTrace: StackTrace.empty);

    expect(report.describe(), isNot(contains('Recent commands')));
    expect(report.describe(), isNot(contains('Command:')));
  });
}
