/// The same scene, drawn by both backends, compared.
///
///     flutter test --platform chrome test/engine_parity_test.dart
///
/// The reference below was produced by `parity_main.dart` in the engine's
/// example, running on Impeller. The scene is `buildParityScene`, which lives in
/// the engine and is written once — that is what makes a difference here
/// attributable to the backends rather than to two transcriptions of one
/// intent.
///
/// Compared as a grid of average luminance rather than as pixels. Two GPUs, two
/// shader compilers and two rounding regimes disagree in the last bits of
/// nearly every pixel and agree completely about where the spheres are, so
/// pixel identity would mean choosing a tolerance for each pixel instead of one
/// for the question actually being asked: do these backends draw the same
/// picture.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

/// Average luminance per cell, row-major from the top, as Impeller drew it.
const List<int> kImpellerGrid = <int>[
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
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

void main() {
  test('WebGL draws the same picture Impeller does', () async {
    final device = WebGlDevice.create(
      width: kParityWidth,
      height: kParityHeight,
      sources: engineShaders,
    );
    if (device == null) fail('no WebGL2 context in this browser');

    TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
        )!;

    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );

    final built = buildParityScene(device);
    final result = renderer.render(
      width: kParityWidth,
      height: kParityHeight,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: kParitySettings,
    );

    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');

    final mine = parityGrid(
      pixels!.buffer.asUint8List(),
      kParityWidth,
      kParityHeight,
    );
    expect(mine.length, kImpellerGrid.length);

    var worst = 0;
    var worstAt = -1;
    var total = 0;
    for (var i = 0; i < mine.length; i++) {
      final delta = (mine[i] - kImpellerGrid[i]).abs();
      total += delta;
      if (delta > worst) {
        worst = delta;
        worstAt = i;
      }
    }
    final mean = total / mine.length;

    // Reported whether it passes or not: a comparison whose number nobody sees
    // is a threshold nobody can judge, which is how two goldens sat under one
    // for a fortnight in this project.
    // ignore: avoid_print
    print('parity: mean ${mean.toStringAsFixed(2)}, worst $worst '
        'at cell ${worstAt ~/ kParityGrid},${worstAt % kParityGrid}');

    // Eight and one, against measured values of 3 and 0.04. Room for a driver
    // that rounds differently, and nothing like room for a shape in the wrong
    // place — the whole lesson of the two goldens that sat at 0.178% under a
    // 0.2% threshold for two commits is that a limit far above the observed
    // value is a limit that has stopped watching.
    expect(worst, lessThan(8),
        reason: 'cell ${worstAt ~/ kParityGrid},${worstAt % kParityGrid} '
            'differs by $worst: WebGL says ${worstAt < 0 ? '-' : mine[worstAt]}, '
            'Impeller said ${worstAt < 0 ? '-' : kImpellerGrid[worstAt]}');
    expect(mean, lessThan(1.0),
        reason: 'the two backends disagree across the whole frame, '
            'not in one place');
  });
}
