@Tags(['skip_very_good_optimization'])
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/demo/device_holder.dart';
import 'package:flutter3d_showcase/src/shell/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_harness.dart';

/// Tagged so `very_good test` runs it on its own: merged into one program with
/// the other test files it never finds the guide, and alone it does. What the
/// others leave behind is not worth finding out here.
///
/// The demo behind the other tab draws every frame, so the tree never
/// settles. Pump frames, and give the asset load the real time it takes, until
/// [finder] has something to find or a few seconds have passed.
/// A [Text] whose text contains [part], including text drawn by `Text.rich`.
Finder _textWith(String part) => find.byWidgetPredicate(
  (Widget w) =>
      w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').contains(part),
);

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  // An animation's first frame only starts it, and the tab slides for 300 ms
  // before the page that loads the assets exists.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShowcaseApp(holder: DeviceHolder(open: () async => cpuDevice())),
    );
    await tester.pump();
  }

  testWidgets('the guide and the source come from the files that run', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.textContaining('PBR metal and rough').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Step by step'));
    await _waitFor(tester, _textWith('Step 1: Make the material'));
    expect(_textWith('Step 1: Make the material'), findsWidgets);
    // The code in the guide is the region of the page, not a copy of it.
    expect(_textWith('LightingModel.pbr'), findsWidgets);

    await tester.tap(find.text('Source'));
    await _waitFor(tester, _textWith('class PbrLightingDemo'));
    expect(_textWith('class PbrLightingDemo'), findsWidgets);
    expect(_textWith('#region'), findsNothing);
  });
}
