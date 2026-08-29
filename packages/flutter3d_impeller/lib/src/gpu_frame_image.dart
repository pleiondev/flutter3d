/// The widget that shows a frame, and owns the [ui.Image] doing it.
///
/// `present` used to make the image inline — `asImage()` straight into a
/// `RawImage` — and nothing ever disposed it, so every frame minted a fresh
/// `ui.Image` for the collector to find. The image is only a handle over the
/// same GPU allocation the pass wrote, but an undisposed handle pins that
/// texture in the engine's image accounting past the frames-in-flight ring,
/// and sixty of them a second is churn with a deadline. A `StatefulWidget` is
/// the smallest thing in Flutter with a place to dispose from, so the image
/// lives here: made when the handle arrives, closed when the handle changes,
/// closed again when the widget goes.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'gpu_texture.dart';

/// A [RawImage] over the flutter_gpu texture inside [frame].
///
/// The backend's `present` returns one of these; nothing else should need to.
final class GpuFrameImage extends StatefulWidget {
  const GpuFrameImage({
    super.key,
    required this.frame,
    required this.fit,
    required this.quality,
  });

  /// The texture to show — a handle this backend made, or the first build
  /// throws the way any fake crossing the seam does.
  final TextureHandle frame;

  final BoxFit fit;
  final FilterQuality quality;

  @override
  State<GpuFrameImage> createState() => _GpuFrameImageState();
}

final class _GpuFrameImageState extends State<GpuFrameImage> {
  /// `asImage` is the cheap half of Impeller: the image is the same GPU
  /// allocation the pass wrote, not a copy, so presenting costs a widget and
  /// nothing else. That this is free here is exactly why the contract used
  /// to say `ui.Image` — and exactly why saying so was a mistake.
  late ui.Image _image = widget.frame.gpuTexture.asImage();

  @override
  void didUpdateWidget(GpuFrameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // By identity, which is how handles compare everywhere in this engine —
    // see `texture_handle_identity_test.dart`. The renderer's ring hands a
    // different handle every frame, so this is the every-frame path.
    if (!identical(oldWidget.frame, widget.frame)) {
      // Disposing only closes this handle to the texture; the backend still
      // owns the GPU allocation, and the frames-in-flight ring is what says
      // when *that* may be drawn into again. What this releases is the
      // engine-side image bookkeeping that would otherwise wait for the
      // collector.
      _image.dispose();
      _image = widget.frame.gpuTexture.asImage();
    }
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _image, fit: widget.fit, filterQuality: widget.quality);
}
