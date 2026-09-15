/// `LodScreen`: three thirds of one object, each at a different level of
/// detail — `pro-lod-04`'s own row, "Screen 17". Absorbs `view-20`.
///
///     flutter test test/ui/lod_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/lod_screen.dart';
import 'package:flutter3d_modeler/src/ui/lod_zone_bar.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A sphere with enough triangles that three different [LodSpec] ratios
/// actually land on three different triangle counts, unlike a cuboid's
/// twelve — `simplifyMeshWithAttributes` hands a mesh back unchanged the
/// moment its own triangle count is already at or under what was asked for.
MeshData _testMesh() => const SphereShape(segments: 24, rings: 12).build();

ModelObject _objectWith(List<LodSpec> lods) => ModelObject(
  id: 1,
  name: 'subject',
  geometry: ImportedGeometry(_testMesh()),
  transform: vm.Matrix4.identity(),
  lods: lods,
);

const List<LodSpec> _threeLevels = <LodSpec>[
  LodSpec(ratio: 1.0, maxScreenFraction: 1.0),
  LodSpec(ratio: 0.5, maxScreenFraction: 0.4),
  LodSpec(ratio: 0.15, maxScreenFraction: 0.1),
];

Future<void> show(
  WidgetTester tester, {
  required ModelObject object,
  required LodMeshCache cache,
  required LodViewportBuilder viewportBuilder,
  void Function(int lodIndex, double maxScreenFraction)? onThresholdChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: LodScreen(
        object: object,
        cache: cache,
        viewportBuilder: viewportBuilder,
        onThresholdChanged: onThresholdChanged ?? (_, _) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows three viewport slots, each labelled distinctly', (
    WidgetTester tester,
  ) async {
    final object = _objectWith(_threeLevels);
    final cache = LodMeshCache();

    await show(
      tester,
      object: object,
      cache: cache,
      viewportBuilder: (BuildContext context, int lodIndex, MeshData? mesh) =>
          Container(key: ValueKey<String>('pane-$lodIndex')),
    );

    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey<String>('lod-viewport-$i')), findsOneWidget);
      expect(find.byKey(ValueKey<String>('pane-$i')), findsOneWidget);
    }

    // Distinct captions — the ratio each level actually asks for, not a bare
    // "LOD n" that would read the same for every third.
    expect(find.text('LOD 0 · 100%'), findsOneWidget);
    expect(find.text('LOD 1 · 50%'), findsOneWidget);
    expect(find.text('LOD 2 · 15%'), findsOneWidget);
  });

  testWidgets(
    'hands each slot a different, verifiably different mesh — the three '
    'thirds actually differ',
    (WidgetTester tester) async {
      final object = _objectWith(_threeLevels);
      final cache = LodMeshCache();
      final Map<int, int?> triangleCounts = <int, int?>{};

      await show(
        tester,
        object: object,
        cache: cache,
        viewportBuilder: (BuildContext context, int lodIndex, MeshData? mesh) {
          triangleCounts[lodIndex] = mesh?.triangleCount;
          return const SizedBox.shrink();
        },
      );

      expect(triangleCounts.length, 3);
      expect(triangleCounts.values.every((int? c) => c != null), isTrue);
      // Coarser levels ask for fewer triangles, and the real simplifier
      // (`LodMeshCache.meshFor` → `simplifyMeshWithAttributes`) delivers
      // fewer for each — this is the "three thirds look visibly different"
      // acceptance, checked the way a widget test can check it.
      final int lod0 = triangleCounts[0]!;
      final int lod1 = triangleCounts[1]!;
      final int lod2 = triangleCounts[2]!;
      expect(<int>{lod0, lod1, lod2}.length, 3);
      expect(lod1, lessThan(lod0));
      expect(lod2, lessThan(lod1));
    },
  );

  testWidgets('a level nothing has been asked for yet still gets a slot', (
    WidgetTester tester,
  ) async {
    // Only two levels configured; the screen still draws its default three
    // thirds, and the third slot gets no mesh rather than throwing.
    final object = _objectWith(_threeLevels.take(2).toList());
    final cache = LodMeshCache();
    MeshData? thirdSlotMesh;
    var thirdSlotCalled = false;

    await show(
      tester,
      object: object,
      cache: cache,
      viewportBuilder: (BuildContext context, int lodIndex, MeshData? mesh) {
        if (lodIndex == 2) {
          thirdSlotCalled = true;
          thirdSlotMesh = mesh;
        }
        return const SizedBox.shrink();
      },
    );

    expect(find.text('LOD 2'), findsOneWidget);
    expect(thirdSlotCalled, isTrue);
    expect(thirdSlotMesh, isNull);
  });

  testWidgets('the zone bar underneath reflects the object\'s own levels', (
    WidgetTester tester,
  ) async {
    final object = _objectWith(_threeLevels);
    final cache = LodMeshCache();

    await show(
      tester,
      object: object,
      cache: cache,
      viewportBuilder: (BuildContext context, int lodIndex, MeshData? mesh) =>
          const SizedBox.shrink(),
    );

    expect(
      find.descendant(
        of: find.byType(LodZoneBar),
        matching: find.byType(GestureDetector),
      ),
      findsNWidgets(3),
    );
  });
}
