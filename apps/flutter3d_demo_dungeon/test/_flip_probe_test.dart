import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empirically: where does the TOP of a widget end up on screen?', (
    tester,
  ) async {
    final device = CpuDevice(
      width: 64,
      height: 64,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final scene = Scene();

    // Camera at -Z looking at the origin, matching the live demo's setup.
    final camera = CameraNode(name: 'eye')
      ..setPositionFrom(Vector3(0.0, 0.0, -3.0))
      ..lookAt(Vector3.zero());
    scene.add(camera);

    // A widget whose TOP half is pure red and BOTTOM half is pure blue —
    // unambiguous, no text/antialiasing to misread.
    final surface = WidgetSurface(
      device: device,
      width: 2.0,
      height: 2.0,
      child: const Column(
        children: <Widget>[
          Expanded(child: ColoredBox(color: Color(0xFFFF0000))),
          Expanded(child: ColoredBox(color: Color(0xFF0000FF))),
        ],
      ),
    );
    addTearDown(surface.dispose);
    scene.add(surface.node);
    // Not `pumpAndSettle()`: a live `WidgetSurface` keeps scheduling frames
    // for its own redraw-on-dirty pipeline, so a settle-based pump never
    // sees "nothing left to draw" and hangs — the same reason every other
    // `WidgetSurface` test in this repository (`widget_surface_test.dart`,
    // `operator_panel_test.dart`) pumps a fixed number of frames instead.
    await tester.pump();
    // `tick()` reaches `WidgetSurfacePipeline.currentImage()`, which asks the
    // engine to rasterise a frame for real — `wg-01`'s own test (and
    // `operator_panel_test.dart` after it) found a bare `await` on this
    // deadlocks inside `testWidgets`'s fake async zone, since the rasteriser
    // needs the real event loop `runAsync` escapes to.
    await tester.runAsync(surface.tick);

    final result = renderer.render(
      width: 64,
      height: 64,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(),
    );
    final readback = await device.readPixels(result.frame);
    final pixels = readback!.buffer.asUint8List();

    Color at(int x, int y) {
      final i = (y * 64 + x) * 4;
      return Color.fromARGB(255, pixels[i], pixels[i + 1], pixels[i + 2]);
    }

    final topColor = at(32, 10);
    final bottomColor = at(32, 54);
    // ignore: avoid_print
    print('top of screen: $topColor, bottom of screen: $bottomColor');
  });
}
