/// The minimap: a course fitted to its box, whatever size the course is.
///
///     flutter test test/mini_map_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/hud.dart';
import 'package:flutter3d_game_ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

void main() {
  const box = Size(100, 100);

  test('a course is fitted to the box, centred on its middle', () {
    MiniMapPainter painter(double scale) => MiniMapPainter(
      outline: <Vector2>[
        Vector2(0.0, 0.0) * scale,
        Vector2(10.0, 0.0) * scale,
        Vector2(10.0, 10.0) * scale,
        Vector2(0.0, 10.0) * scale,
      ],
      markers: const <Vector2>[],
    );
    for (final scale in <double>[1.0, 40.0]) {
      final map = painter(scale);
      // Mutation: draw at a fixed scale — the large course leaves the box.
      expect(map.place(Vector2(0.0, 0.0) * scale, box), const Offset(0, 0));
      expect(
        map.place(Vector2(10.0, 10.0) * scale, box),
        const Offset(100, 100),
      );
      expect(map.place(Vector2(5.0, 5.0) * scale, box), const Offset(50, 50));
    }
  });

  test('the longer side sets the scale, so a long course keeps its shape', () {
    final map = MiniMapPainter(
      outline: <Vector2>[
        Vector2(0.0, 0.0),
        Vector2(20.0, 0.0),
        Vector2(20.0, 5.0),
      ],
      markers: const <Vector2>[],
    );
    // Mutation: scale each axis on its own — the short side is stretched to
    // the box and this lands at 100 rather than 62.5.
    expect(map.place(Vector2(20.0, 5.0), box), const Offset(100, 62.5));
  });

  test('an outline with no extent places nothing', () {
    expect(
      MiniMapPainter(
        outline: <Vector2>[Vector2(1.0, 1.0)],
        markers: const <Vector2>[],
      ).place(Vector2(1.0, 1.0), box),
      isNull,
    );
    // Mutation: drop the `span <= 0` guard — a division by nought.
    expect(
      MiniMapPainter(
        outline: <Vector2>[Vector2(1.0, 1.0), Vector2(1.0, 1.0)],
        markers: const <Vector2>[],
      ).place(Vector2(1.0, 1.0), box),
      isNull,
    );
  });

  testWidgets('the map paints in its box', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MiniMap(
            outline: <Vector2>[
              Vector2(0.0, 0.0),
              Vector2(10.0, 0.0),
              Vector2(0.0, 10.0),
            ],
            markers: <Vector2>[Vector2(1.0, 1.0), Vector2(2.0, 2.0)],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MiniMap)), const Size(150, 150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the map is in the game\'s colours', (WidgetTester tester) async {
    // Mutation: type the dots' colour back into the widget and a game with a
    // palette of its own gets the engine's red on its HUD.
    const others = Color(0xFF00FF88);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<Object?>>[
            GameUiTheme(miniMapOthers: others),
          ],
        ),
        home: Center(
          child: MiniMap(
            outline: <Vector2>[Vector2(0.0, 0.0), Vector2(10.0, 0.0)],
            markers: <Vector2>[Vector2(1.0, 1.0), Vector2(2.0, 2.0)],
          ),
        ),
      ),
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(MiniMap),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as MiniMapPainter;
    expect(painter.othersColor, others);
  });
}
