/// `WeightPaintPanel`: `anim-12`'s own screen 13 right panel.
///
///     flutter test test/ui/weight_paint_panel_test.dart
library;

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/ui/weight_paint_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A cube whose vertex 0 splits between both joints and whose other seven
/// vertices belong wholly to the first — enough for both the influences
/// card and the bone list's own vertex counts to say something different
/// from each other.
EditMesh _skinnedCube() {
  final mesh = EditMesh.cuboid();
  mesh.beginStep();
  mesh.setSkin(
    0,
    VertexAttributes(
      joints: Vector4(0, 1, 0, 0),
      weights: Vector4(0.75, 0.25, 0, 0),
    ),
  );
  for (var v = 1; v < mesh.vertexSlotCount; v++) {
    mesh.setSkin(
      v,
      VertexAttributes(
        joints: Vector4(0, 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      ),
    );
  }
  mesh.endStep();
  return mesh;
}

final List<ModelObject> _objects = <ModelObject>[
  ModelObject(
    id: 1,
    name: 'Hip.L',
    geometry: const SocketGeometry(),
    transform: Matrix4.identity(),
  ),
  ModelObject(
    id: 2,
    name: 'Hip.R',
    geometry: const SocketGeometry(),
    transform: Matrix4.identity(),
  ),
];

final ProjectSkeleton _skeleton = ProjectSkeleton(
  joints: <int>[1, 2],
  inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
);

Future<void> _pump(
  WidgetTester tester, {
  PaintWeightsMode mode = PaintWeightsMode.paint,
  ValueChanged<PaintWeightsMode>? onModeChanged,
  double radius = 48,
  ValueChanged<double>? onRadiusChanged,
  double strength = 1.0,
  ValueChanged<double>? onStrengthChanged,
  bool mirror = false,
  ValueChanged<bool>? onMirrorChanged,
  bool normalize = true,
  ValueChanged<bool>? onNormalizeChanged,
  ProjectSkeleton? skeleton,
  EditMesh? mesh,
  int? selectedVertex,
  int? selectedJoint,
  ValueChanged<int>? onSelectJoint,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: WeightPaintPanel(
          mode: mode,
          onModeChanged: onModeChanged ?? (_) {},
          radius: radius,
          onRadiusChanged: onRadiusChanged ?? (_) {},
          strength: strength,
          onStrengthChanged: onStrengthChanged ?? (_) {},
          mirror: mirror,
          onMirrorChanged: onMirrorChanged ?? (_) {},
          normalize: normalize,
          onNormalizeChanged: onNormalizeChanged ?? (_) {},
          objects: _objects,
          skeleton: skeleton ?? _skeleton,
          mesh: mesh,
          selectedVertex: selectedVertex,
          selectedJoint: selectedJoint,
          onSelectJoint: onSelectJoint,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('radius and strength show the values handed in', (tester) async {
    await _pump(tester, radius: 48, strength: 1.0);

    // `RangeSliderField`'s own non-editable read-out: two decimals always.
    expect(find.text('48.00'), findsOneWidget);
    expect(find.text('1.00'), findsOneWidget);
  });

  testWidgets('pressing Assign reports the mode change', (tester) async {
    PaintWeightsMode? reported;
    await _pump(tester, onModeChanged: (m) => reported = m);

    await tester.tap(find.text('Assign'));
    await tester.pump();

    expect(reported, PaintWeightsMode.assign);
  });

  testWidgets('the mirror checkbox reports its own toggle', (tester) async {
    bool? reported;
    await _pump(tester, mirror: false, onMirrorChanged: (v) => reported = v);

    await tester.tap(
      find.byKey(const ValueKey<String>('weightMirrorCheckbox')),
    );
    await tester.pump();

    expect(reported, isTrue);
  });

  testWidgets('the normalize checkbox reports its own toggle', (tester) async {
    bool? reported;
    await _pump(
      tester,
      normalize: true,
      onNormalizeChanged: (v) => reported = v,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('weightNormalizeCheckbox')),
    );
    await tester.pump();

    expect(reported, isFalse);
  });

  testWidgets('with no vertex under the brush yet, the card says so', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('No vertex under the brush yet'), findsOneWidget);
  });

  testWidgets("the selected vertex shows each bone it is bound to, by name", (
    tester,
  ) async {
    await _pump(tester, mesh: _skinnedCube(), selectedVertex: 0);

    // Both names show twice — once in this card, once in the bone list
    // below it — so it is the weight values that prove the influences card
    // itself rendered rather than only the (always-present) bone list.
    expect(find.text('Hip.L'), findsNWidgets(2));
    expect(find.text('Hip.R'), findsNWidgets(2));
    expect(find.text('0.75'), findsOneWidget);
    expect(find.text('0.25'), findsOneWidget);
  });

  testWidgets('the bone list shows how many vertices each bone influences', (
    tester,
  ) async {
    await _pump(tester, mesh: _skinnedCube());

    // Every one of the cube's eight vertices carries Hip.L; only the split
    // vertex also carries Hip.R.
    expect(find.text('8 v.'), findsOneWidget);
    expect(find.text('1 v.'), findsOneWidget);
  });

  testWidgets('tapping a bone row reports its own joint id', (tester) async {
    int? reported;
    await _pump(tester, onSelectJoint: (id) => reported = id);

    await tester.tap(find.text('Hip.R'));
    await tester.pump();

    expect(reported, 2);
  });

  testWidgets('with no skeleton bound yet, the bone list says so', (
    tester,
  ) async {
    await _pump(
      tester,
      skeleton: ProjectSkeleton(
        joints: const <int>[],
        inverseBindMatrices: const <Matrix4>[],
      ),
    );

    expect(find.text('No bones'), findsOneWidget);
  });
}
