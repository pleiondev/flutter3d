/// A file dragged onto the desktop window — `ui-31n`'s macOS half.
///
///     flutter test test/file_drop_io_test.dart
///
/// **Driven through the real `desktop_drop` channel, not a fake of it.**
/// `DesktopDrop` registers a `MethodChannel('desktop_drop')` handler for
/// calls the native side makes; sending it the same two calls a real drop
/// delivers — `entered` then `performOperation` — exercises the plugin's own
/// dispatch and this file's `FileDropZone` together, reading a real file off
/// disk the way a dropped one would be.
///
/// **What this cannot reach: the native half beneath the channel.** A
/// platform actually noticing a file dragged onto a window and calling this
/// channel in the first place needs a real window and a person's hand — see
/// `integration_test/` for the one place this repository checks a claim
/// against the real platform rather than a simulated one. Nothing here
/// stands in for that; it proves the Dart side of the wire does what a drop
/// arriving on it should.
library;

import 'dart:io';

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_modeler/src/files/file_drop_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  // Before anything below reaches for a binary messenger — the same order
  // `android_test.dart`'s own channel group already needs it in.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('file_drop_io_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  const channel = MethodChannel('desktop_drop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// One call on the channel `DesktopDrop.instance.init()` listens on — the
  /// shape the native plugin side sends, not a shortcut into this package's
  /// own listener list.
  Future<void> send(String method, Object? arguments) async {
    final message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await messenger.handlePlatformMessage(channel.name, message, (_) {});
  }

  testWidgets('a file dropped on the window reaches onDropped with its bytes', (
    WidgetTester tester,
  ) async {
    final file = File('${dir.path}/helmet.glb')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final dropped = <(String, Uint8List)>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FileDropZone(
          onDropped: (String name, Uint8List bytes) =>
              dropped.add((name, bytes)),
          child: const SizedBox.expand(),
        ),
      ),
    );

    // `runAsync`, because reading the dropped file is real `dart:io`, not a
    // microtask `pump` alone would let finish.
    await tester.runAsync(() async {
      // A pointer has to enter the drop target before `desktop_drop` itself
      // will report a drop inside it — see `_DropTargetState._onDropEvent`.
      await send('entered', <double>[10, 10]);
      await send('performOperation', <String>[file.path]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(dropped, hasLength(1));
    expect(dropped.single.$1, 'helmet.glb');
    expect(dropped.single.$2, Uint8List.fromList(<int>[1, 2, 3, 4]));
  });

  testWidgets('a drop outside the target is not reported', (
    WidgetTester tester,
  ) async {
    final file = File('${dir.path}/helmet.glb')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final dropped = <(String, Uint8List)>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Column(
          children: <Widget>[
            SizedBox(
              height: 100,
              child: FileDropZone(
                onDropped: (String name, Uint8List bytes) =>
                    dropped.add((name, bytes)),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.runAsync(() async {
      // Mutation: drop this guard and every file dragged anywhere onto the
      // window — including over a menu that happens to sit outside the
      // zone in some future layout — opens as if it landed on the target.
      await send('entered', <double>[10, 500]);
      await send('performOperation', <String>[file.path]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(dropped, isEmpty);
  });

  group('tut-17: a drop actually opens as the document', () {
    /// [ModelerScreen]'s own autosave slot — never read from in this group,
    /// since nothing here writes to it before a drop, but `initState` reads
    /// it once on startup regardless (`_offerRecovery`), so a real
    /// filesystem or IndexedDB is not something this test should need.
    final storage = _NullBinaryStorage();

    testWidgets(
      'dropping a project file replaces the open document, the same as '
      'choosing it through Open would',
      (WidgetTester tester) async {
        final project = const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'dropped-cube',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
          ),
        );
        final file = File('${dir.path}/dropped.f3dproj')
          ..writeAsBytesSync(writeProject(project));

        // Wide enough for `LayoutClass.desktop` — `ui-05`'s own 1200-pixel
        // boundary — since the document-name label this test reads is
        // `ModelerShell`'s own, and the narrower tablet and phone shells
        // do not draw it at all.
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ModelerScreen(autosaveStorage: storage),
          ),
        );

        // `_open()`'s own `openDevice()` is genuine async work — the same
        // software-rasteriser fallback `flutter3d_app`'s own
        // `backend_choice_test.dart` proves a headless `flutter test`
        // takes — so this needs the real event loop `runAsync` opens
        // rather than a synchronous `pump`.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();

        // The startup document, before anything is dropped — the sanity
        // check that makes the assertion below mean something: a drop that
        // silently did nothing would leave this exact label on screen (the
        // outliner's own single row for the startup cube is a second
        // "cube" text, so this only checks presence, not count).
        expect(find.text('cube'), findsWidgets);

        await tester.runAsync(() async {
          // A pointer has to enter the drop target before `desktop_drop`
          // itself will report a drop inside it — the same order
          // `file_drop_io_test.dart`'s own first test already needs.
          await send('entered', <double>[10, 10]);
          await send('performOperation', <String>[file.path]);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // The top bar's own document-name label — `ui/shell.dart`'s own
        // `Text(isDirty ? '• $documentName' : documentName)` — is the one
        // place on screen that names the open document. Before `tut-17`'s
        // fix, `_handleDroppedFile` awaited the same decode-and-import-
        // screen step `_openFile` runs and then discarded what came back:
        // the file decoded, the document on screen never changed, and this
        // would still read the startup document's own name instead.
        expect(find.text('dropped.f3dproj'), findsOneWidget);
      },
    );
  });
}

/// Answers every read with nothing and every write as if it landed —
/// `ModelerScreen`'s own autosave writes through this during the test
/// instead of reaching for a real file or IndexedDB.
final class _NullBinaryStorage implements BinaryStorage {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<bool> write(String name, Uint8List contents) async => true;

  @override
  Future<void> remove(String name) async {}
}
