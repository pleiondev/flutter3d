/// What `WebGpuDevice` does with what the browser says about it.
///
/// **WebGPU answers late.** A pipeline, a texture, a submit and a shader module
/// are all handed back at once whether or not the browser accepted them, and
/// the verdict arrives as a promise: an error scope popped, a module's
/// compilation info, an `uncapturederror` event. Before 1.0 the device kept
/// every one of those promises in a list and every complaint in another, and
/// only `debugDrainErrors` — which production never calls — emptied either:
/// several futures a frame for the life of the tab, and every refusal unread.
///
/// The ledger keeps the two apart and empties both:
///
/// - a verdict in flight ([track]) leaves [inFlight] the moment it settles;
/// - a complaint that has settled ([complain], [complainOfShader]) is handed
///   over at the next frame by [takeFrame], as a typed refusal: a
///   [ShaderCompileException] when the browser would not compile some WGSL,
///   since that is the cause the pipelines built from it then report, and a
///   [DeviceResourceException] for anything else it refused. A device that is
///   lost says so on `GraphicsDevice.lost`, and [takeFrame] then throws
///   nothing, because the loss is the news and the refusals are its echo.
///
/// Pure Dart, so a VM test holds it: the device needs a browser with WebGPU
/// to open, and this does not.
library;

import 'dart:async';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ShaderCompileException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show DeviceResourceException;

/// The verdicts one `WebGpuDevice` is waiting for, and the complaints it has
/// not yet handed over.
final class WebGpuErrorLedger {
  /// A ledger for a device that names itself [backend] in what it throws.
  WebGpuErrorLedger({required this.backend});

  /// Who refused, as the thrown exceptions say it.
  final String backend;

  /// How many complaints one frame keeps; the rest are counted.
  ///
  /// A frame whose every draw is refused would otherwise hold a sentence per
  /// draw, and nobody reads past the first few: they are one mistake.
  static const int maxHeld = 32;

  final Set<Future<void>> _inFlight = <Future<void>>{};
  final List<_Complaint> _held = <_Complaint>[];
  int _dropped = 0;

  /// How many verdicts have not settled yet.
  int get inFlight => _inFlight.length;

  /// How many complaints are waiting for [takeFrame], up to [maxHeld].
  int get held => _held.length;

  /// Waits for [verdict] without keeping it once it has settled.
  ///
  /// A verdict that rejects is itself a complaint: a promise the browser
  /// rejected is something it refused, and an uncaught rejection would
  /// otherwise surface in a zone nobody is watching.
  void track(Future<void> verdict) {
    late final Future<void> settled;
    settled = verdict
        .then<void>(
          (_) {},
          onError: (Object error) =>
              complain('a call it answered later', '$error'),
        )
        .whenComplete(() => _inFlight.remove(settled));
    _inFlight.add(settled);
  }

  /// Files what the browser said of [what].
  void complain(String what, String message) =>
      _hold(_Complaint(what, message));

  /// Files what the browser's compiler said of the WGSL of [shader]; [log]
  /// is where and what (`line 3, column 7: …`).
  void complainOfShader(String shader, String log) =>
      _hold(_Complaint('the WGSL of "$shader"', log, shader: shader));

  void _hold(_Complaint complaint) {
    if (_held.length < maxHeld) {
      _held.add(complaint);
    } else {
      _dropped++;
    }
  }

  /// Hands over everything that settled since the last frame, as one typed
  /// refusal, and forgets it.
  ///
  /// Called by `beginFrame`, so a refusal is thrown once, at the start of the
  /// frame after the call the browser refused: the earliest point a
  /// synchronous caller can hear an asynchronous answer. With [deviceLost]
  /// the complaints are dropped instead; the loss is reported on
  /// `GraphicsDevice.lost`.
  void takeFrame({bool deviceLost = false}) {
    if (_held.isEmpty) return;
    final taken = List<_Complaint>.of(_held);
    final dropped = _dropped;
    _held.clear();
    _dropped = 0;
    if (deviceLost) return;

    final said = <String>[
      for (final complaint in taken) complaint.said,
      if (dropped > 0) 'and $dropped more',
    ].join('; ');
    final shaders = <String>{
      for (final complaint in taken)
        if (complaint.shader case final String shader) shader,
    };
    if (shaders.isNotEmpty) {
      throw ShaderCompileException(
        shader: shaders.join(', '),
        backend: backend,
        log: said,
      );
    }
    throw DeviceResourceException(
      operation: taken.first.what,
      backend: backend,
      reason: taken.length == 1 && dropped == 0 ? taken.first.message : said,
    );
  }

  /// Everything said since the last drain, or null when nothing was, after
  /// waiting for every verdict in flight — what `debugDrainErrors` answers.
  Future<String?> debugDrain([String where = '']) async {
    await Future.wait(List<Future<void>>.of(_inFlight));
    if (_held.isEmpty) return null;
    final said = <String>[
      for (final complaint in _held) complaint.said,
      if (_dropped > 0) 'and $_dropped more',
    ].join('; ');
    _held.clear();
    _dropped = 0;
    return where.isEmpty ? said : '$where: $said';
  }
}

/// One thing the browser said: of [what], [message]; [shader] when it was
/// the compiler, about that stage.
final class _Complaint {
  const _Complaint(this.what, this.message, {this.shader});

  final String what;
  final String message;
  final String? shader;

  String get said => '$what: $message';
}
