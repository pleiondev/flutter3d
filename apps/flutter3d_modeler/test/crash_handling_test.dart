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
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/crash_handling.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A storage kept in memory — the same fake `autosaving_test.dart` and
/// `main_recovery_test.dart` already use for `BinaryStorage`.
final class FakeBinaryStorage implements BinaryStorage {
  final Map<String, Uint8List> documents = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String name) async => documents[name];

  @override
  Future<bool> write(String name, Uint8List contents) async {
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
  tearDown(() {
    FlutterError.onError = defaultOnError;
    lastAttemptedCommand = null;
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
