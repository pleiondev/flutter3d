/// `tut-20`'s own "Save to cabinet": the button's own gating on
/// `CabinetLink.canSaveBack`, and what tapping it actually sends.
///
///     flutter test test/cabinet_save_test.dart
///
/// **The POST itself is a fake, not a real network call.** `ModelerScreen.
/// cabinetSourceSender` is exactly the door `autosaveStorage` already is for
/// `defaultBinaryStorage` in `file_drop_io_test.dart`: a test hands in a
/// function that records what it was asked to send and answers without
/// touching a socket. What a real browser's `fetch` actually does against a
/// real `cloud/server` — `cabinet_save_web.dart`'s own half — is not
/// something this sandbox can drive; see `file_drop_web_test.dart`'s own doc
/// comment for the identical limit on real drag-and-drop, and `cabinet_save_
/// web.dart`'s own doc comment for what it does instead.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_modeler/src/cabinet_link.dart';
import 'package:flutter3d_modeler/src/files/cabinet_save_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every read with nothing and every write as if it landed —
/// `file_drop_io_test.dart`'s own `_NullBinaryStorage`, repeated here since
/// it is private to that file.
final class _NullBinaryStorage implements BinaryStorage {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<bool> write(String name, Uint8List contents) async => true;

  @override
  Future<void> remove(String name) async {}
}

/// One call `postSourceToCabinet` was asked to make.
typedef _Sent = ({int modelId, String csrf, Uint8List bytes});

/// Pumps a [ModelerScreen] far enough that its start-up device is open and
/// the top bar is on screen — the same sequence `file_drop_io_test.dart`'s
/// own `tut-17` group already needs, for the same reason: `openDevice()` is
/// real async work a headless `flutter test` still has to fall back through,
/// and the top bar only draws past `LayoutClass.desktop`'s own 1200-pixel
/// boundary.
Future<void> _pumpReady(
  WidgetTester tester, {
  CabinetLink? cabinetLink,
  CabinetSourceSender? cabinetSourceSender,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ModelerScreen(
        autosaveStorage: _NullBinaryStorage(),
        cabinetLink: cabinetLink,
        cabinetSourceSender: cabinetSourceSender,
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
}

void main() {
  group('the "Save to cabinet" button only appears when it could succeed', () {
    testWidgets('hidden on an ordinary launch — no cabinet id at all', (
      WidgetTester tester,
    ) async {
      await _pumpReady(tester);
      expect(find.text('Save to cabinet'), findsNothing);
    });

    testWidgets('hidden when the cabinet opened this build for viewing only', (
      WidgetTester tester,
    ) async {
      await _pumpReady(
        tester,
        cabinetLink: const CabinetLink(id: 7, mode: 'view', csrf: 'tok'),
      );
      expect(find.text('Save to cabinet'), findsNothing);
    });

    testWidgets('shown with a cabinet id and mode=edit', (
      WidgetTester tester,
    ) async {
      await _pumpReady(
        tester,
        cabinetLink: const CabinetLink(id: 7, mode: 'edit', csrf: 'tok'),
      );
      expect(find.text('Save to cabinet'), findsOneWidget);
    });

    testWidgets(
      'shown with a cabinet id and no mode at all — tut-20\'s own future '
      'default, before the cabinet has an Edit link that bothers setting '
      'mode=edit explicitly',
      (WidgetTester tester) async {
        await _pumpReady(
          tester,
          cabinetLink: const CabinetLink(id: 7, mode: null, csrf: 'tok'),
        );
        expect(find.text('Save to cabinet'), findsOneWidget);
      },
    );
  });

  group('tapping "Save to cabinet"', () {
    testWidgets(
      'POSTs the open document as a real .f3dproj, with this build\'s own '
      'cabinet id and csrf, and reports success on the status line',
      (WidgetTester tester) async {
        final sent = <_Sent>[];
        Future<CabinetSaveOutcome> fakeSend({
          required int modelId,
          required String csrf,
          required Uint8List bytes,
        }) async {
          sent.add((modelId: modelId, csrf: csrf, bytes: bytes));
          return const CabinetSaveWritten();
        }

        await _pumpReady(
          tester,
          cabinetLink: const CabinetLink(id: 91, mode: 'edit', csrf: 'tok-91'),
          cabinetSourceSender: fakeSend,
        );

        await tester.tap(find.text('Save to cabinet'));
        // The fake sender resolves on a microtask, not a real socket — a
        // plain pump, not `runAsync`, is what flushes it.
        await tester.pump();
        await tester.pump();

        expect(sent, hasLength(1));
        expect(sent.single.modelId, 91);
        expect(sent.single.csrf, 'tok-91');
        // A real .f3dproj, not just "some bytes" — the same round-trip
        // `import_screen_test.dart`'s own project-file checks already lean
        // on: `writeProject`'s own bytes read back as the document they
        // came from.
        expect(isProjectFile(sent.single.bytes), isTrue);
        expect(readProject(sent.single.bytes), isA<ProjectOpened>());

        expect(
          find.textContaining('bytes to the cabinet as .f3dproj'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reports the server\'s own refusal on the status line, and sends '
      'nothing a second time on its own',
      (WidgetTester tester) async {
        final sent = <_Sent>[];
        Future<CabinetSaveOutcome> fakeSend({
          required int modelId,
          required String csrf,
          required Uint8List bytes,
        }) async {
          sent.add((modelId: modelId, csrf: csrf, bytes: bytes));
          return const CabinetSaveFailed('too many saves recently');
        }

        await _pumpReady(
          tester,
          cabinetLink: const CabinetLink(id: 4, mode: 'edit', csrf: 'tok-4'),
          cabinetSourceSender: fakeSend,
        );

        await tester.tap(find.text('Save to cabinet'));
        await tester.pump();
        await tester.pump();

        expect(sent, hasLength(1));
        expect(find.textContaining('too many saves recently'), findsOneWidget);
      },
    );
  });
}
