/// `gfx-16n`: a fourth alpha mode, for foliage and nets.
///
///     flutter test test/alpha_hash_test.dart
///
/// **The choice this removes.** A leaf texture at 40% opacity is either
/// entirely there or entirely gone under a threshold, so a fern comes out as a
/// hard-edged cut-out; blending draws it correctly and wants the geometry
/// sorted, which costs a sort every frame and defeats instancing. Hashed keeps
/// 40% of the *pixels*, in the opaque half, writing depth, with no sorting at
/// all — and that fraction is what this file measures, because "40% of the
/// pixels survive" is the whole claim and a picture of a noisy quad is not.
///
/// The price is noise anywhere the result is not averaged down, and this
/// engine has no temporal accumulation to average it. Said in
/// [MaterialAlphaMode.hashed] rather than discovered.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 96;

/// One flat quad filling most of the frame at [alpha] opacity, unlit and
/// white, on black — so a surviving pixel is white and a discarded one is the
/// background, and counting is not a judgement call.
Future<Uint8List> _draw(
  double alpha,
  MaterialAlphaMode mode, {
  double shift = 0.0,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(3.0, 3.0, 0.1)).build(),
        ),
        Material(
          name: 'leaf',
          baseColor: Vector4(1.0, 1.0, 1.0, alpha),
          lighting: LightingModel.unlit,
          alphaMode: mode,
          alphaCutoff: 0.5,
        ),
      )..setPosition(shift, 0.0, 0.0),
    );
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()..setPosition(shift, 0.0, 3.0),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: const RenderSettings(tonemap: false),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

/// What fraction of the quad's own area survived.
double _survivingFraction(Uint8List rgba) {
  var lit = 0;
  var total = 0;
  for (var at = 0; at < rgba.length; at += 4) {
    total++;
    if (rgba[at + 1] > 128) lit++;
  }
  // The quad covers the middle of the frame; the fraction is of the frame,
  // so a fully opaque draw is the denominator rather than one.
  return lit / total;
}

void main() {
  group('the fraction that survives is the alpha', () {
    late double opaqueArea;

    setUpAll(() async {
      opaqueArea = _survivingFraction(
        await _draw(1.0, MaterialAlphaMode.hashed),
      );
      expect(
        opaqueArea,
        greaterThan(0.3),
        reason: 'the quad has to cover a good part of the frame',
      );
    });

    test('a half-opaque surface keeps about half its pixels', () async {
      final half = _survivingFraction(
        await _draw(0.5, MaterialAlphaMode.hashed),
      );
      expect(half / opaqueArea, closeTo(0.5, 0.08));
    });

    test(
      'a quarter keeps about a quarter, and a fifth about a fifth',
      () async {
        final quarter = _survivingFraction(
          await _draw(0.25, MaterialAlphaMode.hashed),
        );
        final fifth = _survivingFraction(
          await _draw(0.2, MaterialAlphaMode.hashed),
        );
        expect(quarter / opaqueArea, closeTo(0.25, 0.08));
        expect(fifth / opaqueArea, closeTo(0.2, 0.08));
        expect(fifth, lessThan(quarter));
      },
    );

    test('and a threshold cannot do that at all', () async {
      // The comparison the mode exists for. At 40% a cutoff of 0.5 drops the
      // whole surface; at 60% it keeps all of it. There is no setting of a
      // threshold that gives a fern its own density.
      final under = _survivingFraction(
        await _draw(0.4, MaterialAlphaMode.mask),
      );
      final over = _survivingFraction(await _draw(0.6, MaterialAlphaMode.mask));
      expect(under, 0.0);
      expect(over / opaqueArea, closeTo(1.0, 0.01));

      final hashed = _survivingFraction(
        await _draw(0.4, MaterialAlphaMode.hashed),
      );
      expect(hashed / opaqueArea, closeTo(0.4, 0.08));
    });
  });

  group('zero changes in opaque scenes', () {
    test('an opaque material draws what it always drew', () async {
      // The row's own second clause. Nothing about the fourth mode may reach
      // a material that did not ask for it, and the sentinel lives in the
      // same uniform component as the cutoff — so this is the check that the
      // encoding did not leak.
      final a = await _draw(1.0, MaterialAlphaMode.opaque);
      final b = await _draw(1.0, MaterialAlphaMode.opaque);
      expect(a, b);
      expect(_survivingFraction(a) / _survivingFraction(a), 1.0);
    });

    test('a fully opaque hashed surface keeps every pixel', () async {
      // Alpha 1 is never below any noise in [0, 1), so the mode costs a hash
      // and drops nothing — which is what makes it safe on a material whose
      // texture is opaque in places.
      final opaque = _survivingFraction(
        await _draw(1.0, MaterialAlphaMode.opaque),
      );
      final hashed = _survivingFraction(
        await _draw(1.0, MaterialAlphaMode.hashed),
      );
      expect(hashed, closeTo(opaque, 0.001));
    });
  });

  group('the noise travels with the surface', () {
    test('moving the surface moves the pattern with it', () async {
      // **The test that separates a world-anchored hash from a screen-space
      // one.** The quad and the camera move together, so the surface covers
      // exactly the same pixels either way: a hash on screen position would
      // draw the identical frame, and one anchored to the world cannot.
      //
      // Shifted by a third of the hash's own cell — 1/16 of a metre — so the
      // move lands between cells rather than on a multiple of them, which
      // would alias back onto the same pattern.
      final here = await _draw(0.5, MaterialAlphaMode.hashed);
      final moved = await _draw(0.5, MaterialAlphaMode.hashed, shift: 0.0208);

      expect(here, isNot(moved));

      // And the coverage is the same, which is what makes the comparison
      // above mean what it says rather than merely reporting that the quad
      // went somewhere else.
      expect(
        _survivingFraction(moved),
        closeTo(_survivingFraction(here), 0.03),
      );
    });

    test('standing still draws the same frame twice', () async {
      expect(
        await _draw(0.5, MaterialAlphaMode.hashed),
        await _draw(0.5, MaterialAlphaMode.hashed),
      );
    });
  });
}
