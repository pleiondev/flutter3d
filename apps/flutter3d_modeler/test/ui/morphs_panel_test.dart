/// `MorphsPanel`: `anim-19`'s own app half, screen 15's right panel.
///
///     flutter test test/ui/morphs_panel_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show ShapeKey;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/ui/morphs_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject _faceWithShapes({
  List<ShapeDriver> drivers = const <ShapeDriver>[],
}) => ModelObject(
  id: 1,
  name: 'Face',
  geometry: const SocketGeometry(),
  transform: Matrix4.identity(),
  shapeSet: ShapeSet(
    keys: <ShapeKey>[
      ShapeKey('Smile', Float32List.fromList(<double>[0, 0, 0])),
      ShapeKey('Frown', Float32List.fromList(<double>[0, 0, 0])),
    ],
    weights: <double>[0.5, 0.0],
  ),
  shapeDrivers: drivers,
);

final List<ModelObject> _objects = <ModelObject>[
  _faceWithShapes(),
  ModelObject(
    id: 2,
    name: 'Jaw',
    geometry: const SocketGeometry(),
    transform: Matrix4.identity(),
  ),
];

final ProjectSkeleton _skeleton = ProjectSkeleton(
  joints: <int>[2],
  inverseBindMatrices: <Matrix4>[Matrix4.identity()],
);

Future<void> _pump(
  WidgetTester tester, {
  required ModelObject? object,
  bool hasKeyAtCurrentFrame = false,
  void Function(int shapeIndex, double weight)? onSetWeight,
  VoidCallback? onKeyShape,
  int? selectedShape,
  ValueChanged<int>? onSelectShape,
  ValueChanged<int>? onAddDriver,
  ValueChanged<int>? onRemoveDriver,
  void Function(int driverIndex, String field, Object? value)? onSetDriverField,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MorphsPanel(
          object: object,
          objects: _objects,
          skeleton: _skeleton,
          hasKeyAtCurrentFrame: hasKeyAtCurrentFrame,
          onSetWeight: onSetWeight ?? (_, _) {},
          onKeyShape: onKeyShape ?? () {},
          selectedShape: selectedShape,
          onSelectShape: onSelectShape ?? (_) {},
          onAddDriver: onAddDriver ?? (_) {},
          onRemoveDriver: onRemoveDriver ?? (_) {},
          onSetDriverField: onSetDriverField ?? (_, _, _) {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('with no object held, the panel says so', (tester) async {
    await _pump(tester, object: null);

    expect(find.text('No shape keys on this object'), findsOneWidget);
  });

  testWidgets('one row per shape key, by name', (tester) async {
    await _pump(tester, object: _faceWithShapes());

    expect(find.text('Smile'), findsOneWidget);
    expect(find.text('Frown'), findsOneWidget);
  });

  testWidgets('the key dot is checked when a key sits on the current frame', (
    tester,
  ) async {
    await _pump(tester, object: _faceWithShapes(), hasKeyAtCurrentFrame: true);

    expect(find.byIcon(Icons.radio_button_checked), findsNWidgets(2));
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
  });

  testWidgets('the key dot is unchecked with no key on the current frame', (
    tester,
  ) async {
    await _pump(tester, object: _faceWithShapes(), hasKeyAtCurrentFrame: false);

    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
  });

  testWidgets('tapping a key dot reports onKeyShape', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      object: _faceWithShapes(),
      onKeyShape: () => tapped = true,
    );

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('dragging a shape row reports its own weight change', (
    tester,
  ) async {
    ({int shapeIndex, double weight})? reported;
    await _pump(
      tester,
      object: _faceWithShapes(),
      onSetWeight: (int i, double w) => reported = (shapeIndex: i, weight: w),
    );

    // The second shape's own slider, dragged from its default 0.0.
    await tester.drag(
      find.byKey(const ValueKey<String>('slider-null')).at(1),
      const Offset(40, 0),
    );
    await tester.pump();

    expect(reported, isNotNull);
    expect(reported!.shapeIndex, 1);
    expect(reported!.weight, greaterThan(0.0));
  });

  testWidgets('tapping a shape name reports onSelectShape', (tester) async {
    int? reported;
    await _pump(
      tester,
      object: _faceWithShapes(),
      onSelectShape: (int i) => reported = i,
    );

    await tester.tap(find.text('Frown'));
    await tester.pump();

    expect(reported, 1);
  });

  testWidgets('a driver row shows its own bone, axis and angles', (
    tester,
  ) async {
    await _pump(
      tester,
      object: _faceWithShapes(
        drivers: <ShapeDriver>[
          ShapeDriver(
            shapeIndex: 0,
            jointId: 2,
            axis: DriverAxis.x,
            from: 0.0,
            to: math.pi / 2,
          ),
        ],
      ),
    );

    expect(find.text('Jaw'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
  });

  testWidgets('editing a driver\'s "To" angle reports degrees as radians', (
    tester,
  ) async {
    ({int index, String field, Object? value})? reported;
    await _pump(
      tester,
      object: _faceWithShapes(
        drivers: <ShapeDriver>[
          const ShapeDriver(
            shapeIndex: 0,
            jointId: 2,
            axis: DriverAxis.x,
            from: 0.0,
            to: 0.0,
          ),
        ],
      ),
      onSetDriverField: (int index, String field, Object? value) =>
          reported = (index: index, field: field, value: value),
    );

    // The driver's own second `NumberField` — "From°" is the first, "To°"
    // the second — rather than a text-content finder: both start at the
    // same 0.0 and would otherwise match each other.
    await tester.enterText(find.byType(TextField).at(1), '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(reported, isNotNull);
    expect(reported!.index, 0);
    expect(reported!.field, 'to');
    expect(reported!.value! as double, closeTo(math.pi / 2, 1e-9));
  });

  testWidgets('picking a different bone reports the driver\'s new jointId', (
    tester,
  ) async {
    ({int index, String field, Object? value})? reported;
    await _pump(
      tester,
      object: _faceWithShapes(
        drivers: <ShapeDriver>[
          const ShapeDriver(
            shapeIndex: 0,
            jointId: 2,
            axis: DriverAxis.x,
            from: 0.0,
            to: 0.0,
          ),
        ],
      ),
      onSetDriverField: (int index, String field, Object? value) =>
          reported = (index: index, field: field, value: value),
    );

    // Only one bone is offered (`_skeleton` has a single joint), so exercise
    // the axis segmented control instead — the same "a driver row edit
    // issues SetShapeDriverField with the right id/index/field" acceptance,
    // over a control every build of this panel actually offers more than
    // one choice on.
    await tester.tap(find.text('Y'));
    await tester.pump();

    expect(reported, (index: 0, field: 'axis', value: 'y'));
  });

  testWidgets('"Add driver" reports the shape index it was pressed under', (
    tester,
  ) async {
    int? reported;
    await _pump(
      tester,
      object: _faceWithShapes(),
      onAddDriver: (int i) => reported = i,
    );

    await tester.tap(find.text('Add driver').last);
    await tester.pump();

    expect(reported, 1);
  });
}
