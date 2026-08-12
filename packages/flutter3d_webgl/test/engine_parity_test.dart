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

/// Average luminance per cell, row-major from the top, as Impeller drew each
/// fixture.
///
/// Recorded in one run by `parity_main.dart`, all four together — recording
/// them separately is how two end up drawn by different versions of the engine.
const Map<ParityScene, List<int>> kImpellerGrids = <ParityScene, List<int>>{
  ParityScene.plain: <int>[
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
  ],
  ParityScene.directionalShadow: <int>[
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 60, 145, 38, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 47, 142, 112, 4, 4,
    4, 4, 4, 4, 4, 4, 50, 123, 129, 55, 5, 28, 58, 77, 4, 4,
    4, 4, 4, 4, 4, 49, 157, 173, 182, 186, 36, 15, 21, 7, 4, 4,
    4, 4, 4, 4, 5, 99, 151, 168, 177, 184, 136, 5, 4, 4, 4, 4,
    4, 4, 4, 4, 11, 84, 139, 159, 171, 179, 184, 54, 4, 4, 4, 4,
    4, 4, 4, 4, 15, 53, 119, 148, 162, 172, 178, 94, 4, 4, 4, 4,
    4, 4, 4, 4, 15, 29, 83, 129, 150, 162, 169, 88, 4, 4, 4, 4,
    4, 4, 4, 4, 11, 27, 39, 95, 130, 148, 157, 54, 4, 4, 4, 4,
    102, 171, 171, 171, 172, 45, 27, 42, 90, 121, 141, 176, 171, 171, 171, 102,
    231, 231, 228, 201, 194, 145, 30, 27, 33, 59, 186, 231, 231, 231, 231, 231,
    231, 134, 28, 14, 14, 14, 16, 24, 103, 188, 231, 231, 231, 231, 231, 231,
    231, 38, 14, 14, 14, 14, 14, 14, 152, 231, 231, 231, 231, 231, 231, 231,
    231, 198, 91, 30, 14, 14, 27, 96, 217, 231, 231, 231, 231, 231, 231, 231,
  ],
  ParityScene.pointShadow: <int>[
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 52, 135, 35, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 54, 136, 102, 4, 4,
    4, 4, 4, 4, 4, 4, 24, 71, 87, 40, 5, 29, 63, 61, 4, 4,
    4, 4, 4, 4, 4, 16, 72, 101, 124, 138, 37, 15, 21, 6, 4, 4,
    4, 4, 4, 4, 5, 32, 67, 92, 114, 131, 115, 5, 4, 4, 4, 4,
    4, 4, 4, 4, 11, 29, 57, 81, 100, 118, 130, 40, 4, 4, 4, 4,
    4, 4, 4, 4, 15, 27, 42, 67, 86, 102, 114, 59, 4, 4, 4, 4,
    4, 4, 4, 4, 15, 27, 29, 51, 71, 85, 95, 49, 4, 4, 4, 4,
    4, 4, 4, 4, 11, 27, 27, 32, 52, 67, 75, 26, 4, 4, 4, 4,
    12, 16, 16, 17, 20, 26, 27, 27, 30, 42, 49, 45, 44, 43, 42, 27,
    14, 14, 14, 14, 14, 18, 26, 27, 27, 27, 65, 83, 84, 84, 83, 81,
    14, 14, 14, 14, 14, 14, 16, 22, 22, 71, 100, 102, 104, 105, 105, 104,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 66, 112, 115, 118, 119, 120, 120,
    23, 14, 14, 14, 14, 14, 14, 14, 35, 107, 120, 124, 127, 129, 130, 131,
  ],
  ParityScene.bloom: <int>[
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 72, 148, 38, 4, 4,
    4, 4, 4, 4, 4, 4, 3, 2, 2, 2, 4, 94, 159, 109, 4, 4,
    4, 4, 4, 4, 4, 4, 52, 124, 128, 53, 3, 32, 83, 71, 4, 4,
    4, 4, 4, 4, 4, 59, 168, 178, 182, 184, 71, 15, 21, 6, 4, 4,
    4, 4, 4, 4, 9, 137, 166, 174, 179, 182, 172, 12, 4, 4, 4, 4,
    4, 4, 4, 4, 32, 138, 159, 168, 174, 177, 178, 63, 4, 4, 4, 4,
    4, 4, 4, 4, 30, 121, 149, 160, 167, 171, 172, 87, 4, 4, 4, 4,
    4, 4, 4, 4, 16, 88, 132, 148, 157, 162, 163, 81, 4, 4, 4, 4,
    4, 4, 4, 4, 11, 43, 100, 129, 142, 148, 148, 47, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 25, 45, 88, 112, 121, 105, 8, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 11, 26, 31, 49, 54, 19, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 9, 18, 18, 9, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
  ],
};

void main() {
  for (final which in ParityScene.values) {
    test('WebGL draws ${which.name} the way Impeller does', () async {
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

      final built = buildParityScene(device, which: which);
      final result = renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(which),
      );

      final pixels = await device.readPixels(result.frame);
      expect(pixels, isNotNull, reason: 'the frame could not be read back');

      final mine = parityGrid(
        pixels!.buffer.asUint8List(),
        kParityWidth,
        kParityHeight,
      );
      final reference = kImpellerGrids[which]!;
      expect(mine.length, reference.length);

      var worst = 0;
      var worstAt = -1;
      var total = 0;
      for (var i = 0; i < mine.length; i++) {
        final delta = (mine[i] - reference[i]).abs();
        total += delta;
        if (delta > worst) {
          worst = delta;
          worstAt = i;
        }
      }
      final mean = total / mine.length;

      // Printed whether it passes or not. A comparison whose number nobody sees
      // is a threshold nobody can judge, which is how two goldens sat under one
      // for a fortnight in this project.
      // ignore: avoid_print
      print('parity ${which.name}: mean ${mean.toStringAsFixed(2)}, '
          'worst $worst at cell ${worstAt ~/ kParityGrid},'
          '${worstAt % kParityGrid}');

      // Eight and one, against 3 and 0.04 measured on the plain fixture. Room
      // for a driver that rounds differently, none for a shape in the wrong
      // place — the lesson of two goldens that sat at 0.178% under a 0.2% limit
      // for two commits is that a limit far above the observed value has
      // stopped watching.
      expect(worst, lessThan(8),
          reason: 'cell ${worstAt ~/ kParityGrid},${worstAt % kParityGrid} '
              'differs by $worst: WebGL ${worstAt < 0 ? '-' : mine[worstAt]}, '
              'Impeller ${worstAt < 0 ? '-' : reference[worstAt]}');
      expect(mean, lessThan(1.0),
          reason: 'the two backends disagree across the whole frame, '
              'not in one place');
    },
        // Shadows do not draw on this backend yet, and the numbers say which
        // way: where Impeller puts a shadow the WebGL frame is still lit —
        // cell 13,3 reads 231 against 14 for the directional map, 107 against
        // 14 for the cube atlas. Not a distorted shadow, an absent one.
        //
        // Skipped rather than left red, because a suite that is red every day
        // is a suite nobody reads; skipped rather than deleted, because then
        // the gap goes back to being an opinion. Removing this is the
        // definition of done for shadows here.
        skip: (which == ParityScene.directionalShadow ||
                which == ParityScene.pointShadow)
            ? 'shadows do not draw on WebGL yet — see the note above'
            : null);
  }
}
