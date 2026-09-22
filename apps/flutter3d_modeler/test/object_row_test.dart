/// One line of the object list.
///
///     flutter test test/object_row_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/properties/object_row.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelObject anchor({String name = 'Hand'}) => ModelObject(
  id: 1,
  name: name,
  geometry: const SocketGeometry(),
  transform: vm.Matrix4.identity(),
);

Future<void> show(
  WidgetTester tester, {
  required ModelObject object,
  bool selected = false,
  VoidCallback? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ObjectRow(
        object: object,
        selected: selected,
        onTap: onTap ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('the object\'s own name is shown', (WidgetTester tester) async {
    await show(tester, object: anchor(name: 'Left Hand'));

    expect(find.text('Left Hand'), findsOneWidget);
  });

  testWidgets('a tap calls onTap', (WidgetTester tester) async {
    var taps = 0;
    await show(tester, object: anchor(), onTap: () => taps++);

    await tester.tap(find.byType(ObjectRow));
    await tester.pump();

    // Mutation: drop the InkWell's onTap, or wire it to nothing. Either way
    // the count stays 0, which is what this notices.
    expect(taps, 1);
  });
}
