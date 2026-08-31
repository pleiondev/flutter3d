/// Encoding raw pixels as a PNG, for the two paths that write files.
///
/// The renderer used to hand back a `ui.Image`, so writing a PNG was one call
/// on it. It hands back a texture now — because one backend cannot produce an
/// image without a round trip that costs more than the frame — so the pixels
/// arrive as bytes and this puts them through `dart:ui` to be encoded.
///
/// That round trip is the expensive one, and it is affordable here for a reason
/// worth stating: this runs when a golden is **recorded or has failed**, and
/// when a debug capture is taken. Never per frame.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Encodes [rgba] — premultiplied RGBA8, row-major from the top-left, as
/// `GraphicsDevice.readPixels` returns it — as a PNG.
Future<Uint8List?> encodePng(ByteData rgba, int width, int height) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba.buffer.asUint8List(),
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
