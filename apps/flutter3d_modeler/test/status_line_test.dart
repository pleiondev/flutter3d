/// The strip along the bottom, and what colour it says things in.
///
///     flutter test test/status_line_test.dart
///
/// **These are the questions that went unasked while it was private.** What
/// colour a warning shows in, whether a quad is visible before somebody opens
/// the export dialogue, and whether a million triangles reads as a number — all
/// of them needed a pumped shell to answer, so none of them was answered.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/status_line.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A project of one cuboid: six quads, which the readiness calls a warning
/// because a format that holds triangles has no room for them.
ModelProject withQuads() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'box',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: vm.Matrix4.identity(),
  ),
);

/// A project of one object with no faces: an error, because some loaders
/// refuse an empty mesh and the rest draw nothing.
ModelProject withNothing() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'ghost',
    geometry: EditedGeometry(EditMesh.empty()),
    transform: vm.Matrix4.identity(),
  ),
);

Future<void> show(
  WidgetTester tester,
  ExportReadiness readiness, {
  int triangles = 12,
  String said = 'ready',
  VoidCallback? onExport,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: StatusLine(
        said: said,
        readiness: readiness,
        triangles: triangles,
        onExport: onExport,
      ),
    ),
  ),
);

Color colourOf(WidgetTester tester, String startsWith) {
  final text = tester.widget<Text>(
    find.byWidgetPredicate(
      (Widget w) => w is Text && (w.data ?? '').startsWith(startsWith),
    ),
  );
  return text.style!.color!;
}

void main() {
  group('how loudly it says it', () {
    test('a clean project is quiet', () {
      expect(
        StatusTone.of(ExportReadiness.check(const ModelProject())),
        StatusTone.quiet,
      );
    });

    test('a quad is a warning rather than nothing', () {
      // Mutation: colour only refusals, which is what this did. A model full of
      // n-gons reads exactly like a clean one, and the first anybody hears of
      // it is the export dialogue — which is the moment this bar exists to come
      // before.
      expect(
        StatusTone.of(ExportReadiness.check(withQuads())),
        StatusTone.warn,
      );
    });

    test('an object with no faces is a refusal', () {
      expect(
        StatusTone.of(ExportReadiness.check(withNothing())),
        StatusTone.refuse,
      );
    });
  });

  group('what colour that is', () {
    testWidgets('a warning is warm and a refusal is the error colour', (
      WidgetTester tester,
    ) async {
      await show(tester, ExportReadiness.check(withQuads()));
      final warm = colourOf(tester, 'exports with a warning');

      await show(tester, ExportReadiness.check(withNothing()));
      final bad = colourOf(tester, 'will not export');

      // Three levels, each meaning one thing. Mutation: give the warning and
      // the refusal the same colour and the bar goes back to two states, which
      // is what made a quad invisible.
      expect(warm, isNot(bad));
    });

    testWidgets('a clean project is not coloured like a warning', (
      WidgetTester tester,
    ) async {
      await show(tester, ExportReadiness.check(const ModelProject()));
      final quiet = colourOf(tester, 'ready to export');

      await show(tester, ExportReadiness.check(withQuads()));
      final warm = colourOf(tester, 'exports with a warning');

      // The old reasoning, kept: a bar that is orange whenever anything at all
      // is imperfect is a bar people stop reading. Quiet has to be quiet.
      expect(quiet, isNot(warm));
    });
  });

  group('the triangle count', () {
    test('thousands are grouped so the number can be read', () {
      // Mutation: print the integer plainly. `1240000` is a number somebody has
      // to count the digits of; `1 240 000` is one they can read at a glance,
      // which is the whole job of a figure in a status bar.
      expect(grouped(1240000), "1${thinSpace}240${thinSpace}000");
      expect(grouped(999), '999');
      expect(grouped(1000), "1${thinSpace}000");
      expect(grouped(0), '0');
    });

    test('the grouping starts from the right, not the left', () {
      // Mutation: group forwards. `12345` becomes `123 45`, which is wrong in
      // every locale and looks almost right in a screenshot.
      expect(grouped(12345), "12${thinSpace}345");
      expect(grouped(123456), "123${thinSpace}456");
      expect(grouped(1234567), "1${thinSpace}234${thinSpace}567");
    });

    testWidgets('it is on the bar, grouped', (WidgetTester tester) async {
      await show(
        tester,
        ExportReadiness.check(const ModelProject()),
        triangles: 1240000,
      );

      expect(
        find.textContaining('1${thinSpace}240${thinSpace}000'),
        findsOneWidget,
      );
    });
  });

  group("ui-10's own click", () {
    testWidgets('tapping the readiness sentence calls onExport', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await show(
        tester,
        ExportReadiness.check(withQuads()),
        onExport: () => taps++,
      );

      await tester.tap(find.textContaining('exports with a warning'));
      await tester.pump();

      // Mutation: drop the GestureDetector, or wire it to something else.
      // Either way the count stays 0 and this test is the one that notices.
      expect(taps, 1);
    });

    testWidgets('a null onExport leaves the sentence untappable', (
      WidgetTester tester,
    ) async {
      // Mutation: call onExport! unconditionally, which throws the moment a
      // caller — a test, or a screen with nowhere to send an export yet —
      // passes none.
      await show(tester, ExportReadiness.check(withQuads()));

      await tester.tap(find.textContaining('exports with a warning'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('what it says', () {
    testWidgets('the sentence is shown and does not push the rest off', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        ExportReadiness.check(const ModelProject()),
        said:
            'a very long sentence about something that just happened, '
            'long enough to want the whole bar to itself and then some more',
      );

      // The sentence gets the flexible half and ellipsises; the numbers keep
      // their room. Mutation: let the sentence size itself and a long refusal
      // pushes the triangle count and the frame time off the screen.
      expect(tester.takeException(), isNull);
      expect(find.textContaining('ready to export'), findsOneWidget);
      expect(find.textContaining('△'), findsOneWidget);
    });
  });
}
