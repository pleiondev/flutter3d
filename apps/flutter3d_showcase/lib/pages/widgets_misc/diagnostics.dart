/// How long since the last frame, what a window of frames cost, and giving
/// pooled render targets back when the platform warns about memory.
///
/// Quoted by `diagnostics.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DiagnosticsDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run(context);
    final material = Material(
      name: 'clock',
      baseColor: Vector4(0.7, 0.7, 0.4, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region clock
  static String _clockLine() {
    final clock = FrameClock();
    final first = clock.tick();
    clock.secondsSince(const Duration(milliseconds: 16));
    clock.secondsSince(const Duration(milliseconds: 32));
    return 'first tick: ${first}s, elapsed after two frames: '
        '${clock.elapsed.toStringAsFixed(3)}s';
  }
  // #endregion clock

  // #region timing
  static String _timingLine() {
    final log = FrameTimingLog(label: 'demo', window: 2);
    log.note(
      build: const Duration(milliseconds: 4),
      raster: const Duration(milliseconds: 6),
    );
    final line = log.note(
      build: const Duration(milliseconds: 8),
      raster: const Duration(milliseconds: 10),
    );
    return line ?? 'no line yet';
  }
  // #endregion timing

  static String _run(DemoContext context) {
    // #region pressure
    // What a memory warning does: give the renderer's pooled render targets
    // back. `MemoryPressureRelease` calls exactly this when the platform
    // warns; calling it directly here proves the release itself.
    context.renderer.releaseTransientTargets();
    // #endregion pressure

    return '${_clockLine()}\n${_timingLine()}';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the clock marker was not drawn');
    }
    if (!_report.contains('first tick: 0.0s')) {
      throw StateError(
        'the very first tick of a frame clock should measure '
        'as no time at all',
      );
    }
    if (!_report.contains('over 2 frames')) {
      throw StateError(
        'a timing log with a window of two should report '
        'after its second frame',
      );
    }
  }
}
