/// The 3x3 position/rotation/scale grid.
///
///     flutter test test/transform_rows_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/transform_fields.dart';
import 'package:flutter3d_modeler/src/ui/properties/transform_rows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Nine distinct numbers, one per grid cell, so a test can tell any of them
/// apart from any other.
TransformFields fields() => (
  position: vm.Vector3(1, 2, 3),
  rotationDegrees: vm.Vector3(4, 5, 6),
  scale: vm.Vector3(7, 8, 9),
);

Future<void> show(
  WidgetTester tester,
  ValueChanged<TransformFields> onChanged,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: TransformRows(fields: fields(), onChanged: onChanged),
    ),
  ),
);

void main() {
  testWidgets('each of the nine numbers is shown, once each', (
    WidgetTester tester,
  ) async {
    await show(tester, (_) {});

    for (final String said in <String>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
    ]) {
      expect(find.text(said), findsOneWidget);
    }
  });

  testWidgets('editing one field changes only that axis', (
    WidgetTester tester,
  ) async {
    TransformFields? changed;
    await show(tester, (TransformFields to) => changed = to);

    // The first NumberField in the grid is Position X — see the header row,
    // then Position/Rotation/Scale down.
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Mutation: `_withAxis` writing to the wrong row/axis, or rebuilding all
    // nine instead of the one that actually changed.
    expect(changed?.position, vm.Vector3(50, 2, 3));
    expect(changed?.rotationDegrees, fields().rotationDegrees);
    expect(changed?.scale, fields().scale);
  });
}
