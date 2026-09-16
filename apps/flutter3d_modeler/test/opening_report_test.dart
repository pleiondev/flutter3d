/// `ux-30`: the "opened in N ms" card is a greeting, and it leaves.
///
///     flutter test test/opening_report_test.dart
///
/// **Driven through the real screen, because the bug was that nothing ever
/// took it away.** A widget test over `MeasurementReportOverlay` alone would
/// have passed for the whole of the time the card was sitting over every
/// model anybody opened: the overlay was always right, and the state behind
/// it never changed again.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_modeler/src/app_config.dart' show kOpeningReportFor;
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings in memory, already past Quick Setup — a first launch would open
/// that over the editor and this test is about what is underneath it.
final class _Settled implements Storage {
  final Map<String, String> documents = <String, String>{
    SettingsStore.name: jsonEncode(
      const ModelerSettings(
        quickSetupDone: true,
        showHomeAtLaunch: false,
      ).toJson(),
    ),
  };

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// Nothing to recover, so no dialog over the editor.
final class _NoAutosave implements BinaryStorage {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<bool> write(String name, Uint8List contents) async => true;

  @override
  Future<void> remove(String name) async {}
}

void main() {
  /// Launches the editor and waits for the device the software rasteriser
  /// stands in for — real asynchronous work, hence `runAsync`.
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ModelerScreen(
          autosaveStorage: _NoAutosave(),
          settingsStorage: _Settled(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  testWidgets('it says how long the open took, and then stops saying it', (
    WidgetTester tester,
  ) async {
    await launch(tester);

    expect(
      find.textContaining('opened in'),
      findsOneWidget,
      reason: 'the opening cost should be shown at all',
    );

    // Just short of the promise, so this fails on a card that leaves early
    // as well as on one that never leaves.
    await tester.pump(kOpeningReportFor - const Duration(milliseconds: 100));
    expect(find.textContaining('opened in'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));

    // **The acceptance the row states.** Mutation: set the field and start
    // no timer, which is what this did — the card then sat over the top-left
    // corner of the model for the whole session, and into every screenshot
    // anybody took of it.
    expect(find.textContaining('opened in'), findsNothing);
  });

  testWidgets('and the card is gone for good, not hidden for a frame', (
    WidgetTester tester,
  ) async {
    await launch(tester);
    await tester.pump(kOpeningReportFor + const Duration(milliseconds: 100));

    for (var each = 0; each < 5; each++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('opened in'), findsNothing);
    }
  });
}
