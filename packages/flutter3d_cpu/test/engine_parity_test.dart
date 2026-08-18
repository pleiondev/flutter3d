/// The engine, drawing through a backend with no GPU under it.
///
///     flutter test test/engine_parity_test.dart
///
/// The point is not the picture. It is that `Renderer` runs at all against an
/// implementation of `GraphicsDevice` that shares no code, no vocabulary and no
/// vendor with the two it was written against — no GLSL, no driver, no
/// framebuffer. Whatever the engine still assumes about a GPU shows up here as
/// a crash or a wrong shape, and nowhere else.
///
/// The reference grid is Impeller's, recorded by `parity_main.dart` in the
/// engine's example and copied here rather than imported: this package does not
/// depend on the other backends, and a backend that needed a sibling to be
/// tested would not be much of a backend.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

/// Average luminance per cell, row-major from the top, as Impeller drew the
/// `plain` fixture.
const List<int> kImpellerPlain = <int>[
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, //
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 72, 148, 37, 4, 4,
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 94, 159, 109, 4, 4,
  4, 4, 4, 4, 4, 4, 52, 125, 128, 54, 5, 32, 82, 71, 4, 4,
  4, 4, 4, 4, 4, 59, 168, 178, 182, 184, 71, 15, 21, 6, 4, 4,
  4, 4, 4, 4, 9, 137, 166, 174, 179, 181, 172, 13, 4, 4, 4, 4,
  4, 4, 4, 4, 32, 138, 159, 168, 174, 177, 178, 64, 4, 4, 4, 4,
  4, 4, 4, 4, 30, 121, 149, 160, 167, 171, 172, 87, 4, 4, 4, 4,
  4, 4, 4, 4, 16, 88, 132, 148, 157, 162, 163, 81, 4, 4, 4, 4,
  4, 4, 4, 4, 11, 43, 100, 129, 142, 148, 148, 47, 4, 4, 4, 4,
  4, 4, 4, 4, 4, 25, 45, 88, 112, 121, 105, 8, 4, 4, 4, 4,
  4, 4, 4, 4, 4, 11, 26, 31, 49, 54, 19, 4, 4, 4, 4, 4,
  4, 4, 4, 4, 4, 4, 9, 18, 18, 9, 4, 4, 4, 4, 4, 4,
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
];

CpuDevice _device() => CpuDevice(
      width: kParityWidth,
      height: kParityHeight,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

Renderer _renderer(CpuDevice device) {
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      )!;
  return Renderer.create(
    device: device,
    fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
    fallbackNormal: texel(<int>[128, 128, 255, 255]),
  );
}

void main() {
  test('the engine starts on a device that has never seen a GPU', () {
    // Separate from the drawing test on purpose. `Renderer.create` resolves
    // every shader name and builds the pipelines it always needs; if that is
    // where a backend dies, "the picture is wrong" is the wrong headline.
    expect(() => _renderer(_device()), returnsNormally);
  });

  test('it draws the plain fixture', () async {
    final device = _device();
    final renderer = _renderer(device);
    final built = buildParityScene(device, which: ParityScene.plain);

    final result = renderer.render(
      width: kParityWidth,
      height: kParityHeight,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: paritySettingsFor(ParityScene.plain),
    );

    // Draw calls, because a frame that never drew and a frame drawn black are
    // the same picture and different numbers.
    // ignore: avoid_print
    print('cpu plain: ${result.drawCalls} draws, ${result.pipelines} pipelines');

    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    final mine = parityGrid(
      pixels!.buffer.asUint8List(),
      kParityWidth,
      kParityHeight,
    );

    var worst = 0;
    var worstAt = -1;
    var total = 0;
    for (var i = 0; i < mine.length; i++) {
      final delta = (mine[i] - kImpellerPlain[i]).abs();
      total += delta;
      if (delta > worst) {
        worst = delta;
        worstAt = i;
      }
    }
    // ignore: avoid_print
    print('parity plain: mean ${(total / mine.length).toStringAsFixed(2)}, '
        'worst $worst at cell ${worstAt ~/ kParityGrid},'
        '${worstAt % kParityGrid}');
    // ignore: avoid_print
    print('cpu rows 5,8: ${mine.sublist(5 * kParityGrid, 6 * kParityGrid)}\n'
        '              ${mine.sublist(8 * kParityGrid, 9 * kParityGrid)}');

    // Five and 0.3. Measured at 3 and 0.12 — against WebGL's 3 and 0.04 on the
    // same fixture, and WebGL compiles the *same GLSL*.
    //
    // It was 9 and 0.56 until the sampler was fixed to address texel centres
    // rather than scaling by `size - 1`. That was not a texture bug: the
    // composite resamples the whole frame, so half a texel of offset softened
    // every pixel of every picture this backend drew, textured or not.
    //
    // Twice now this limit has been left where a measurement could no longer
    // reach it, and both times tightening it was the finding. A threshold far
    // above the observed value has stopped watching — the lesson of two
    // goldens that sat at 0.178% under a 0.2% limit here for a fortnight.
    expect(worst, lessThan(5),
        reason: 'cell ${worstAt ~/ kParityGrid},${worstAt % kParityGrid} '
            'differs by $worst: cpu ${worstAt < 0 ? '-' : mine[worstAt]}, '
            'Impeller ${worstAt < 0 ? '-' : kImpellerPlain[worstAt]}');
    expect(total / mine.length, lessThan(0.3),
        reason: 'the two disagree across the whole frame, not at one edge');

    // Kept alongside the numbers, because they fail differently. A mirrored
    // frame moves the picture and the mean goes up; these say *which way* it
    // moved, and that is the bug that got past three pixel assertions in this
    // project and needed a person to notice.
    bool bright(List<int> g, int row, int col) =>
        g[row * kParityGrid + col] > 40;

    // The small sphere, up and to the right. The asymmetry the fixture exists
    // for: a mirrored frame puts it down and to the left and every average
    // stays the same.
    expect(bright(mine, 2, 12), isTrue,
        reason: 'the small sphere is not up and to the right — a mirrored '
            'frame, or a depth convention that culled it');
    expect(bright(mine, 13, 3), isFalse,
        reason: 'something is lit where the mirror of the small sphere would '
            'be');

    // The large sphere's lit face, and its unlit edge.
    expect(bright(mine, 8, 7), isTrue, reason: 'the large sphere is not lit');
    expect(bright(mine, 8, 1), isFalse,
        reason: 'the background beside the sphere is not background');

    // Lit from above: row 5 of the big sphere is brighter than row 11.
    expect(mine[5 * kParityGrid + 8], greaterThan(mine[11 * kParityGrid + 8]),
        reason: 'the light is coming from below');
  });
}
