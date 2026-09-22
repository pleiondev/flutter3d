/// `bakeTextureGraph`/`bakeTextureFull`: `mat-11`'s own CPU compositor.
///
///     dart test test/texture_bake_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Uint8List _chunk(String type, List<int> data) {
  final out = BytesBuilder();
  out.add(
    (ByteData(4)..setUint32(0, data.length, Endian.big)).buffer.asUint8List(),
  );
  out.add(ascii.encode(type));
  out.add(data);
  out.add(const <int>[0, 0, 0, 0]);
  return out.toBytes();
}

/// A tiny solid-colour PNG, compressed through `dart:io`'s own `ZLibCodec` —
/// the same independent-encoder pattern `png_decoder_test.dart` already
/// uses, since this package has no compressor of its own to build a
/// fixture with instead.
Uint8List _solidPng(int r, int g, int b) {
  final row = <int>[0, r, g, b];
  final out = BytesBuilder();
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, 1)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  out.add(_chunk('IHDR', ihdr.buffer.asUint8List()));
  out.add(_chunk('IDAT', ZLibCodec().encode(row)));
  out.add(_chunk('IEND', const <int>[]));
  return out.toBytes();
}

final Uint8List _redPng = _solidPng(255, 0, 0);
final Uint8List _bluePng = _solidPng(0, 0, 255);

void main() {
  group('determinism', () {
    test('two runs of the same graph are byte-identical', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          const NoiseTextureNode(id: 2, seed: 7, scale: 3),
          NormalFromHeightTextureNode(id: 3, height: 2, strength: 1.5),
          BlendTextureNode(id: 4, base: 1, overlay: 3, factor: 0.5),
          const OutputTextureNode(id: 5, result: 4),
        ],
      );
      final images = <int, Uint8List>{0: _redPng};

      final first = bakeTextureGraph(graph, 5, images, size: 32);
      final second = bakeTextureGraph(graph, 5, images, size: 32);
      expect(first, isNotNull);
      expect(second, first);
    });

    test('the isolate path (bakeTextureFull) agrees with the synchronous '
        'one', () async {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          const OutputTextureNode(id: 2, result: 1),
        ],
      );
      final images = <int, Uint8List>{0: _redPng};

      final sync = bakeTextureGraph(graph, 2, images, size: 16);
      final viaIsolate = await bakeTextureFull(graph, 2, images, size: 16);
      expect(viaIsolate, sync);
    });
  });

  group('the structural-hash cache', () {
    test('editing a Blend node\'s own factor does not re-decode its Image '
        'input', () {
      // Mutation: key the cache by node id instead of structural content,
      // or drop the cache lookup before `_evalImage` runs — either way an
      // Image node would be redecoded with whatever `images` currently
      // holds rather than reusing what a shared cache already has, which
      // is exactly what this test would then fail to catch.
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          ColorTextureNode(id: 4, value: Vector4(0.5, 0.5, 0.5, 1)),
          BlendTextureNode(id: 2, base: 1, overlay: 4, factor: 0.3),
          const OutputTextureNode(id: 3, result: 2),
        ],
      );
      final cache = TextureBakeCache();
      final images = <int, Uint8List>{0: _redPng};

      final first = bakeTextureGraph(graph, 3, images, size: 1, cache: cache)!;

      // A structurally identical Image node (same id, same imageId), a
      // different Blend factor, and — the point of the test — a
      // *different* image behind the same id. If the cache is keyed the
      // way it claims to be, the Image node's own cached raster answers
      // for it again rather than this new red-free picture.
      final edited = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          ColorTextureNode(id: 4, value: Vector4(0.5, 0.5, 0.5, 1)),
          BlendTextureNode(id: 2, base: 1, overlay: 4, factor: 0.7),
          const OutputTextureNode(id: 3, result: 2),
        ],
      );
      final swappedImages = <int, Uint8List>{0: _bluePng};
      final second = bakeTextureGraph(
        edited,
        3,
        swappedImages,
        size: 1,
        cache: cache,
      )!;

      // Worked out by hand: red is linear 1.0 on its own channel, so a
      // cached Image gives base-red = 1.0 regardless of `swappedImages`;
      // an actually-redecoded Image would answer 0.0 (blue has no red).
      // result_red (linear) = base_red * (1 - factor) + 0.5 * factor,
      // then sRGB-encoded the same way the bake's own output pass does —
      // this reads back what the pixel *should* be if the cache reused
      // pngA's own red, not a bare linear-to-byte guess.
      final linearRed = 1.0 * (1 - 0.7) + 0.5 * 0.7;
      final expectedRed = (1.055 * math.pow(linearRed, 1 / 2.4) - 0.055) * 255;
      expect(first, isNot(second));
      expect(second[0], closeTo(expectedRed, 1));
    });

    test('a fresh cache and a reused one answer the same bytes', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          const OutputTextureNode(id: 2, result: 1),
        ],
      );
      final images = <int, Uint8List>{0: _redPng};
      final withoutCache = bakeTextureGraph(graph, 2, images, size: 8);
      final withCache = bakeTextureGraph(
        graph,
        2,
        images,
        size: 8,
        cache: TextureBakeCache(),
      );
      expect(withCache, withoutCache);
    });
  });

  group('refused, by value', () {
    test('a graph with a cycle', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[const InvertTextureNode(id: 1, source: 1)],
      );
      expect(bakeTextureGraph(graph, 1, const <int, Uint8List>{}), isNull);
    });

    test('an output node id nothing in the graph has', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          ColorTextureNode(id: 1, value: Vector4(1, 1, 1, 1)),
        ],
      );
      expect(bakeTextureGraph(graph, 99, const <int, Uint8List>{}), isNull);
    });
  });

  group('individual nodes, worked out by hand', () {
    test('Color fills every pixel with its own value', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          ColorTextureNode(id: 1, value: Vector4(1, 0, 0, 1)),
          const OutputTextureNode(id: 2, result: 1),
        ],
      );
      final rgba = bakeTextureGraph(
        graph,
        2,
        const <int, Uint8List>{},
        size: 4,
      )!;
      for (var i = 0; i < rgba.length; i += 4) {
        expect(rgba[i], 255, reason: 'pixel ${i ~/ 4} red');
        expect(rgba[i + 1], 0, reason: 'pixel ${i ~/ 4} green');
        expect(rgba[i + 3], 255, reason: 'pixel ${i ~/ 4} alpha');
      }
    });

    test('Invert on a Levels-remapped Noise stays in 0..255', () {
      // Not a value check — a range and non-crash check for the one node
      // chain in this file with no hand-computable single expected pixel
      // (noise is deterministic, not simple).
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const NoiseTextureNode(id: 1, seed: 3, scale: 5),
          const LevelsTextureNode(
            id: 2,
            source: 1,
            blackPoint: 0.2,
            whitePoint: 0.8,
          ),
          const InvertTextureNode(id: 3, source: 2),
          NormalFromHeightTextureNode(id: 4, height: 3),
          const OutputTextureNode(id: 5, result: 4),
        ],
      );
      final rgba = bakeTextureGraph(
        graph,
        5,
        const <int, Uint8List>{},
        size: 16,
      )!;
      expect(rgba, everyElement(inInclusiveRange(0, 255)));
    });

    test('Noise actually varies across the image, not just across runs', () {
      // Mutation: have the noise hash ignore its own coordinates and answer
      // a constant — "two runs byte-identical" up above would still pass,
      // since a constant is trivially deterministic; only a check that the
      // picture is not flat catches it.
      // Baked by its own id rather than through an Output node — Output
      // takes a colour input and Noise answers a scalar one.
      final graph = TextureGraph(
        nodes: <TextureNode>[const NoiseTextureNode(id: 1, seed: 1, scale: 8)],
      );
      final rgba = bakeTextureGraph(
        graph,
        1,
        const <int, Uint8List>{},
        size: 16,
      )!;
      final reds = <int>{for (var i = 0; i < rgba.length; i += 4) rgba[i]};
      expect(reds.length, greaterThan(1));
    });

    test('Checker alternates at its own cell boundary', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          CheckerTextureNode(
            id: 1,
            colorA: Vector4(1, 1, 1, 1),
            colorB: Vector4(0, 0, 0, 1),
            scale: 2,
          ),
          const OutputTextureNode(id: 2, result: 1),
        ],
      );
      final rgba = bakeTextureGraph(
        graph,
        2,
        const <int, Uint8List>{},
        size: 4,
      )!;
      // scale 2 over a 4-wide image: cell = floor(u*2); u = (x+0.5)/4, so
      // x=0,1 fall in cell 0 and x=2,3 in cell 1 along each axis.
      // Mutation: use `x` instead of `(x+0.5)/size` for `u` — the cell
      // boundary shifts by half a pixel and this exact pixel disagrees.
      expect(rgba[0], 255); // (0,0): cell 0+0=0, even -> colorA (white)
      expect(rgba.sublist(2 * 4, 2 * 4 + 1), <int>[
        0,
      ]); // (2,0): cell 1+0=1, odd -> colorB
    });

    test('an unwired Blend input reads as fully transparent black', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          ColorTextureNode(id: 1, value: Vector4(1, 1, 1, 1)),
          const BlendTextureNode(
            id: 2,
            base: 1,
            mode: TextureBlendMode.normal,
            factor: 1.0,
          ),
          const OutputTextureNode(id: 3, result: 2),
        ],
      );
      final rgba = bakeTextureGraph(
        graph,
        3,
        const <int, Uint8List>{},
        size: 1,
      )!;
      // mode normal, factor 1: result = overlay, and overlay is unwired
      // (0,0,0,0) — full black, zero alpha.
      expect(rgba, <int>[0, 0, 0, 0]);
    });
  });
}
