/// What a locked pointer gives a game that an ordinary cursor cannot:
/// relative motion with nothing to run out of room against.
///
/// **`pointer_lock` is not a dependency of this app yet.** The real package
/// asks the platform to hide the cursor and hand back relative deltas with
/// no screen edge to hit; this page cannot import it (see the showcase's own
/// report on this row), so it demonstrates the concept with the relative
/// deltas Flutter's own pointer events already carry, accumulated with
/// nothing clamping them to the window.
///
/// Quoted by `pointer_lock.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PointerLockDemo extends ShowcaseDemo {
  Vector2 accumulated = Vector2.zero();

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.55, 0.55, 0.65, 1.0),
      roughness: 0.7,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 24, rings: 12).build(),
      ),
      stone,
      name: 'ball',
    );
    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region accumulate
  /// A locked pointer never runs out of room: nothing here clamps the total
  /// to the window's size, the way an ordinary cursor position would be. A
  /// real `pointer_lock` capture hands over exactly this shape of delta;
  /// this page sums the deltas Flutter's own pointer events already report.
  Vector2 accumulate(Vector2 total, Offset delta) =>
      total + Vector2(delta.dx, delta.dy);
  // #endregion accumulate

  @override
  Widget? customBody(
    BuildContext buildContext,
    DemoContext context,
  ) => Listener(
    onPointerMove: (PointerMoveEvent event) {
      accumulated = accumulate(accumulated, event.delta);
    },
    child: Container(
      color: const Color(0xFF14161A),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
        child: Text(
          'pointer_lock is not wired into this app. Drag across this panel; '
          'the total below keeps growing past the edge of the window the '
          'way a locked pointer\'s relative motion would, rather than '
          'stopping the way an ordinary cursor position does.\n\n'
          'accumulated: (${accumulated.x.toStringAsFixed(0)}, '
          '${accumulated.y.toStringAsFixed(0)})',
        ),
      ),
    ),
  );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // Three known deltas in a row have to sum exactly, the way an unbounded
    // relative total must: nothing here is allowed to clamp or drop one.
    Vector2 total = Vector2.zero();
    total = accumulate(total, const Offset(30, -10));
    total = accumulate(total, const Offset(30, -10));
    total = accumulate(total, const Offset(30, -10));
    if (total.x != 90.0 || total.y != -30.0) {
      throw StateError('accumulate dropped or clamped a relative delta');
    }
  }
}
