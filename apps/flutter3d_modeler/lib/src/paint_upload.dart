/// `pro-pt-03`'s remaining half: the texture a paint stroke changed, written
/// back over the rectangle it changed and no more.
///
/// **A decode and a whole upload per stroke is the difference between
/// painting and waiting.** `MaterialPool` keys its textures by the bytes'
/// own hash, so a stroke that rewrites the base-colour image looks to it
/// like a different image: it decodes a 4K PNG and uploads four megabytes
/// for a mark a hundred texels across. What is actually needed is the tiles
/// the stroke replaced — which the paint stack already knows, because
/// copy-on-write is what it is built out of.
///
/// **Once per stroke, not once per sample.** A drag reports a sample per
/// pointer move; uploading on each would be sixty writes a second for one
/// gesture, and the picture on screen only has to be right by the time the
/// pointer comes up. The dirty rectangle is the union over the whole drag,
/// so a stroke that wandered across the model still costs one write.
///
/// **What this does not do is mips.** `overwriteTexture` refuses any level
/// but zero, and deliberately: patching one level of a chain leaves the rest
/// stale with nothing saying so. A painted texture is sampled at level zero
/// while it is being painted; the chain is rebuilt when the pool next
/// uploads the image whole, which is what a save and a reopen already do.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// The rectangle one stroke changed, and the one write it costs.
class PaintUpload {
  PaintUpload({required this.device});

  final GraphicsDevice device;

  PaintStack? _before;
  int? _canvas;

  /// The stack as it was when the stroke opened — what the tiles are
  /// compared against when it closes.
  void opened(PaintStack? stack, {required int canvas}) {
    _before = stack;
    _canvas = canvas;
  }

  /// Writes what changed between [opened] and [now] into [texture].
  ///
  /// [flattened] is the whole canvas as straight RGBA8, the same bytes the
  /// stack flattens to; only the dirty rectangle's own rows are sent.
  /// Answers how many texels were written — zero when nothing changed, which
  /// is what a drag that never reached the mesh leaves behind.
  Future<int> flush(
    TextureHandle texture,
    PaintStack? now,
    Uint8List flattened,
  ) async {
    final int? canvas = _canvas;
    if (canvas == null || now == null) return 0;
    final rect = dirtyRectOf(dirtyTilesBetween(_before, now), canvas);
    _before = null;
    _canvas = null;
    if (rect == null) return 0;

    final (int x, int y, int width, int height) = rect;
    // The region's own rows, cut out of the flattened canvas: a region write
    // takes the bytes for that region and nothing else, so the rows are
    // packed here rather than sent with the whole canvas's stride.
    final patch = Uint8List(width * height * 4);
    for (var row = 0; row < height; row++) {
      final int from = ((y + row) * canvas + x) * 4;
      patch.setRange(row * width * 4, (row + 1) * width * 4, flattened, from);
    }
    await device.overwriteTexture(
      texture,
      ByteData.view(patch.buffer),
      region: ScreenRect(x: x, y: y, width: width, height: height),
    );
    return width * height;
  }
}
