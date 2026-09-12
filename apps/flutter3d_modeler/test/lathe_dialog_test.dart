/// `ui-13`'s own modal: 720 tall, three chips, a segment count that changes
/// the summary, and a live second preview.
///
///     flutter test test/lathe_dialog_test.dart
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_modeler/src/ui/lathe_dialog.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Renderer _testRenderer() {
  final it = cpuTestDevice();
  return Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
}

/// A fixed number of frames rather than [WidgetTester.pumpAndSettle] —
/// `ModelerViewport` renders every rebuild it is given, including a
/// dialog's own open/close transition frames, and `pumpAndSettle` waits for
/// *no* frame to be scheduled at all. A live render loop, embedded here on
/// purpose the way the design's own screen 09 wants a second `RenderView`,
/// never reaches that; a transition this short settles well within the
/// frames pumped here regardless.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Pumps a screen with one button that opens `showLatheDialog`, taps it
/// open and settles, and hands back the dialog's own eventual result —
/// still pending, inside a record rather than returned directly, because an
/// `async` function returning a bare `Future` flattens it: `return
/// pending;` here would make this function itself wait for the dialog to
/// close before ever returning, which is the one thing a test still has to
/// do (tap `Cancel` or `Add`) after this call comes back.
Future<({Future<LatheChoice?> result})> _open(
  WidgetTester tester,
  Renderer renderer,
) async {
  Future<LatheChoice?>? pending;
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () =>
                pending = showLatheDialog(context, renderer: renderer),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  return (result: pending!);
}

void main() {
  Future<void> withScreen(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    tester.view.physicalSize = const ui.Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await body();
  }

  testWidgets('the design\'s own screen 09: 720 tall, three chips', (
    WidgetTester tester,
  ) async {
    await withScreen(tester, () async {
      final result = (await _open(tester, _testRenderer())).result;

      final content = tester.widget<SizedBox>(
        find.byWidgetPredicate((Widget w) => w is SizedBox && w.height == 720),
      );
      expect(content.height, 720);

      for (final String label in <String>['Point', 'Curve', 'Axis']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(await result, isNull);
    });
  });

  testWidgets('changing the segment count changes the summary', (
    WidgetTester tester,
  ) async {
    await withScreen(tester, () async {
      final result = (await _open(tester, _testRenderer())).result;

      String triangleCountText() =>
          tester.widget<Text>(find.textContaining('Triangles')).data!;

      final before = triangleCountText();

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 24);
      slider.onChanged!(12);
      await tester.pump();

      final after = triangleCountText();
      expect(after, isNot(before));

      int trianglesIn(String text) =>
          int.parse(RegExp(r'Triangles (\d+)').firstMatch(text)!.group(1)!);
      // Fewer segments sweep the same profile through fewer columns, so the
      // mesh has fewer triangles, not merely a different number of them.
      expect(trianglesIn(after), lessThan(trianglesIn(before)));

      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(await result, isNull);
    });
  });

  testWidgets('Cancel closes the dialog and adds nothing', (
    WidgetTester tester,
  ) async {
    await withScreen(tester, () async {
      final result = (await _open(tester, _testRenderer())).result;

      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(await result, isNull);
    });
  });

  testWidgets('Add hands back the authored profile and segment count', (
    WidgetTester tester,
  ) async {
    await withScreen(tester, () async {
      final result = (await _open(tester, _testRenderer())).result;

      await tester.tap(find.text('Add'));
      await _settle(tester);

      final choice = await result;
      expect(choice, isNotNull);
      expect(choice!.profile.length, greaterThanOrEqualTo(2));
      expect(choice.segments, 24);
      expect(choice.closedProfile, isFalse);
    });
  });
}
