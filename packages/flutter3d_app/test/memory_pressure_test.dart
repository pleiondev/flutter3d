/// `gfx-71n`: a memory warning gives the pooled render targets back.
///
///     flutter test test/memory_pressure_test.dart
///
/// **What the pool does without this is settle at a high-water mark and stay
/// there.** It keeps one texture of every attachment shape any frame has ever
/// needed, and gives none of it back: turn bloom on once and its five levels
/// are held for the rest of the session. On a desktop that is a megabyte nobody
/// notices; on a phone the operating system kills the process, which arrives as
/// a report with no Dart stack.
///
/// Two claims: the warning reaches the pool, and the frame after it draws the
/// same picture. The second is the one that makes the first safe — a release
/// that took a target a live frame was holding would be a use-after-free on a
/// backend where dropping the last reference is what frees.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _size = 32;

({CpuDevice device, Renderer renderer, Scene scene}) _built() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        Material(name: 'cube'),
      ),
    )
    ..add(
      LightNode(intensity: 4.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 0.0, 5.0)
        ..lookAt(Vector3.zero()),
    );
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
  );
}

Future<List<int>> _draw(
  ({CpuDevice device, Renderer renderer, Scene scene}) it, {
  bool bloom = false,
}) async {
  final frame = it.renderer.render(
    width: _size,
    height: _size,
    scene: it.scene,
    views: <RenderView>[
      RenderView(
        camera: it.scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(bloom: BloomSettings(enabled: bloom)),
  );
  final bytes = await it.device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

/// Leaves the pool holding what a frame no longer needs.
///
/// **This is the shape the row describes, measured.** Five frames with bloom
/// on and the pool has fifteen textures — its five levels across three
/// frames-in-flight slots. Six frames with bloom off and all fifteen are
/// *free*: nothing asks for that shape again, and the pool holds them for the
/// rest of the session. A test that turned bloom on and left it on would find
/// an empty free list and prove nothing, because in a steady state every
/// pooled texture is lent.
Future<void> _leaveBloomBehind(
  ({CpuDevice device, Renderer renderer, Scene scene}) it,
) async {
  for (var i = 0; i < 5; i++) {
    await _draw(it, bloom: true);
  }
  for (var i = 0; i < 6; i++) {
    await _draw(it);
  }
}

void main() {
  testWidgets('a memory warning empties the pool', (WidgetTester tester) async {
    final it = _built();
    await _leaveBloomBehind(it);
    expect(
      it.renderer.targetPool.pooledCount,
      greaterThan(0),
      reason: 'the pool holds nothing, so this measures nothing',
    );

    await tester.pumpWidget(
      MemoryPressureRelease(
        renderer: it.renderer,
        child: const SizedBox.shrink(),
      ),
    );
    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(it.renderer.targetPool.pooledCount, 0);
  });

  testWidgets('and the next frame draws the same picture', (
    WidgetTester tester,
  ) async {
    final it = _built();
    await _leaveBloomBehind(it);
    final before = await _draw(it);

    await tester.pumpWidget(
      MemoryPressureRelease(
        renderer: it.renderer,
        child: const SizedBox.shrink(),
      ),
    );
    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(await _draw(it), before);
  });

  testWidgets('an application can hear that it happened', (
    WidgetTester tester,
  ) async {
    // A memory warning is the sort of thing a player reports as "it got slow
    // for a second" and a developer never sees otherwise.
    final it = _built();
    var heard = 0;

    await tester.pumpWidget(
      MemoryPressureRelease(
        renderer: it.renderer,
        onReleased: () => heard++,
        child: const SizedBox.shrink(),
      ),
    );
    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(heard, 1);
  });

  testWidgets('and stops hearing once it is gone', (WidgetTester tester) async {
    // The observer has to come off the binding in `dispose`, or a warning after
    // a scene is torn down reaches a renderer whose device may be gone.
    final it = _built();
    var heard = 0;

    await tester.pumpWidget(
      MemoryPressureRelease(
        renderer: it.renderer,
        onReleased: () => heard++,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(heard, 0);
  });
}
