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
    ui.decodeImageFromPixels(
      bytes,
      t.width,
      t.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) setState(() => _image = image);
      },
    );
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
