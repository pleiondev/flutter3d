/// `pro-uv-07`'s own UV-layout painter: sized at the acceptance's own
/// 400×400, and a tap that names the triangle and island it landed on.
///
///     flutter test test/ui/uv_layout_view_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/uv_layout_view.dart';
import 'package:flutter3d_modeler/src/uv_unwrap_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// One small right triangle near the UV square's own bottom-left corner, one
/// near its own top-right — far enough apart that a tap at either one's own
/// centroid cannot land on an edge or inside the other.
List<UvIslandData> _twoIslands() => <UvIslandData>[
  const UvIslandData(
    id: 0,
    faceCount: 1,
    stretch: 1.0,
    triangles: <UvTriangle>[
      UvTriangle(Offset(0, 0), Offset(0.4, 0), Offset(0, 0.4)),
    ],
  ),
  const UvIslandData(
    id: 1,
    faceCount: 1,
    stretch: 10.0,
    triangles: <UvTriangle>[
      UvTriangle(Offset(0.6, 0.6), Offset(1, 0.6), Offset(0.6, 1)),
    ],
  ),
];

/// [MaterialApp.home] alone gives its child the *screen's* own tight
/// constraints, which would stretch a 400×400 view to fill it — `Center`
/// loosens that the way any real caller's layout already does (`UvScreen`'s
/// own `Center` around this same widget).
Widget _harness(UvLayoutView view) => MaterialApp(home: Center(child: view));

void main() {
  testWidgets('paints at the acceptance\'s own 400×400', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_harness(UvLayoutView(islands: _twoIslands())));

    expect(tester.getSize(find.byType(UvLayoutView)), const Size(400, 400));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('a tap inside a triangle reports its own island and index', (
    WidgetTester tester,
  ) async {
    int? tappedIsland;
    int? tappedTriangle;
    await tester.pumpWidget(
      _harness(
        UvLayoutView(
          islands: _twoIslands(),
          onTriangleTap: (int islandId, int triangleIndex) {
            tappedIsland = islandId;
            tappedTriangle = triangleIndex;
          },
        ),
      ),
    );

    // The centroid of island 1's own triangle, (0.7333, 0.7333) in UV space
    // — the painter flips V, so that lands at local (293.3, 106.7).
    final topLeft = tester.getTopLeft(find.byType(UvLayoutView));
    await tester.tapAt(topLeft + const Offset(293.3, 106.7));
    await tester.pump();

    expect(tappedIsland, 1);
    expect(tappedTriangle, 0);
  });

  testWidgets('a tap outside every triangle reports nothing', (
    WidgetTester tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      _harness(
        UvLayoutView(
          islands: _twoIslands(),
          onTriangleTap: (_, _) => called = true,
        ),
      ),
    );

    // UV (0.5, 0.5) sits in the gap this fixture leaves between the two
    // triangles.
    final topLeft = tester.getTopLeft(find.byType(UvLayoutView));
    await tester.tapAt(topLeft + const Offset(200, 200));
    await tester.pump();

    expect(called, isFalse);
  });

  testWidgets('with no callback, the picture is not wrapped in a tap target', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_harness(UvLayoutView(islands: _twoIslands())));

    expect(
      find.descendant(
        of: find.byType(UvLayoutView),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });
}
