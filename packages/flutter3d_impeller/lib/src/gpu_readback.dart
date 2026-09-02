/// `GraphicsDevice.readback` on flutter_gpu: a queued copy into a staging
/// texture, and the bytes taken off it once the queue says the copy ran.
///
/// **`copyTextureToBuffer` is a dead end here, and that is worth stating
/// because it is the obvious tool.** flutter_gpu 3.47 has the copy — a
/// `TextureRegion` into a `DeviceBuffer` — and no way for Dart to read a
/// `DeviceBuffer` afterwards: `DeviceBuffer` has `overwrite` and `flush` and
/// nothing that goes the other way. The bytes land in GPU memory and stay
/// there. So the copy goes texture to texture instead, into a staging texture
/// this file owns, and the only route from a texture to Dart memory — the one
/// `readPixels` already takes — is taken from the staging copy rather than from
/// the live target.
///
/// That still buys both halves of the contract. The copy is a command on a
/// command buffer submitted in order, so it reads the target as the passes
/// before it left it, whatever draws into the target afterwards; and nothing
/// blocks — `submit` hands the buffer to the queue and comes back, and the
/// completion callback is where the bytes are asked for. By the time
/// `toByteData` runs, the staging texture has been written and nothing else
/// will ever write it until it is handed out again, which happens only after
/// the bytes are out.
///
/// Staging textures are pooled by size and format rather than made per call:
/// a meter reads a 64×64 target every frame, and flutter_gpu has no dispose, so
/// one allocation per frame would be one 16 KB texture per frame for the
/// collector. The pool grows to however many readbacks are in flight at once —
/// two, for a caller that asks every frame and hears back a frame later.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'gpu_texture.dart';

/// The staging pool and the copy. One per device.
final class GpuReadback {
  GpuReadback({required this.onRejectedSubmission});

  /// Told when the queue refuses the copy, so the device's own counter of
  /// refused buffers stays the one place that number lives.
  final void Function() onRejectedSubmission;

  /// Staging textures nothing is copying into or reading from, by size and
  /// format.
  final Map<String, List<TextureHandle>> _idle = <String, List<TextureHandle>>{};

  /// How many staging textures exist, in the pool or in flight. Diagnostic:
  /// a number that climbs is a caller asking faster than the queue answers.
  int get debugStagingCount => _made;
  int _made = 0;

  Future<ByteData> read(TextureHandle texture, ScreenRect? region) {
    final rect = readbackRegionOf(texture, region);
    final staging = _take(rect.width, rect.height, texture.format);

    final buffer = gpu.gpuContext.createCommandBuffer();
    buffer.copyTextureToTexture(
      gpu.TextureRegion(
        texture.gpuTexture,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
      ),
      gpu.TextureDestinationRegion(staging.gpuTexture),
    );

    final completer = Completer<ByteData>();
    buffer.submit(
      completionCallback: (bool ok) {
        if (!ok) {
          onRejectedSubmission();
          _give(staging);
          completer.completeError(
            StateError('the GPU refused the command buffer carrying a readback'),
          );
          return;
        }
        // The same route `readPixels` takes, off a texture nothing is drawing
        // into. Closed once the bytes are out, for the reason given there: a
        // handle left open is a `ui.Image` for the collector per readback.
        final image = staging.gpuTexture.asImage();
        image
            .toByteData(format: ui.ImageByteFormat.rawRgba)
            .then(
              (ByteData? bytes) {
                if (bytes == null) {
                  completer.completeError(
                    StateError('the staging texture read back as nothing'),
                  );
                } else {
                  completer.complete(bytes);
                }
              },
              onError: (Object error, StackTrace stack) =>
                  completer.completeError(error, stack),
            )
            .whenComplete(() {
              image.dispose();
              _give(staging);
            });
      },
    );
    return completer.future;
  }

  String _keyFor(int width, int height, TextureFormat format) =>
      '${width}x$height/${format.name}';

  TextureHandle _take(int width, int height, TextureFormat format) {
    final idle = _idle[_keyFor(width, height, format)];
    if (idle != null && idle.isNotEmpty) return idle.removeLast();
    _made++;
    return createGpuTexture(
      StorageMode.devicePrivate,
      width,
      height,
      format: format,
      // Nothing renders into it, and `asImage` insists on shader read.
      enableRenderTargetUsage: false,
    );
  }

  void _give(TextureHandle staging) => _idle
      .putIfAbsent(
        _keyFor(staging.width, staging.height, staging.format),
        () => <TextureHandle>[],
      )
      .add(staging);
}
