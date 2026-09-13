/// `anim-07`'s own `ConstraintsList`: rows over `ProjectSkeleton.constraints`.
///
///     flutter test test/ui/constraints_list_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/constraints_list.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

IkConstraint _arm() => IkConstraint(
  rootJointId: 1,
  midJointId: 2,
  effectorJointId: 3,
  target: vm.Vector3(1, 0, 0),
  pole: vm.Vector3(0, 1, 0),
);

IkConstraint _leg() => IkConstraint(
  rootJointId: 4,
  midJointId: 5,
  effectorJointId: 6,
  target: vm.Vector3(0, -1, 0),
  pole: vm.Vector3(0, 0, 1),
);

Future<void> _pump(
  WidgetTester tester, {
  required List<IkConstraint> constraints,
  String Function(int)? nameOf,
  int? selected,
  ValueChanged<int>? onSelect,
  ValueChanged<int>? onRemove,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ConstraintsList(
        constraints: constraints,
        nameOf: nameOf,
        selected: selected,
        onSelect: onSelect ?? (_) {},
        onRemove: onRemove,
      ),
    ),
  ),
);

void main() {
  testWidgets('no constraints says so, plainly', (tester) async {
    await _pump(tester, constraints: const <IkConstraint>[]);

    expect(find.text('No constraints'), findsOneWidget);
  });

  testWidgets('each constraint shows root, mid and effector by id when no '
      'name lookup is given', (tester) async {
    await _pump(tester, constraints: <IkConstraint>[_arm()]);

    expect(find.text('1 → 2 → 3'), findsOneWidget);
  });

  testWidgets('a nameOf callback resolves joint ids to names', (tester) async {
    const names = <int, String>{1: 'upper arm', 2: 'forearm', 3: 'hand'};
    await _pump(
      tester,
      constraints: <IkConstraint>[_arm()],
      nameOf: (int id) => names[id] ?? '$id',
    );

    expect(find.text('upper arm → forearm → hand'), findsOneWidget);
  });

  testWidgets('tapping a row reports its own index, not always zero', (
    tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      constraints: <IkConstraint>[_arm(), _leg()],
      onSelect: selected.add,
    );

    await tester.tap(find.text('4 → 5 → 6'));
    await tester.pump();

    expect(selected, <int>[1]);
  });

  testWidgets('no delete affordance appears when onRemove is not given', (
    tester,
  ) async {
    await _pump(tester, constraints: <IkConstraint>[_arm()]);

    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('onRemove is wired to the right index', (tester) async {
    final removed = <int>[];
    await _pump(
      tester,
      constraints: <IkConstraint>[_arm(), _leg()],
      onRemove: removed.add,
    );

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();

    expect(removed, <int>[1]);
  });
}
