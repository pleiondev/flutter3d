/// Puts the renderer's own frame on the VM service as `ext.flutter3d.render.*`
/// — `P12`.
///
/// **The frame the player sees, not a second one drawn for the tool.** The
/// diagnostic renderers in `flutter3d_sim_mcp` and `flutter3d_editor_mcp` draw
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
/// Seven extensions, each `ext.flutter3d.render.<verb>`, string parameters as
/// the protocol requires:
///
/// * `passes`, `draws`, `stats`, `scanNan` — take a fresh capture unless
///   `fresh=false` and one is held.
/// * `passOutput`, `draw`, `readPixel` — read the capture already held, so an
///   index from `draws` or a pass from `passes` means the same frame; pass
///   `fresh=true` to take a new one. With none held they take one.
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

import 'render_inspection.dart';

/// Registers `ext.flutter3d.render.*` against whatever [renderer] answers at
/// the moment of each request — null while the game's renderer has not
/// opened, which is refused with that reason.
///
/// Calling it again replaces the getter rather than registering twice, which
/// `registerExtension` would refuse: a game that builds its renderer again,
/// or a second screen with its own, points the same extensions at the new
/// one.
void registerRenderExtensions(
  Renderer? Function() renderer, {
  Duration timeout = const Duration(seconds: 2),
}) {
  _inspector.renderer = renderer;
  _inspector.timeout = timeout;
  if (_registered) return;
  _registered = true;

  void answer(
    String verb, {
    required bool freshByDefault,
    required Map<String, Object?> Function(
      FrameCapture capture,
      Map<String, String> parameters,
    )
    ask,
  }) {
    developer.registerExtension('ext.flutter3d.render.$verb', (
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
    });
  }

  answer('passes', freshByDefault: true, ask: (c, _) => renderPasses(c));
  answer('draws', freshByDefault: true, ask: renderDraws);
  answer('stats', freshByDefault: true, ask: (c, _) => renderStats(c));
  answer('scanNan', freshByDefault: true, ask: renderScanNan);
  answer('passOutput', freshByDefault: false, ask: renderPassOutput);
  answer('draw', freshByDefault: false, ask: renderDraw);
  answer('readPixel', freshByDefault: false, ask: renderReadPixel);
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
}
