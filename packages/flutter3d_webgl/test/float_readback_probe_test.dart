/// Whether a float colour buffer reads back as the floats written into it.
///
///     flutter test --platform chrome test/float_readback_probe_test.dart
///
/// **The second half of a measurement, not a check of this backend.** The
/// engine's `readback` contract admits only eight-bit RGBA, and `readback.dart`
/// argues the case from this backend: a half-float target read through
/// `readPixels(RGBA, UNSIGNED_BYTE)` is an `INVALID_OPERATION` that leaves the
/// pack buffer at the zeros it was made with, so the future completes with a
/// black picture. That is true of *that* combination and says nothing about
/// the one WebGL2 actually offers for a float buffer, which is `RGBA` with
/// `FLOAT`. Nothing in this repository had ever asked for it.
///
/// The same question was put to Impeller by
/// `packages/flutter3d/example/lib/float_readback_probe.dart`, and the answer
/// there was yes with a trap: the read arrives through a `ui.Image` tagged
/// premultiplied, so every channel comes back divided by the fourth one and a
/// fourth channel of zero destroys the pixel. This path has no `ui.Image` in
/// it at all, so it should have no such division — and "should" is why this
/// runs rather than being reasoned about. Written against the raw context
/// rather than through `WebGlDevice` on purpose: the device hardcodes
/// `UNSIGNED_BYTE` at every one of its three read sites, so going through it
/// would measure the choice instead of the capability.
///
/// This asserts what the numbers should be, so that a browser that disagrees
/// says so instead of being believed. The verdict belongs beside Impeller's,
/// and together they decide whether the contract's refusal is a limit or a
/// choice.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('a float colour buffer reads back as the floats written into it', () {
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = 4
      ..height = 4;
    final gl = canvas.getContext('webgl2') as web.WebGL2RenderingContext?;
    if (gl == null) fail('no WebGL2 context in this browser');

    // Without it a float texture is not a renderable format at all, which is
    // the same extension the device demands before it will open a context.
    if (gl.getExtension('EXT_color_buffer_float') == null) {
      fail('EXT_color_buffer_float is missing, so nothing float is renderable');
    }

    // The values Impeller was asked for, so the two answers are comparable:
    // above one and below zero to catch a clamp, a fourth channel of a half to
    // catch a division, and a fourth channel of zero because that is where a
    // premultiplied reading cannot even pretend — and because in XPBD an
    // inverse mass of zero is a pinned particle rather than an edge case.
    const List<(double, double, double, double)> clears =
        <(double, double, double, double)>[
          (2.5, -1.25, 1000.5, 0.5),
          (0.75, -0.5, 3.25, 0.0),
          (0.25, 0.5, 0.75, 1.0),
        ];

    for (final (double r, double g, double b, double a) in clears) {
      final texture = gl.createTexture();
      gl.bindTexture(web.WebGL2RenderingContext.TEXTURE_2D, texture);
      gl.texStorage2D(
        web.WebGL2RenderingContext.TEXTURE_2D,
        1,
        web.WebGL2RenderingContext.RGBA32F,
        4,
        4,
      );

      final framebuffer = gl.createFramebuffer();
      gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, framebuffer);
      gl.framebufferTexture2D(
        web.WebGL2RenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        web.WebGL2RenderingContext.TEXTURE_2D,
        texture,
        0,
      );

      gl.clearColor(r, g, b, a);
      gl.clear(web.WebGLRenderingContext.COLOR_BUFFER_BIT);

      final pixels = Float32List(4 * 4 * 4);
      final js = pixels.toJS;
      gl.readPixels(
        0,
        0,
        4,
        4,
        web.WebGLRenderingContext.RGBA,
        web.WebGLRenderingContext.FLOAT,
        js,
      );
      final int error = gl.getError();
      final List<double> read = js.toDart.sublist(0, 4);

      // ignore: avoid_print
      print(
        'wrote [$r, $g, $b, $a] -> $read'
        '${error == 0 ? '' : '  glError=$error'}',
      );

      expect(error, 0, reason: 'readPixels(RGBA, FLOAT) raised $error');
      expect(read[0], closeTo(r, 1e-5), reason: 'red did not survive');
      expect(read[1], closeTo(g, 1e-5), reason: 'green did not survive');
      expect(read[2], closeTo(b, 1e-3), reason: 'blue did not survive');
      expect(read[3], closeTo(a, 1e-5), reason: 'alpha did not survive');

      gl.deleteFramebuffer(framebuffer);
      gl.deleteTexture(texture);
    }
  });
}
