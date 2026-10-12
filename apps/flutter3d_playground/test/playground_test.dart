/// The playground opened on the software device `flutter test` has: the
/// sample drawn, a broken edit said under the text with the last good
/// document still on screen, and a fixed one drawn again.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_playground/main.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  // The frame that shows what the last turn of the loop set.
  await tester.pump();
}

Scene? _scene(WidgetTester tester) {
  final surface = find.byType(SceneSurface);
  return surface.evaluate().isEmpty
      ? null
      : tester.widget<SceneSurface>(surface).scene;
}

void main() {
  testWidgets('an edit is drawn, and a broken one is said inline', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(900, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const PlaygroundApp());
    final state = tester.state<PlaygroundState>(find.byType(Playground));

    await _settle(tester, () => state.drawn != null);
    expect(find.byType(DidNotStart), findsNothing);
    expect(state.drawn!.brushes, hasLength(4));
    expect(find.textContaining('drawn: 4 brushes'), findsOneWidget);
    final first = _scene(tester);

    // A stray comma: said with its line, and the courtyard stays.
    final document = find.byKey(const ValueKey<String>('document'));
    await tester.enterText(document, sampleLevel.replaceFirst('}', '},', 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('error: line'), findsOneWidget);
    expect(find.textContaining('still drawing'), findsOneWidget);
    expect(_scene(tester), same(first));

    // One brush fewer: drawn again.
    final fewer = sampleLevel
        .replaceFirst(
          '    { "at": [3.0, 0.25, 1.0], "size": [3.0, 0.5, 2.0], "material": "stone" }\n',
          '',
        )
        .replaceFirst('"brick" },\n  ]', '"brick" }\n  ]');
    await tester.enterText(document, fewer);
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester, () => state.drawn!.brushes.length == 3);
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('drawn: 3 brushes'), findsOneWidget);
    expect(_scene(tester), isNot(same(first)));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
