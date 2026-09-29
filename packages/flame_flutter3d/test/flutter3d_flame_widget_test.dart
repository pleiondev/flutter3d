/// [Flutter3dFlameWidget] builds and ticks both layers without throwing.
///
/// **These were skipped as hanging, and do not hang.** A Flame
/// `GameWidget` under `flutter_test` was said to hang in this environment,
/// and the evidence was a test runner that ran for its whole timeout with
/// no output. Run with `flutter test` directly, both finish in seconds: the
/// runner, not Flame, was what stood still. With the skip in place the
/// package's own host widget had no test at all.
library;

import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an empty game and an empty scene compose and tick', (
    tester,
  ) async {
    final camera = CameraNode(name: 'eye');
    var ticks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Flutter3dFlameWidget(
          game: FlameGame(),
          camera: camera,
          buildScene: (device) => Scene(),
          onTick: (double dt) => ticks++,
          width: 32,
          height: 24,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GameWidget<FlameGame>), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 16));

    expect(ticks, greaterThan(0));
  });

  testWidgets('an existing device and renderer are reused, not reopened', (
    tester,
  ) async {
    final device = CpuDevice(
      width: 32,
      height: 24,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final camera = CameraNode(name: 'eye');
    GraphicsDevice? seen;

    await tester.pumpWidget(
      MaterialApp(
        home: Flutter3dFlameWidget(
          game: FlameGame(),
          camera: camera,
          existing: (device: device, renderer: renderer),
          buildScene: (d) {
            seen = d;
            return Scene();
          },
        ),
      ),
    );
    await tester.pump();

    expect(seen, same(device), reason: 'no second device should open');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
