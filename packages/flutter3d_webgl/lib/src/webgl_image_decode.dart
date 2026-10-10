/// Images decoded by the browser and uploaded as they come — `A4.16`.
///
/// **The decode leaves Dart entirely.** `createImageBitmap` runs the
/// browser's own decoder, off the main thread in every engine that ships
/// one, and `texSubImage2D` takes the bitmap without its pixels ever being
/// copied into the Dart heap. The CPU path this replaces on the web decoded
/// in `dart:ui`, read the pixels back as bytes, built a mip chain in Dart and
/// uploaded every level — three passes over the image on the thread that also
/// draws the frame.
///
/// **The chain is `MipChain.build`'s, to the byte.** Level zero is read back
/// from the texture it was just written into, halved in Dart, and the levels
/// written below it. That is the chain every other backend uploads, so a
/// texture decoded here samples exactly as it does on Impeller.
///
/// It used to be `generateMipmap`, which is the driver's box: the same filter
/// in kind and not in rounding, and on a normal map the difference between a
/// level and its neighbour's was enough to move `normal-mapping` by
/// thirty-six pixels against every backend that uploads the CPU chain. One
/// read of level zero and one pass in Dart is what agreeing costs, paid once
/// per mipmapped image at load, never per frame; the decode itself stays
/// in the browser.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_resources.dart';
import 'webgl_types.dart';

/// The MIME type [bytes] announce, for the blob the browser decodes; empty
/// when they are none this recognises, which lets the browser sniff.
String encodedImageMime(Uint8List bytes) {
  if (bytes.length < 12) return '';
  if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
  if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'image/gif';
  if (bytes[0] == 0x52 && bytes[8] == 0x57) return 'image/webp';
  return '';
}

/// [encoded] decoded by the browser, scaled to fit [maxDimension] while it
/// is decoded, or null when the browser refuses it.
///
/// Straight alpha and no colour conversion — see
/// `EncodedImageUpload.decodeTexture` for why. When the header
/// states the size ([encodedImageSize]) the resize is part of the one decode;
/// when it does not, the full image is decoded and then scaled, and the
/// full-size bitmap is closed straight away.
Future<web.ImageBitmap?> decodeImageBitmap(
  Uint8List encoded, {
  int? maxDimension,
}) async {
  final mime = encodedImageMime(encoded);
  final blob = web.Blob(
    <web.BlobPart>[encoded.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );

  web.ImageBitmapOptions options({int? width, int? height}) =>
      width == null || height == null
      ? web.ImageBitmapOptions(
          premultiplyAlpha: 'none',
          colorSpaceConversion: 'none',
        )
      : web.ImageBitmapOptions(
          premultiplyAlpha: 'none',
          colorSpaceConversion: 'none',
          resizeWidth: width,
          resizeHeight: height,
          resizeQuality: 'high',
        );

  try {
    final stated = encodedImageSize(encoded);
    if (stated != null) {
      final target = cappedImageSize(
        stated.width,
        stated.height,
        maxDimension: maxDimension,
      );
      final scaled =
          target.width != stated.width || target.height != stated.height;
      return await web.window
          .createImageBitmap(
            blob,
            scaled
                ? options(width: target.width, height: target.height)
                : options(),
          )
          .toDart;
    }
    final full = await web.window.createImageBitmap(blob, options()).toDart;
    final target = cappedImageSize(
      full.width,
      full.height,
      maxDimension: maxDimension,
    );
    if (target.width == full.width && target.height == full.height) {
      return full;
    }
    try {
      return await web.window
          .createImageBitmap(
            full,
            options(width: target.width, height: target.height),
          )
          .toDart;
    } finally {
      full.close();
    }
  } catch (_) {
    // A file the browser will not decode — a format it lacks, a truncated
    // download. The caller falls back to the CPU decoder, which may know it.
    return null;
  }
}

/// A texture holding [bitmap] at level zero, and `MipChain.build`'s chain below it
/// when [mipmaps] — `EncodedImageUpload.decodeTexture` on
/// this backend. Closes [bitmap].
TextureHandle webglCreateTextureFromBitmap(
  web.WebGL2RenderingContext gl,
  List<web.WebGLTexture> persistentTextures,
  List<web.WebGLRenderbuffer> persistentRenderbuffers,
  web.ImageBitmap bitmap, {
  required bool mipmaps,
}) {
  final width = bitmap.width;
  final height = bitmap.height;
  final levels = mipmaps ? MipChain.levelsFor(width, height) + 1 : 1;
  final handle = webglCreateTexture(
    gl,
    persistentTextures,
    persistentRenderbuffers,
    RenderTargetDescriptor(
      width: width,
      height: height,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
    levels: levels,
    rendered: false,
  );
  try {
    // Bound by `webglCreateTexture` on the upload unit and still bound.
    // The unpack flags are ignored for an ImageBitmap — its own options
    // already said straight alpha and no conversion — so nothing here has to
    // be set and put back.
    gl.texSubImage2D(
      web.WebGLRenderingContext.TEXTURE_2D,
      0,
      0,
      0,
      web.WebGLRenderingContext.RGBA.toJS,
      web.WebGLRenderingContext.UNSIGNED_BYTE.toJS,
      bitmap,
    );
    if (levels > 1) {
      final texture = (handle.backend as WebGlTexture).texture;
      final base = _readLevelZero(gl, texture, width, height);
      final chain = MipChain.build(ByteData.sublistView(base), width, height);
      // Still bound on the upload unit: the read above touched only the read
      // framebuffer. Rows of RGBA8 are four-aligned at every width, so the
      // default unpack alignment holds.
      var w = width;
      var h = height;
      for (var level = 0; level < chain.length; level++) {
        w = w > 1 ? w >> 1 : 1;
        h = h > 1 ? h >> 1 : 1;
        gl.texSubImage2D(
          web.WebGLRenderingContext.TEXTURE_2D,
          level + 1,
          0,
          0,
          w.toJS,
          h.toJS,
          web.WebGLRenderingContext.RGBA.toJS,
          web.WebGLRenderingContext.UNSIGNED_BYTE,
          chain[level].buffer
              .asUint8List(chain[level].offsetInBytes, w * h * 4)
              .toJS,
        );
      }
      gl.texParameteri(
        web.WebGLRenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_MAX_LEVEL,
        levels - 1,
      );
    }
  } finally {
    bitmap.close();
  }
  return handle;
}

/// Level zero of [texture], [width] by [height] RGBA8, read back through a
/// framebuffer of its own: row zero first, as it was written, which is the
/// order `MipChain.build` reads.
Uint8List _readLevelZero(
  web.WebGL2RenderingContext gl,
  web.WebGLTexture? texture,
  int width,
  int height,
) {
  final pixels = Uint8List(width * height * 4);
  final framebuffer = gl.createFramebuffer();
  gl
    ..bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, framebuffer)
    ..framebufferTexture2D(
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      web.WebGLRenderingContext.COLOR_ATTACHMENT0,
      web.WebGLRenderingContext.TEXTURE_2D,
      texture,
      0,
    );
  try {
    gl.readPixels(
      0,
      0,
      width,
      height,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      pixels.toJS,
    );
  } finally {
    gl
      ..bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null)
      ..deleteFramebuffer(framebuffer);
  }
  return pixels;
}
