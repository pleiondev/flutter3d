/// Puts the renderer's own frame on the VM service as `ext.flutter3d.render.*`
/// — `P12`.
///
/// **The frame the player sees, not a second one drawn for the tool.** The
/// diagnostic renderers in `flutter3d_sim_mcp` and `flutter3d_mcp/editor.dart` draw
/// a level again on the software backend at 320×200, which answers "what is
/// in the level" and nothing about why the game's own frame is black, has a
/// hole in it, or costs twice what it did yesterday. Those are questions about
/// the GPU frame that actually ran, with its passes, its targets and its
/// draws, and only the running game has it. So every request here is a
/// `Renderer.captureNextFrame(draws: true)`: the next frame the game draws
/// anyway, recorded pass by pass, and answered by the functions in
/// `render_inspection.dart`.
///
/// ## What a caller sees
///
/// Eleven extensions, each `ext.flutter3d.render.<verb>`, string parameters
/// as the protocol requires:
///
/// * `passes`, `draws`, `stats`, `scanNan` — take a fresh capture unless
///   `fresh=false` and one is held.
/// * `passOutput`, `draw`, `readPixel`, `capture` — read the capture already
///   held, so an index from `draws` or a pass from `passes` means the same
///   frame; pass `fresh=true` to take a new one. With none held they take
///   one. `capture` answers the whole frame as a capture file — `A5.23`.
/// * `memory` — what the renderer holds on the device, by category, with no
///   capture — `A5.24`.
/// * `debugViews` — the debug views by name, for a tool to pick from —
///   `A5.21`.
/// * `pick` — which draws put the pixel at `x`, `y` on the screen: the
///   picking pass's node and its draws, taken together with a fresh capture
///   of the same frame, which it then holds for `draw` to open.
///
/// Every answer carries `frame`, a count of captures this game has taken, so
/// a caller can see whether two answers are about the same frame.
///
/// **Harmless where the VM service is off**, the same way the timeline's are:
/// `registerExtension` adds an entry nothing ever asks for, and nothing is
/// captured until something does.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show CpuDevice;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'render_inspection.dart';

/// Registers `ext.flutter3d.render.*` against whatever [renderer] answers at
/// the moment of each request — null while the game's renderer has not
/// opened, which is refused with that reason.
///
/// Calling it again replaces the getter rather than registering twice, which
/// `registerExtension` would refuse: a game that builds its renderer again,
/// or a second screen with its own, points the same extensions at the new
/// one.
///
/// [scene], when given, is what `memory` adds the meshes and textures of —
/// the renderer holds neither, so without it the report covers the
/// renderer's own targets, pool and pipelines.
void registerRenderExtensions(
  Renderer? Function() renderer, {
  Duration timeout = const Duration(seconds: 2),
  Scene? Function()? scene,
}) {
  _inspector.renderer = renderer;
  _inspector.timeout = timeout;
  _inspector.scene = scene ?? () => null;
  if (_registered) return;
  _registered = true;

  void answer(
    String verb, {
    required bool freshByDefault,
    required Set<String> answers,
    required Map<String, Object?> Function(
      FrameCapture capture,
      Map<String, String> parameters,
    )
    ask,
  }) {
    registerFlutter3dExtension('ext.flutter3d.render.$verb', (
      method,
      parameters,
    ) async {
      final fresh = switch (parameters['fresh']) {
        'true' => true,
        'false' => false,
        _ => freshByDefault,
      };
      final taken = await _inspector.capture(fresh: fresh);
      if (taken case _Unavailable(:final why)) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          why,
        );
      }
      final (frame, capture) = (taken as _Taken).value;
      final result = ask(capture, parameters);
      if (isRefusal(result)) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          result['refused']! as String,
        );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object?>{'frame': frame, ...result}),
      );
    }, answers: <String>{'frame', ...answers});
  }

  // What each answers beside `frame`: the keys the function in
  // `render_inspection.dart` builds, which `api/flutter3d_app.vm` holds.
  answer(
    'passes',
    freshByDefault: true,
    answers: const <String>{'width', 'height', 'passes'},
    ask: (c, _) => renderPasses(c),
  );
  answer(
    'draws',
    freshByDefault: true,
    answers: const <String>{'total', 'offset', 'draws', 'undetailed'},
    ask: renderDraws,
  );
  answer(
    'stats',
    freshByDefault: true,
    answers: const <String>{
      'width',
      'height',
      'passes',
      'activePasses',
      'drawCalls',
      'describedDraws',
      'triangles',
      'cpuMicros',
      'targetBytes',
      'targets',
      'unsizedFormats',
    },
    ask: (c, _) => renderStats(c),
  );
  answer(
    'scanNan',
    freshByDefault: true,
    answers: const <String>{'clean', 'scanned', 'eightBit', 'found', 'unread'},
    ask: renderScanNan,
  );
  answer(
    'passOutput',
    freshByDefault: false,
    answers: const <String>{
      'pass',
      'png',
      'resource',
      'width',
      'height',
      'format',
      'readable',
      'floats',
      'refused',
    },
    ask: renderPassOutput,
  );
  answer(
    'draw',
    freshByDefault: false,
    answers: const <String>{
      'index',
      'passIndex',
      'pass',
      'kind',
      'mesh',
      'material',
      'vertices',
      'indices',
      'instances',
      'lighting',
      'triangles',
      'state',
      'uniforms',
    },
    ask: renderDraw,
  );
  answer(
    'readPixel',
    freshByDefault: false,
    answers: const <String>{
      'pass',
      'resource',
      'format',
      'x',
      'y',
      'uint',
      'unorm',
      'float',
      'floatUnread',
    },
    ask: renderReadPixel,
  );
  answer(
    'capture',
    freshByDefault: false,
    answers: const <String>{'capture'},
    ask: renderCaptureFile,
  );
  // Neither of these takes a capture: the memory report reads what the
  // renderer holds now, and the views are a table.
  registerFlutter3dExtension('ext.flutter3d.render.memory', (
    method,
    parameters,
  ) async {
    final current = _inspector.renderer();
    if (current == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'the game has no renderer yet; ask again once it is drawing',
      );
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode(renderMemory(current.memoryReport(scene: _inspector.scene()))),
    );
  }, answers: const <String>{'totalBytes', 'categories', 'entries'});
  registerFlutter3dExtension(
    'ext.flutter3d.render.debugViews',
    (method, parameters) async => developer.ServiceExtensionResponse.result(
      jsonEncode(renderDebugViews()),
    ),
    answers: const <String>{'views', 'wipeSides'},
  );
  registerFlutter3dExtension('ext.flutter3d.render.pick', (
    method,
    parameters,
  ) async {
    final x = int.tryParse(parameters['x'] ?? '');
    final y = int.tryParse(parameters['y'] ?? '');
    if (x == null || y == null || x < 0 || y < 0) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'pick takes x and y, whole pixels from the top left',
      );
    }
    final picked = await _inspector.pick(x, y);
    return switch (picked) {
      _Unavailable(:final why) => developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        why,
      ),
      _Taken(value: (final frame, final capture)) =>
        developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'frame': frame,
            ...renderPicked(capture, _inspector.lastPicked, x: x, y: y),
          }),
        ),
    };
  }, answers: const <String>{'frame', 'x', 'y', 'node', 'draws', 'says'});
}

bool _registered = false;
final _Inspector _inspector = _Inspector();

sealed class _Capture {
  const _Capture();
}

final class _Taken extends _Capture {
  const _Taken(this.value);
  final (int, FrameCapture) value;
}

final class _Unavailable extends _Capture {
  const _Unavailable(this.why);
  final String why;
}

/// The one capture the extensions share, and the renderer it came from.
final class _Inspector {
  Renderer? Function() renderer = () => null;
  Scene? Function() scene = () => null;
  Duration timeout = const Duration(seconds: 2);

  (int, FrameCapture)? _held;
  Renderer? _heldFrom;
  int _frames = 0;

  Future<_Capture> capture({required bool fresh}) async {
    final current = renderer();
    if (current == null) {
      return const _Unavailable(
        'the game has no renderer yet; ask again once it is drawing',
      );
    }
    final held = _held;
    if (!fresh && held != null && identical(_heldFrom, current)) {
      return _Taken(held);
    }
    final device = current.device;
    final FrameCapture capture;
    try {
      capture = await current
          .captureNextFrame(
            draws: true,
            // Only the software backend keeps its targets as floats; on the
            // others a NaN is reported unread rather than absent.
            readFloats: device is CpuDevice ? device.readHdrPixels : null,
          )
          .timeout(timeout);
    } on TimeoutException {
      return _Unavailable(
        'no frame was drawn within ${timeout.inMilliseconds} ms; a capture '
        'is the next frame the game draws, so the game has to be drawing — '
        'a paused game that stops presenting draws nothing to capture',
      );
    } on Object catch (error) {
      return _Unavailable('the capture failed: $error');
    }
    final taken = (++_frames, capture);
    _held = taken;
    _heldFrom = current;
    return _Taken(taken);
  }

  /// What [pick] found, read by the answer that follows it.
  MeshNode? lastPicked;

  /// The node drawn at ([x], [y]) and a capture of the very frame that drew
  /// it: both asked before the frame, so the picking pass and the journal
  /// are one frame's. The frame's size comes from the capture held, or a
  /// first capture taken for it.
  Future<_Capture> pick(int x, int y) async {
    final current = renderer();
    if (current == null) {
      return const _Unavailable('the game has not opened its renderer yet');
    }
    final sized = await capture(fresh: false);
    if (sized case _Unavailable()) return sized;
    final (_, held) = (sized as _Taken).value;
    if (x >= held.width || y >= held.height) {
      return _Unavailable(
        '($x, $y) is outside the ${held.width}×${held.height} frame',
      );
    }
    final node = current.pickPixel(
      (x + 0.5) / held.width,
      (y + 0.5) / held.height,
    );
    final taken = await capture(fresh: true);
    try {
      lastPicked = await node.timeout(timeout);
    } on Object catch (error) {
      return _Unavailable('the picking pass did not answer: $error');
    }
    return taken;
  }
}
