/// `wg-00`'s two claims, each pinned by a test that would fail without the
/// mechanism behind it: a pipeline that was not asked to redraw does not, and
/// a pointer event handed a UV reaches the widget under it exactly like a
/// real tap would.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('redrawIfDirty', () {
    testWidgets('does nothing until something marks itself dirty', (
      tester,
    ) async {
      final pipeline = WidgetSurfacePipeline(
        width: 64,
        height: 64,
        // A widget that never changes: the control this measures against is
        // one with nothing to redraw for.
        child: const ColoredBox(color: Color(0xFF112233)),
      );
      addTearDown(pipeline.dispose);

      expect(
        pipeline.isDirty,
        isFalse,
        reason: 'the first frame is already drawn',
      );
      expect(pipeline.redrawIfDirty(), isFalse);
      expect(pipeline.redrawIfDirty(), isFalse);
      expect(pipeline.redrawCount, 0);
    });

    testWidgets('redraws once per state change, not once per check', (
      tester,
    ) async {
      final notifier = ValueNotifier<Color>(const Color(0xFFFF0000));
      final pipeline = WidgetSurfacePipeline(
        width: 64,
        height: 64,
        child: ValueListenableBuilder<Color>(
          valueListenable: notifier,
          builder: (context, color, _) => ColoredBox(color: color),
        ),
      );
      addTearDown(pipeline.dispose);
      addTearDown(notifier.dispose);

      expect(pipeline.redrawIfDirty(), isFalse, reason: 'nothing changed yet');

      notifier.value = const Color(0xFF00FF00);
      expect(
        pipeline.isDirty,
        isTrue,
        reason:
            'ValueListenableBuilder calls setState, which schedules a '
            'build through BuildOwner.onBuildScheduled',
      );
      expect(pipeline.redrawIfDirty(), isTrue);
      expect(pipeline.redrawIfDirty(), isFalse, reason: 'already caught up');
      expect(pipeline.redrawCount, 1);

      notifier.value = const Color(0xFF0000FF);
      notifier.value = const Color(0xFF0000FF);
      // Two writes, the second a no-op `ValueListenableBuilder` still
      // rebuilds for (it does not compare old and new value) — one redraw is
      // still correct, because the question is "did anything ask", not "how
      // many times".
      expect(pipeline.redrawIfDirty(), isTrue);
      expect(pipeline.redrawCount, 2);
    });
  });

  group('dispatchAtUv', () {
    testWidgets('a tap on the surface reaches the button under its UV', (
      tester,
    ) async {
      var taps = 0;
      final pipeline = WidgetSurfacePipeline(
        width: 200,
        height: 100,
        child: Row(
          children: [
            // Left half: nothing. Right half: the button. A UV of (0.75, 0.5)
            // should land on the button and a UV of (0.25, 0.5) should not.
            const SizedBox(width: 100, height: 100),
            SizedBox(
              width: 100,
              height: 100,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
            ),
          ],
        ),
      );
      addTearDown(pipeline.dispose);

      const pointer = 1;
      pipeline.announcePointer(pointer, added: true);

      pipeline.dispatchAtUv(
        const Offset(0.25, 0.5),
        (local) => PointerDownEvent(pointer: pointer, position: local),
      );
      pipeline.dispatchAtUv(
        const Offset(0.25, 0.5),
        (local) => PointerUpEvent(pointer: pointer, position: local),
      );
      expect(taps, 0, reason: 'the left half has nothing on it');

      pipeline.dispatchAtUv(
        const Offset(0.75, 0.5),
        (local) => PointerDownEvent(pointer: pointer, position: local),
      );
      pipeline.dispatchAtUv(
        const Offset(0.75, 0.5),
        (local) => PointerUpEvent(pointer: pointer, position: local),
      );
      pipeline.announcePointer(pointer, added: false);

      expect(taps, 1, reason: 'a UV of (0.75, 0.5) is the button half');
    });

    testWidgets(
      'the whole chain: a ray hits a wall, and the UV it lands at taps the '
      'button drawn there',
      (tester) async {
        // The wall `wg-00` asks a pointer to hit — a plain box, the same
        // shape `flutter3d_sim/test/parity_test.dart` and
        // `flutter3d_game_platformer/test/parity_test.dart` already proved
        // deterministic across every platform in `rp-00`. What is new here is
        // what happens *after* the hit: the point and normal it returns are
        // turned into a UV on the face, and that UV is what reaches the
        // widget — nothing about the pipeline above cares that the UV came
        // from a raycast rather than from a test calling `dispatchAtUv`
        // directly, which is the point: the wall could be any shape wg-01
        // ends up supporting, as long as it can still answer in UV.
        // `addBox` takes the box's *full* size, not its half-extents — the
        // half-extents below (2.0, 2.0, 0.1) are half of what is passed here,
        // the same convention `flutter3d_sim/test/parity_test.dart`'s `_room`
        // relies on for its floor.
        final centre = Vector3(0.0, 1.0, 0.0);
        final halfExtents = Vector3(2.0, 2.0, 0.1);
        final world = CollisionWorld()..addBox(centre, halfExtents * 2.0);
        final hit = RayHit();
        // Straight along Z, so the hit point's x and y are the ray's own —
        // aimed at a quarter of the way across the wall and a quarter of the
        // way up its face, chosen off-centre so a bug that reads the wrong
        // axis or flips a sign lands somewhere else on the widget and is
        // caught by the same assertion.
        world.raycast(
          Vector3(-1.0, 2.0, -5.0),
          Vector3(0.0, 0.0, 1.0),
          20.0,
          hit,
        );
        expect(hit.hit, isTrue, reason: 'the ray was aimed at the wall');

        final uv = _uvOnBoxFace(
          point: hit.point,
          normal: hit.normal,
          centre: centre,
          halfExtents: halfExtents,
        );
        expect(
          uv,
          offsetMoreOrLessEquals(const Offset(0.25, 0.25), epsilon: 1e-6),
          reason: 'the geometry above is chosen to land exactly here',
        );

        var taps = 0;
        final pipeline = WidgetSurfacePipeline(
          width: 200,
          height: 100,
          child: Stack(
            children: [
              // Covers pixel (50, 25) — where UV (0.25, 0.25) lands on a
              // 200x100 canvas — comfortably, without covering most of the
              // canvas: a bug that puts the tap somewhere else on the surface
              // still misses this.
              Positioned(
                left: 20,
                top: 0,
                width: 60,
                height: 50,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                ),
              ),
            ],
          ),
        );
        addTearDown(pipeline.dispose);

        const pointer = 2;
        pipeline.announcePointer(pointer, added: true);
        pipeline.dispatchAtUv(
          uv,
          (local) => PointerDownEvent(pointer: pointer, position: local),
        );
        pipeline.dispatchAtUv(
          uv,
          (local) => PointerUpEvent(pointer: pointer, position: local),
        );
        pipeline.announcePointer(pointer, added: false);

        expect(
          taps,
          1,
          reason:
              'the ray, the hit, the UV and the dispatch each did their '
              'part: $uv should have landed inside the button',
        );
      },
    );
  });
}

/// A hit point and normal on an axis-aligned box, as a UV on the face it hit.
///
/// **Deliberately not part of the pipeline's public API.** Mapping a triangle
/// mesh's hit point to its own UV channel is the renderer's job — `wg-01`'s,
/// once a `WidgetSurface` node has a mesh to ask — and a box has no UV
/// channel to read at all. This exists only so the test above can aim a ray
/// at something and get a UV back, the way a real mesh will.
Offset _uvOnBoxFace({
  required Vector3 point,
  required Vector3 normal,
  required Vector3 centre,
  required Vector3 halfExtents,
}) {
  final local = point - centre;
  // Whichever axis the normal points along is the face's own depth axis; the
  // other two are the face's width and height, read off in a fixed order so a
  // hit on the front and the back of the wall do not mirror each other.
  if (normal.x.abs() > normal.y.abs() && normal.x.abs() > normal.z.abs()) {
    return Offset(
      (local.z / halfExtents.z + 1.0) / 2.0,
      1.0 - (local.y / halfExtents.y + 1.0) / 2.0,
    );
  }
  if (normal.y.abs() > normal.z.abs()) {
    return Offset(
      (local.x / halfExtents.x + 1.0) / 2.0,
      (local.z / halfExtents.z + 1.0) / 2.0,
    );
  }
  return Offset(
    (local.x / halfExtents.x + 1.0) / 2.0,
    1.0 - (local.y / halfExtents.y + 1.0) / 2.0,
  );
}
