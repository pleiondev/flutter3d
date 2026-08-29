/// Shows a [CpuTexture] by decoding it into an image.
///
/// The round trip this backend cannot avoid and the other two can: the pixels
/// are already in CPU memory, so getting them onto the screen means handing
/// them to Flutter, which is what `decodeImageFromPixels` is. On a GPU backend
/// the same journey is what made `imageOf` the wrong contract.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'cpu_texture.dart';

final class CpuFrame extends StatefulWidget {
  const CpuFrame({
    super.key,
    required this.texture,
    required this.fit,
    required this.quality,
  });

  final CpuTexture texture;
  final BoxFit fit;
  final FilterQuality quality;

  @override
  State<CpuFrame> createState() => _CpuFrameState();
}

class _CpuFrameState extends State<CpuFrame> {
  ui.Image? _image;

  /// Which decode is allowed to land. The backend presents a new texture every
  /// frame, so two decodes are routinely in flight at once, and nothing about
  /// `decodeImageFromPixels` promises they complete in order — a slow older
  /// frame used to overwrite the newer one that had already landed.
  int _decodeSequence = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(CpuFrame old) {
    super.didUpdateWidget(old);
    if (!identical(old.texture, widget.texture)) _decode();
  }

  void _decode() {
    final t = widget.texture;
    final bytes = Uint8List(t.width * t.height * 4);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (t.pixels[i].clamp(0.0, 1.0) * 255.0).round();
    }
    final sequence = ++_decodeSequence;
    ui.decodeImageFromPixels(
      bytes,
      t.width,
      t.height,
      ui.PixelFormat.rgba8888,
      (image) {
        // Every path that does not hand the image to `_image` must dispose it:
        // a `ui.Image` is a texture the engine holds until told otherwise, and
        // this callback fires once per presented frame — leaking here was a
        // texture per frame, not a slow drip.
        if (!mounted || sequence != _decodeSequence) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
      },
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return RawImage(
      image: image,
      fit: widget.fit,
      filterQuality: widget.quality,
    );
  }
}
