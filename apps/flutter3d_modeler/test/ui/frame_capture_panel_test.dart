/// `gfx-70n`'s editor half: the panel a reader walks a capture with.
///
///     flutter test test/ui/frame_capture_panel_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/frame_capture_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A capture with one working pass, one black one and one that could not be
/// read — the three things the panel has to tell apart.
FrameCapture _capture() {
  ByteData filled(int value) {
    final bytes = Uint8List(4 * 4 * 4);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = value;
    }
    return ByteData.sublistView(bytes);
  }

  return FrameCapture(
    width: 4,
    height: 4,
    passes: <CapturedPass>[
      CapturedPass(
        name: 'scene',
        active: true,
        reads: const <String>['shadow map'],
        optionalReads: const <String>[],
        writes: const <String>['hdr colour'],
        keeps: const <String>[],
        images: <CapturedImage>[
          CapturedImage(
            resource: 'hdr colour',
            width: 4,
            height: 4,
            format: TextureFormat.r8g8b8a8UNormInt,
            pixels: filled(200),
          ),
        ],
      ),
      CapturedPass(
        name: 'bloom',
        active: true,
        reads: const <String>['hdr colour'],
        optionalReads: const <String>[],
        writes: const <String>['bloom'],
        keeps: const <String>[],
        images: <CapturedImage>[
          CapturedImage(
            resource: 'bloom',
            width: 4,
            height: 4,
            format: TextureFormat.r8g8b8a8UNormInt,
            pixels: filled(0),
          ),
        ],
      ),
      const CapturedPass(
        name: 'depth prepass',
        active: true,
        reads: <String>[],
        optionalReads: <String>[],
        writes: <String>['depth'],
        keeps: <String>[],
        images: <CapturedImage>[
          CapturedImage(
            resource: 'depth',
            width: 4,
            height: 4,
            format: TextureFormat.r8g8b8a8UNormInt,
            refused: 'tile memory',
          ),
        ],
      ),
      const CapturedPass(
        name: 'light shafts',
        active: false,
        reads: <String>[],
        optionalReads: <String>[],
        writes: <String>[],
        keeps: <String>[],
        images: <CapturedImage>[],
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  FrameCapture? capture,
  bool waiting = false,
  VoidCallback? onCapture,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: FrameCapturePanel(
        capture: capture,
        waiting: waiting,
        onCapture: onCapture ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('with nothing captured it says so', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('Nothing captured yet'), findsOneWidget);
    expect(find.text('Capture a frame'), findsOneWidget);
  });

  testWidgets('while waiting the button is out of reach', (
    WidgetTester tester,
  ) async {
    // A second request replaces the first, so offering the button twice would
    // quietly throw away the capture somebody is waiting for.
    var asked = 0;
    await _pump(tester, waiting: true, onCapture: () => asked++);

    expect(find.text('Capturing…'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(asked, 0);
  });

  testWidgets('a capture lists its passes, reads and writes', (
    WidgetTester tester,
  ) async {
    await _pump(tester, capture: _capture());

    expect(find.text('scene · 1 images'), findsOneWidget);
    expect(find.text('reads shadow map'), findsOneWidget);
    expect(find.text('writes hdr colour'), findsOneWidget);
  });

  testWidgets('and points at the pass whose output came back black', (
    WidgetTester tester,
  ) async {
    // **The whole reason the panel exists.** The scene pass wrote something and
    // the bloom pass wrote black, so the reader's eye goes to bloom without
    // reading the code.
    await _pump(tester, capture: _capture());

    expect(find.text('bloom came back black'), findsOneWidget);
    expect(find.text('hdr colour came back black'), findsNothing);
  });

  testWidgets('a resource it could not read says why', (
    WidgetTester tester,
  ) async {
    // A gap in a capture is worse than no capture: the reader assumes the pass
    // wrote nothing.
    await _pump(tester, capture: _capture());

    expect(find.text('depth: tile memory'), findsOneWidget);
  });

  testWidgets('and a pass that did not run says that instead', (
    WidgetTester tester,
  ) async {
    // An inactive pass with no images is the ordinary case, not a missing one.
    await _pump(tester, capture: _capture());

    expect(find.text('light shafts · did not run'), findsOneWidget);
  });
}
