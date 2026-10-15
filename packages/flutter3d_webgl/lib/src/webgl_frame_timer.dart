/// What the GPU spent on each labelled pass, on WebGL2:
/// `EXT_disjoint_timer_query_webgl2`'s `TIME_ELAPSED_EXT` queries, one
/// around each labelled pass, read a frame or two later.
///
/// **Elapsed time, not timestamps**, because that is the half of the
/// extension every browser that offers it counts. Some answer
/// `QUERY_COUNTER_BITS_EXT` of zero for `TIMESTAMP_EXT` — a timestamp query
/// set reads zeros there and is not listed — while their elapsed-time
/// queries work, which is all `GraphicsDevice.onGpuTimings` needs.
///
/// **A result is never waited for.** WebGL2 makes a query's answer available
/// no earlier than the page's next turn of the event loop, so each frame
/// reads only the frames whose queries are already answered, oldest first,
/// and a frame the GPU timer calls disjoint (a power state or context
/// change) is dropped rather than reported wrong.
library;

import 'dart:js_interop';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

/// The extension's `TIME_ELAPSED_EXT` target.
const int webglTimeElapsed =
    web.EXT_disjoint_timer_query_webgl2.TIME_ELAPSED_EXT;

/// One labelled pass's query.
typedef _Timed = ({String label, web.WebGLQuery query});

/// The frame timer behind `WebGlDevice.onGpuTimings`.
final class WebGlFrameTimer {
  WebGlFrameTimer(this._gl);

  final web.WebGL2RenderingContext _gl;

  /// Passes timed a frame; the rest are drawn untimed rather than refused.
  static const int maxPasses = 64;

  /// Frames whose answers may be outstanding at once. A browser that never
  /// answers (a lost context) costs this many frames of queries, not a leak.
  static const int maxFramesInFlight = 4;

  final List<_Timed> _current = <_Timed>[];
  final List<({int frame, List<_Timed> passes})> _pending =
      <({int frame, List<_Timed> passes})>[];
  bool _open = false;
  int _frame = 0;

  /// Starts timing a pass labelled [label]. False when a pass is already
  /// being timed (GL times one span at a time) or the frame is full.
  bool begin(String label) {
    if (_open || _current.length >= maxPasses) return false;
    final query = _gl.createQuery();
    if (query == null) return false;
    _gl.beginQuery(webglTimeElapsed, query);
    _current.add((label: label, query: query));
    _open = true;
    return true;
  }

  /// Ends the span [begin] started.
  void end() {
    if (!_open) return;
    _gl.endQuery(webglTimeElapsed);
    _open = false;
  }

  /// Closes the frame just drawn and hands [listener] every earlier frame
  /// whose answers have arrived, in order.
  void endFrame(void Function(GpuFrameTimings timings)? listener) {
    end();
    if (_current.isNotEmpty) {
      _pending.add((frame: _frame, passes: List<_Timed>.of(_current)));
      _current.clear();
    }
    _frame++;
    // Nothing to read, and no reason to ask the context anything.
    if (_pending.isEmpty) return;
    final disjoint = _truthy(
      _gl.getParameter(web.EXT_disjoint_timer_query_webgl2.GPU_DISJOINT_EXT),
    );
    while (_pending.isNotEmpty && _answered(_pending.first.passes.last.query)) {
      final (:frame, :passes) = _pending.removeAt(0);
      if (listener != null && !disjoint) {
        listener(
          GpuFrameTimings(
            frame: frame,
            passes: <GpuPassTiming>[
              for (final pass in passes)
                GpuPassTiming(
                  label: pass.label,
                  micros: (_nanoseconds(pass.query) / 1000.0).round(),
                ),
            ],
          ),
        );
      }
      _delete(passes);
    }
    while (_pending.length > maxFramesInFlight) {
      _delete(_pending.removeAt(0).passes);
    }
  }

  /// Deletes every query still held.
  void dispose() {
    end();
    _delete(_current);
    _current.clear();
    for (final frame in _pending) {
      _delete(frame.passes);
    }
    _pending.clear();
  }

  bool _answered(web.WebGLQuery query) => _truthy(
    _gl.getQueryParameter(
      query,
      web.WebGL2RenderingContext.QUERY_RESULT_AVAILABLE,
    ),
  );

  double _nanoseconds(web.WebGLQuery query) {
    final value = _gl.getQueryParameter(
      query,
      web.WebGL2RenderingContext.QUERY_RESULT,
    );
    return value != null && value.isA<JSNumber>()
        ? (value as JSNumber).toDartDouble
        : 0;
  }

  void _delete(List<_Timed> passes) {
    for (final pass in passes) {
      _gl.deleteQuery(pass.query);
    }
  }

  static bool _truthy(JSAny? value) {
    if (value == null) return false;
    if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
    if (value.isA<JSNumber>()) return (value as JSNumber).toDartDouble != 0;
    return false;
  }
}
