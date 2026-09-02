/// A shader bundle the editor keeps reading, so an edited shader shows
/// without a restart.
///
/// `--dart-define=shaders=<path>` names a `.f3dshaders` file. It is loaded
/// through `GraphicsDevice.loadShaders` before the renderer is built and
/// handed to `Renderer.create` as `materials`, so every stage it holds wins
/// the name over the engine's. Then it is watched: whenever the file's
/// modification time moves, the bytes are read again, the library is
/// refreshed in place — the handles the renderer holds are the same objects
/// afterwards, which is the contract `LoadedShaderLibrary` makes — and the
/// renderer relinks its pipelines on the next frame.
///
/// **A refused bundle keeps the previous shaders and says so.** Rebuilding a
/// bundle with a shader that no longer compiles, or with the wrong SDK, is
/// the ordinary case in an editing loop, and the right answer is a line in
/// the bar naming the file, not a black viewport.
///
/// **Polled, not watched.** `File.watch` on macOS arrives through FSEvents
/// with coalescing and a delay that varies by what wrote the file, and the
/// bundle is written twice by the tools that make it — impellerc's output and
/// then the packed container. Polling a modification time twice a second is
/// simpler, costs one `stat`, and cannot miss a write that landed between
/// two events.
///
/// The file system is behind two functions rather than reached for, so the
/// whole of the logic — when to read, what to do with a refusal, that a
/// refusal is not retried until the file changes again — is a plain test.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

final class ShaderWatch {
  ShaderWatch({
    required this.library,
    required this.modifiedAt,
    required this.readBytes,
    required this.onRefreshed,
    required this.onRefused,
    this.every = const Duration(milliseconds: 500),
  }) : _seen = modifiedAt();

  /// The library the bundle was loaded into.
  final LoadedShaderLibrary library;

  /// The file's modification time, or null while there is no file.
  final DateTime? Function() modifiedAt;

  /// The file's bytes.
  final Future<ByteData> Function() readBytes;

  /// Called after a refresh was accepted — the renderer's cue to relink.
  final void Function() onRefreshed;

  /// Called with what the device said when it refused the new bytes.
  final void Function(ShaderBundleRefused refused) onRefused;

  /// How often to look.
  final Duration every;

  /// The modification time the library currently reflects, accepted or not:
  /// a refused write is not tried again until the file moves.
  DateTime? _seen;

  Timer? _timer;

  /// Whether a refresh is in flight, so two ticks cannot read at once.
  bool _reading = false;

  /// Starts looking, [every] so often.
  void start() {
    _timer ??= Timer.periodic(every, (_) => unawaited(poll()));
  }

  /// Looks once. True when the file had changed and the library took it.
  Future<bool> poll() async {
    if (_reading) return false;
    final now = modifiedAt();
    if (now == null || now == _seen) return false;
    _reading = true;
    try {
      final bytes = await readBytes();
      // Read, then recorded: whatever the outcome, this write has been seen.
      _seen = now;
      try {
        library.refresh(bytes);
      } on ShaderBundleRefused catch (refused) {
        onRefused(refused);
        return false;
      }
      onRefreshed();
      return true;
    } finally {
      _reading = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
