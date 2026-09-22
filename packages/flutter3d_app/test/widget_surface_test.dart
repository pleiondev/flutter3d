/// `wg-01`: a live widget as a mesh in the scene. Four things, each pinned by
/// a test that fails without the mechanism behind it: the plane stands up and
/// faces the direction a level author expects from `yaw` (not just compiles);
/// a world point on the surface maps back to the UV that placed it there; the
/// diagnostic counter this owes `wg-01`'s own acceptance stays flat across
/// frames nothing changed and moves across ones that did; and a real ray hit
/// on the surface reaches a real widget under it, the same chain `wg-00`
/// proved for a plain UV.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

GraphicsDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('orientation', () {
    testWidgets('at yaw nought, the surface faces -Z — the same forward '
        'ActorVisuals.yawFor already documents', (tester) async {
      final surface = WidgetSurface(
        device: _device(),
        width: 2.0,
        height: 1.0,
        child: const ColoredBox(color: Color(0xFF112233)),
      );
      addTearDown(surface.dispose);

      final normal = Vector3(0.0, 1.0, 0.0);
      surface.node.worldMatrix.rotate3(normal);
      // `vector_math`'s own `Matrix4`/`Quaternion` are float32 underneath —
      // `1e-6`, not `1e-9`, is what a rotation actually round-trips to.
      expect(normal.x, closeTo(0.0, 1e-6));
      expect(normal.y, closeTo(0.0, 1e-6));
      expect(normal.z, closeTo(-1.0, 1e-6));
    });

    testWidgets('yaw turns the surface about world Y, not some other axis', (
      tester,
    ) async {
      final surface = WidgetSurface(
        device: _device(),
        child: const ColoredBox(color: Color(0xFF112233)),
      )..yaw = 1.5707963267948966; // pi/2
      addTearDown(surface.dispose);

      final normal = Vector3(0.0, 1.0, 0.0);
      surface.node.worldMatrix.rotate3(normal);
      // A quarter turn about Y takes -Z to -X, the same rotation
      // `fixture_visuals.dart` already applies to a fixture's own yaw.
      expect(normal.x, closeTo(-1.0, 1e-6));
      expect(normal.y, closeTo(0.0, 1e-6));
      expect(normal.z, closeTo(0.0, 1e-6));
    });
  });

  group('uvAt', () {
    testWidgets('a world point on the surface maps back to its own UV', (
      tester,
    ) async {
      final surface = WidgetSurface(
        device: _device(),
        width: 2.0,
        height: 1.0,
        child: const ColoredBox(color: Color(0xFF112233)),
      )..setPosition(Vector3(5.0, 1.0, 0.0));
      addTearDown(surface.dispose);

      // Centre of the surface.
      expect(
        surface.uvAt(Vector3(5.0, 1.0, 0.0)),
        offsetMoreOrLessEquals(const Offset(0.5, 0.5), epsilon: 1e-4),
      );
      // A quarter of the way across from the left edge, at the bottom —
      // `v` near 1.0, since `v` runs top-down and the bottom of the surface
      // is the far end of it.
      expect(
        surface.uvAt(Vector3(4.5, 0.5, 0.0)),
        offsetMoreOrLessEquals(const Offset(0.25, 1.0), epsilon: 1e-4),
      );
    });

    testWidgets('a point off the plane, or off its edge, finds nothing', (
      tester,
    ) async {
      final surface = WidgetSurface(
        device: _device(),
        width: 2.0,
        height: 1.0,
        child: const ColoredBox(color: Color(0xFF112233)),
      );
      addTearDown(surface.dispose);

      expect(
        surface.uvAt(Vector3(0.0, 0.0, 1.0)),
        isNull,
        reason: 'behind the plane',
      );
      expect(
        surface.uvAt(Vector3(5.0, 0.0, 0.0)),
        isNull,
        reason: 'past its width',
      );
    });
  });

  group('tick', () {
    testWidgets('redrawCount stays flat across frames nothing changed, and '
        'moves across ones that did', (tester) async {
      final notifier = ValueNotifier<Color>(const Color(0xFFFF0000));
      final surface = WidgetSurface(
        device: _device(),
        width: 0.1,
        height: 0.1,
        child: ValueListenableBuilder<Color>(
          valueListenable: notifier,
          builder: (context, color, _) => ColoredBox(color: color),
        ),
      );
      addTearDown(surface.dispose);
      addTearDown(notifier.dispose);

      // `tick()` reaches `WidgetSurfacePipeline.currentImage()`, which asks
      // the engine's own raster pipeline to encode a frame — real async I/O
      // `flutter_test`'s fake zone never lets resolve on its own, the same
      // reason `widget_surface_pipeline_benchmark_test.dart` reaches for
      // `tester.runAsync` around the identical call.
      expect(surface.redrawCount, 0);
      await tester.runAsync(surface.tick);
      await tester.runAsync(surface.tick);
      await tester.runAsync(surface.tick);
      expect(
        surface.redrawCount,
        0,
        reason: 'nothing inside the widget changed',
      );

      notifier.value = const Color(0xFF00FF00);
      await tester.runAsync(surface.tick);
      expect(surface.redrawCount, 1);

      await tester.runAsync(surface.tick);
      await tester.runAsync(surface.tick);
      expect(
        surface.redrawCount,
        1,
        reason: 'caught up after the one real change',
      );
    });

    testWidgets('a redrawn frame is uploaded as the mesh\'s own texture', (
      tester,
    ) async {
      final surface = WidgetSurface(
        device: _device(),
        width: 0.1,
        height: 0.1,
        child: const ColoredBox(color: Color(0xFF224466)),
      );
      addTearDown(surface.dispose);

      final before = surface.node.material.albedo;
      await tester.runAsync(surface.tick);
      // The very first frame is already drawn by the pipeline's own
      // constructor (see `WidgetSurfacePipeline`'s docstring) rather than by
      // this call, so `redrawCount` does not have to move for a widget this
      // static — what has to be true, and what a widget that never changes
      // would fail without `tick`'s own forced first upload, is that the
      // frame the pipeline already drew reaches the mesh at all.
      expect(surface.node.material.albedo, isNot(same(before)));

      final afterFirst = surface.node.material.albedo;
      await tester.runAsync(surface.tick);
      expect(
        surface.node.material.albedo,
        same(afterFirst),
        reason: 'nothing changed on the second call, so nothing re-uploads',
      );
    });
  });

  group('the whole chain', () {
    testWidgets('a ray hits the surface, and the UV it lands at taps the '
        'button drawn there', (tester) async {
      var taps = 0;
      final surface = WidgetSurface(
        device: _device(),
        width: 2.0,
        height: 1.0,
        // Covers UV (0.25, 0.75) — where the ray aimed below is chosen to
        // land — comfortably, without covering most of the canvas: a bug
        // that reads the wrong axis or flips a sign still misses this.
        child: Align(
          alignment: const Alignment(-0.5, 0.5),
          child: SizedBox(
            width: 100,
            height: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
          ),
        ),
      )..setPosition(Vector3(0.0, 1.0, 0.0));
      addTearDown(surface.dispose);

      // `addBox` takes the box's *full* size — the same 2.0 x 1.0 face as
      // the surface, with a thin depth along Z standing in for a wall a
      // real level would raycast against instead of the bare mesh.
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.1));
      final hit = RayHit();
      world.raycast(
        Vector3(-0.5, 0.75, -5.0),
        Vector3(0.0, 0.0, 1.0),
        20.0,
        hit,
      );
      expect(hit.hit, isTrue, reason: 'the ray was aimed at the surface');

      // The collision box is 0.1 deep (half-thickness 0.05) standing in for
      // a wall — `uvAt`'s own doc names exactly this: its default tolerance
      // is a hair too tight for a hit on this box's own near face.
      final uv = surface.uvAt(hit.point, epsilon: 0.06);
      expect(
        uv,
        offsetMoreOrLessEquals(const Offset(0.25, 0.75), epsilon: 1e-4),
        reason: 'the geometry above is chosen to land exactly here',
      );

      const pointer = 3;
      surface.pipeline.announcePointer(pointer, added: true);
      surface.pipeline.dispatchAtUv(
        uv!,
        (local) => PointerDownEvent(pointer: pointer, position: local),
      );
      surface.pipeline.dispatchAtUv(
        uv,
        (local) => PointerUpEvent(pointer: pointer, position: local),
      );
      surface.pipeline.announcePointer(pointer, added: false);

      expect(taps, 1, reason: 'the ray landed where the button was drawn');
    });
  });
}
