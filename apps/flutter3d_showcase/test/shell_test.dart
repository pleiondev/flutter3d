@Tags(['skip_very_good_optimization'])
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/demo/device_holder.dart';
import 'package:flutter3d_showcase/src/shell/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_harness.dart';

/// The demo behind the other tab draws every frame, so the tree never
/// settles. Pump frames, and give the asset load the real time it takes, until
/// [finder] has something to find or a few seconds have passed.
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

  testWidgets('the home page lists the pages by category', (tester) async {
    await open(tester);
    expect(find.text('The engine, one capability at a time'), findsOneWidget);
    expect(find.textContaining('PBR metal and rough'), findsWidgets);
  });

  testWidgets('search narrows the tree to what matches', (tester) async {
    // Mutation: ignore the query. Typing "shadow" would still show the PBR
    // page in the results.
    await open(tester);
    await tester.enterText(find.byType(TextField), 'cascade');
    await tester.pump();
    expect(find.text('Cascaded shadows'), findsWidgets);
    expect(find.text('PBR metal and rough'), findsNothing);
  });

  testWidgets('a page has its version tag and its three tabs', (tester) async {
    await open(tester);
    await tester.tap(find.textContaining('PBR metal and rough').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('since 0.1.0'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('Step by step'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
  });
}
