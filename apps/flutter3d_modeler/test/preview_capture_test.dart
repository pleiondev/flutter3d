/// `tut-19`'s own preview capture: the trigger inside [_installOpened] that
/// decides whether to try at all, and what it hands to whatever actually
/// sends the picture.
///
///     flutter test test/preview_capture_test.dart
///
/// **The capture itself is a fake, not a real canvas or a real network
/// call.** `ModelerScreen.previewCapturer` is exactly the door
/// `cabinetSourceSender` already is in `cabinet_save_test.dart` — a function
/// that records what it was asked to send and answers without touching a
/// canvas or a socket. What a real browser's `canvas.toBlob()` actually
/// produces from a live WebGPU/WebGL2 surface — `preview_capture_web.dart`'s
/// own half — is not something this sandbox can drive; see that file's own
/// doc comment for what it does instead, and `cabinet_save_web.dart`'s for
/// the identical limit on a real save-back.
///
/// **Reached through the autosave-recovery dialog, not a real open.** Nothing
/// in this test harness can fetch a model over the network or pick one from
/// a folder, so [_installOpened] is driven here the one other way
/// `ModelerScreen` already lets a test reach it without either: seed
/// `autosaveStorage` with a project, accept the "Restore unsaved changes?"
/// dialog `_offerRecovery` shows on startup, and `_installOpened` runs for
/// real — camera framed, `setState` done, and `_capturePreviewIfDue` with
/// it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_modeler/src/cabinet_link.dart';
import 'package:flutter3d_modeler/src/files/preview_capture.dart';
import 'package:flutter_test/flutter_test.dart';
// Prefixed the same way `main.dart`'s own import of this package already
// is — `package:flutter/material.dart` and `vector_math` unprefixed
// disagree about which `Matrix4` a bare reference means, the same ambiguity
// `main.dart`'s own `as vm` already sidesteps.
import 'package:vector_math/vector_math.dart' as vm;

/// `main_recovery_test.dart`'s own `FakeBinaryStorage`, repeated here since
/// it is private to that file.
final class _FakeBinaryStorage implements BinaryStorage {
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

ModelProject _cube() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: vm.Matrix4.identity(),
  ),
);

/// A storage that already holds one autosave under `ModelerScreen`'s own
/// fixed session id, so `_offerRecovery` has something to offer the moment
/// the app starts.
_FakeBinaryStorage _storageWithRecovery() {
  final storage = _FakeBinaryStorage();
  // `app_wiring.dart`'s own `_kAutosaveSessionId` — private to that library,
  // so named here the same literal way `main_recovery_test.dart`'s own
  // session ids already are.
  final key = recoveryPathFor(null, sessionId: 'single-window');
  storage.documents[key] = writeProject(_cube());
  return storage;
}

/// One call the fake [PreviewCapturer] was asked to make.
typedef _Sent = ({int modelId, String sourceSha, String csrf});

/// Pumps a [ModelerScreen] through startup and past the "Restore unsaved
/// changes?" dialog `_offerRecovery` offers for the autosave
/// [_storageWithRecovery] already seeded — the same `runAsync`-then-`pump`
/// shape `cabinet_save_test.dart`'s own `_pumpReady` already needs for
/// `openDevice()`'s real async work, extended by one more settle for the
/// dialog itself and one more pump for `_capturePreviewIfDue`'s own
/// `addPostFrameCallback`.
Future<void> _pumpPastRecovery(
  WidgetTester tester, {
  required CabinetLink cabinetLink,
  PreviewCapturer? previewCapturer,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      // `RestoreAutosaveDialog` reads `AppLocalizations.of(context)` for
      // its own title, body and button label — `restore_autosave_dialog_
      // test.dart`'s own harness sets up the identical three for the same
      // reason, and pins the locale so `find.text('Restore')` means the
      // same thing regardless of the machine this runs on.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ModelerScreen(
        autosaveStorage: _storageWithRecovery(),
        cabinetLink: cabinetLink,
        previewCapturer: previewCapturer,
      ),
    ),
  );
  // Real time, not fake-async time: `openDevice()` is real async work
  // `cabinet_save_test.dart`'s own `_pumpReady` already needs 200ms of for
  // the same reason, and `_offerRecovery`'s own chain right behind it —
  // reading the fake storage, decoding the project, calling
  // `RestoreAutosaveDialog.show` — needs a slice of that same real time
  // too, so this waits longer than `_pumpReady` does.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  // Bounded pumps, never `pumpAndSettle` — `ModelerScreen`'s own render-loop
  // `Ticker` reschedules a frame every time one is drawn, the same reason
  // `cabinet_save_test.dart`'s own `_pumpReady` never calls it either.
  // `pumpAndSettle` would wait for a frame nothing schedules ever to stop
  // being scheduled. A fixed handful of frames is what the dialog's own
  // entrance transition needs instead.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(find.text('Restore'), findsOneWidget);
  await tester.tap(find.text('Restore'));
  // `_installOpened` runs synchronously off this tap; `_capturePreviewIfDue`
  // schedules the fake through `addPostFrameCallback`, which these pumps
  // flush. Real durations, not bare `pump()` calls: popping the dialog
  // starts its own exit-transition `AnimationController`/`Ticker`, and a
  // zero-duration pump never advances it — leaving that ticker running past
  // the end of this test to bleed stray frames (and this test's own name,
  // by zone) into whatever ran next in the same worker. Enough 100ms steps
  // to carry the default ~150ms Material dialog transition all the way to
  // its end is what actually retires it.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('the preview capturer is only ever asked when tut-19\'s own four '
      'conditions all hold', () {
    testWidgets(
      'called once, with this cabinet entry\'s id, source hash and csrf',
      (WidgetTester tester) async {
        final sent = <_Sent>[];
        Future<void> fakeCapture({
          required int modelId,
          required String sourceSha,
          required String csrf,
        }) async {
          sent.add((modelId: modelId, sourceSha: sourceSha, csrf: csrf));
        }

        await _pumpPastRecovery(
          tester,
          cabinetLink: const CabinetLink(
            id: 42,
            mode: 'view',
            csrf: 'tok-42',
            isOwner: true,
            sourceSha: 'sha-abc',
          ),
          previewCapturer: fakeCapture,
        );

        expect(sent, hasLength(1));
        expect(sent.single.modelId, 42);
        expect(sent.single.sourceSha, 'sha-abc');
        expect(sent.single.csrf, 'tok-42');
      },
    );

    testWidgets('never called when this viewer could not edit the model', (
      WidgetTester tester,
    ) async {
      final sent = <_Sent>[];
      Future<void> fakeCapture({
        required int modelId,
        required String sourceSha,
        required String csrf,
      }) async {
        sent.add((modelId: modelId, sourceSha: sourceSha, csrf: csrf));
      }

      await _pumpPastRecovery(
        tester,
        cabinetLink: const CabinetLink(
          id: 42,
          mode: 'view',
          csrf: 'tok-42',
          sourceSha: 'sha-abc',
        ),
        previewCapturer: fakeCapture,
      );

      expect(sent, isEmpty);
    });

    testWidgets(
      'never called for an edit-mode open — only a view-only open is safe '
      'to auto-capture from',
      (WidgetTester tester) async {
        final sent = <_Sent>[];
        Future<void> fakeCapture({
          required int modelId,
          required String sourceSha,
          required String csrf,
        }) async {
          sent.add((modelId: modelId, sourceSha: sourceSha, csrf: csrf));
        }

        await _pumpPastRecovery(
          tester,
          cabinetLink: const CabinetLink(
            id: 42,
            mode: 'edit',
            csrf: 'tok-42',
            isOwner: true,
            sourceSha: 'sha-abc',
          ),
          previewCapturer: fakeCapture,
        );

        expect(sent, isEmpty);
      },
    );

    testWidgets('never called on an ordinary launch — no cabinet id at all', (
      WidgetTester tester,
    ) async {
      final sent = <_Sent>[];
      Future<void> fakeCapture({
        required int modelId,
        required String sourceSha,
        required String csrf,
      }) async {
        sent.add((modelId: modelId, sourceSha: sourceSha, csrf: csrf));
      }

      await _pumpPastRecovery(
        tester,
        cabinetLink: CabinetLink.none,
        previewCapturer: fakeCapture,
      );

      expect(sent, isEmpty);
    });
  });
}
