/// What the Flame pages draw on Flame's side: a small top-down map and a line
/// of caption, so the 2D layer shows the same world the 3D one does.
///
/// **Kept out of the pages so each one is about its bridge.** A page adds the
/// bridged components to [FlameMinimap.world] and reads nothing else from here.
/// The map is scaled so a bridged component's position, in metres, lands where
/// it stands on the plane, which is what makes the two layers visibly agree.
library;

import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Rect;

import 'package:flame/components.dart';
import 'package:flutter/gestures.dart'
    show PointerMoveEvent, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/painting.dart' show Shadow, TextStyle;
import 'package:flutter/widgets.dart' show Listener, Widget;
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// A square map in the top-right corner of the game, [metres] pixels to the
/// metre, centred on the origin of the plane.
final class FlameMinimap extends PositionComponent {
  FlameMinimap({this.metres = 24.0, double side = 240.0})
    : world = PositionComponent(
        position: Vector2.all(side / 2),
        scale: Vector2.all(metres),
      ),
      super(size: Vector2.all(side));

  /// Pixels to the metre.
  final double metres;

  /// Where bridged components go: a child here is positioned in metres.
  final PositionComponent world;

  @override
  Future<void> onLoad() async {
    await add(world);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(size.x - this.size.x - 16.0, 16.0);
  }

  @override
  void render(Canvas canvas) {
    final Rect box = Rect.fromLTWH(0.0, 0.0, size.x, size.y);
    canvas.drawRect(box, Paint()..color = const Color(0xCC14161A));
    final Paint grid = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke;
    for (double x = size.x / 2 % metres; x <= size.x; x += metres) {
      canvas.drawLine(Offset(x, 0.0), Offset(x, size.y), grid);
    }
    for (double y = size.y / 2 % metres; y <= size.y; y += metres) {
      canvas.drawLine(Offset(0.0, y), Offset(size.x, y), grid);
    }
    canvas.drawRect(
      box,
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}

/// A dot for a bridged component to carry, sized in metres.
CircleComponent flameDot(Color color, {double radius = 0.25}) =>
    CircleComponent(
      radius: radius,
      anchor: Anchor.center,
      paint: Paint()..color = color,
    );

/// A line of text at [at], in pixels from the top-left of the game.
TextComponent flameCaption(String text, {Vector2? at}) => TextComponent(
  text: text,
  position: at ?? Vector2(16.0, 16.0),
  textRenderer: TextPaint(
    style: const TextStyle(
      color: Color(0xFFE8E8EC),
      fontSize: 15.0,
      shadows: <Shadow>[Shadow(blurRadius: 4.0, color: Color(0xFF000000))],
    ),
  ),
);

/// [child] turned by a drag and zoomed by the wheel, the same as a page's
/// own viewport. Flame's game sits above the scene and takes the pointer, but
/// a listener further up the tree still hears every event.
Widget flameOrbit(DemoContext context, Widget child) => Listener(
  onPointerMove: (PointerMoveEvent event) =>
      context.orbit.rotate(event.delta.dx, event.delta.dy),
  onPointerSignal: (PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      context.orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
    }
  },
  child: child,
);
