/// Shows a `CpuTexture` by decoding it into an image.
///
/// **Moved here from `flutter3d_cpu` (mcp-02n)**, once that package went flat:
/// a Flutter-facing widget file could not stay in a package that resolves
/// without the Flutter SDK. `presentFrame` in `backend_native.dart` builds
/// one of these for a `CpuDevice`.
///
/// The round trip this backend cannot avoid and the other two can: the pixels
/// are already in CPU memory, so getting them onto the screen means handing
/// them to Flutter, which is what `decodeImageFromPixels` is. On a GPU backend
/// the same journey is what made `imageOf` the wrong contract.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show CpuTexture;

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

  /// Which decode is allowed to land. A decode is asked for on every frame,
  /// so two are routinely in flight at once, and nothing about
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
    // **Unconditionally, and that is the fix.** This used to decode only when
    // the texture instance changed — and the backend hands back the *same*
    // `CpuTexture` every frame, because a render target is a buffer it
    // reuses rather than a megabyte it allocates sixty times a second. So the
    // comparison was always "unchanged", the decode ran once in `initState`,
    // and the picture froze on the first frame ever drawn: the camera turned,
    // the document changed, the model was replaced, and the widget went on
    // showing the frame from startup. It cost nothing to see because the two
    // GPU backends present through their own path and never come here.
    //
    // A rebuild that carries no new pixels — a theme change, a parent
    // rebuilding for its own reasons — now decodes the same pixels again,
    // which is a copy and a decode of a buffer that was going to be decoded
    // on the next frame anyway. The alternative is a frame counter on the
    // texture, which is a field on a rendering type for one widget's
    // convenience; this is the cheaper thing to be wrong about.
    _decode();
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
