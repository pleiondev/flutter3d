/// The automap on the screen.
///
///     flutter test test/automap_view_test.dart
///
/// The painter is asked what it would draw rather than watched drawing it:
/// the scale it picks for a view, and that a view with a map in it paints
/// without throwing. What the cells look like is the map's business, held
/// in `flutter3d_sim`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// One room, 8 m square, floor and four walls.
Level _room() => Level(
  brushes: <Brush>[
    _box(4.0, -0.5, 4.0, 10.0, 1.0, 10.0),
    _box(4.0, 2.0, -0.5, 10.0, 4.0, 1.0),
    _box(4.0, 2.0, 8.5, 10.0, 4.0, 1.0),
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(8.5, 2.0, 4.0, 1.0, 4.0, 8.0),
  ],
);

void main() {
  testWidgets('draws a revealed room without complaint', (tester) async {
    final map = Automap(NavGrid.bake(_room().brushes, cellSize: 0.5))
      ..reveal(Vector3(4.0, 0.1, 4.0));
    expect(map.revealedCount, greaterThan(0));

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: AutomapView(
            automap: map,
            position: Vector3(4.0, 0.1, 4.0),
            yaw: 0.3,
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('the scale shows metresAcross on the shorter side', () {
    final painter = AutomapPainter(
      automap: Automap(NavGrid.bake(_room().brushes, cellSize: 0.5)),
      position: Vector3.zero(),
      yaw: 0.0,
      metresAcross: 40.0,
      floor: Colors.grey,
      wall: Colors.black,
      player: Colors.yellow,
      backdrop: Colors.black54,
    );

    expect(painter.scaleFor(const Size(800, 400)), 10.0);
    expect(painter.scaleFor(const Size(200, 600)), 5.0);
  });
}
