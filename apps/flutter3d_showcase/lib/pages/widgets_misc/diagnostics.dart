/// How long since the last frame, what a window of frames cost, and giving
/// pooled render targets back when the platform warns about memory.
///
/// Quoted by `diagnostics.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DiagnosticsDemo extends ShowcaseDemo {
  late final String _report;
  late final double _firstTick;
  late final bool _hasTimingLine;

  @override
  Scene build(DemoContext context) {
    final (String report, double firstTick, bool hasTimingLine) = _run(context);
    _report = report;
    _firstTick = firstTick;
    _hasTimingLine = hasTimingLine;
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
  static (String, double) _clockLine() {
    final clock = FrameClock();
    final first = clock.tick();
    clock.secondsSince(const Duration(milliseconds: 16));
    clock.secondsSince(const Duration(milliseconds: 32));
    return (
      'first tick: ${first}s, elapsed after two frames: '
          '${clock.elapsed.toStringAsFixed(3)}s',
      first,
    );
  }
  // #endregion clock

  // #region timing
  static String? _timingLine() {
    final log = FrameTimingLog(label: 'demo', window: 2);
    log.note(
      build: const Duration(milliseconds: 4),
      raster: const Duration(milliseconds: 6),
    );
    return log.note(
      build: const Duration(milliseconds: 8),
      raster: const Duration(milliseconds: 10),
    );
  }
  // #endregion timing

  static (String, double, bool) _run(DemoContext context) {
    // #region pressure
    // What a memory warning does: give the renderer's pooled render targets
    // back. `MemoryPressureRelease` calls exactly this when the platform
    // warns; calling it directly here proves the release itself.
    context.renderer.releaseTransientTargets();
    // #endregion pressure

    final (String clockLine, double firstTick) = _clockLine();
    final String? timingLine = _timingLine();
    return (
      '$clockLine\n${timingLine ?? 'no line yet'}',
      firstTick,
      timingLine != null,
    );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the clock marker was not drawn');
    }
    // Compared as a number, not read back out of `_report`: the first tick
    // is a whole-number double, and a web backend prints one of those
    // without its trailing `.0` — a compiled `0` failing a substring match
    // against `'tick: 0.0s'` would be this check catching its own string,
    // not the clock.
    if (_firstTick != 0.0) {
      throw StateError(
        'the very first tick of a frame clock should measure '
        'as no time at all',
      );
    }
    if (!_hasTimingLine) {
      throw StateError(
        'a timing log with a window of two should report '
        'after its second frame',
      );
    }
  }
}
