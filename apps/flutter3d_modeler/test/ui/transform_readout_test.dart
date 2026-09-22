/// `ux-11`'s own carried label: what it says, and that it stays on the
/// picture rather than running off the edge of it.
///
///     flutter test test/ui/transform_readout_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/transform_readout.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _picture = Size(800, 600);

Future<void> _pump(WidgetTester tester, Offset at, {String? hints}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: _picture.width,
            height: _picture.height,
            child: Stack(
              children: <Widget>[
                TransformReadout(
                  readout: 'Move · X · 0.35 m',
                  hints: hints,
                  at: at,
                  within: _picture,
                ),
              ],
            ),
          ),
        ),
      ),
    );

/// Where the label ended up, in the picture's own coordinates.
Rect _labelAt(WidgetTester tester) =>
    tester.getRect(find.text('Move · X · 0.35 m'));

void main() {
  testWidgets('it says what the transform is at', (WidgetTester tester) async {
    await _pump(tester, const Offset(100, 100));

    expect(find.text('Move · X · 0.35 m'), findsOneWidget);
  });

  testWidgets('each hint is its own chip', (WidgetTester tester) async {
    await _pump(
      tester,
      const Offset(100, 100),
      hints: 'Shift precise · Ctrl snap 0.1 m · Esc cancel',
    );

    // Mutation: draw the hints as one run of text. Three separate facts read
    // as a sentence, and the one somebody is looking for — what the modifier
    // is worth right now — is in the middle of it.
    expect(find.text('Shift precise'), findsOneWidget);
    expect(find.text('Ctrl snap 0.1 m'), findsOneWidget);
    expect(find.text('Esc cancel'), findsOneWidget);
  });

  testWidgets('it sits beside the pointer', (WidgetTester tester) async {
    await _pump(tester, const Offset(100, 100));

    final Rect label = _labelAt(tester);
    expect(label.left, greaterThan(100));
    expect(label.top, greaterThan(100));
  });

  testWidgets('and flips rather than running off the edge', (
    WidgetTester tester,
  ) async {
    // The bottom-right corner, which is exactly where a model being scaled up
    // takes the pointer.
    await _pump(tester, const Offset(780, 580));

    // Mutation: pin the label to the pointer's lower right whatever happens.
    // It leaves the picture at the one corner people drag into most, and the
    // number they were reading is simply gone.
    final Rect label = _labelAt(tester);
    expect(label.right, lessThanOrEqualTo(_picture.width));
    expect(label.bottom, lessThanOrEqualTo(_picture.height));
    expect(label.left, lessThan(780));
    expect(label.top, lessThan(580));
  });
}
