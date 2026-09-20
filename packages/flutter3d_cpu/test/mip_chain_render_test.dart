/// `ap-08` in `doc/asset-pipeline-plan.md`, the half of its acceptance
/// `mip_chain_test.dart` in `flutter3d_formats` cannot reach on its own: "a
/// reference frame on the CPU backend with a model far away differs from a
/// frame without mips by less than a noise threshold". `mip_chain_test.dart`
/// already pins the arithmetic in isolation; this pins the *effect*, on a
/// real render through `uploadEncodedImage` and the software rasteriser.
///
/// **The comparison is not "a chain" against "no chain" — a single-level
/// RGBA8 upload gets one anyway.** `_uploadRgba8` in `texture_upload.dart`
/// builds one on the spot with `MipChain.build` whenever the sampler asks
/// for mipmapping, which every material texture's default sampler does; a
/// first version of this test compared `writeKtx2WithMips`'s own chain
/// against a single-level file expecting "no chain" and found the two
/// render identically, because both had one by the time a pixel was drawn.
/// The comparison this test draws instead is the one that is actually new:
/// `writeKtx2WithMips`'s gamma-correct chain against `MipChain.build`'s own,
/// which its doc comment already names as filtering sRGB bytes as though
/// they were linear — "the darkening compounds down the chain until a
/// distant surface is visibly murkier than a near one". A checkerboard far
/// enough away to reach a deep mip level should read distinctly *brighter*
/// through the gamma-correct chain than through the one already in the
/// engine, and that is what is asserted — the same textbook case
/// `mip_chain_test.dart` already proves on the chain alone, now proven on a
/// frame nothing in this repository has rendered before.
///
///     flutter test test/mip_chain_render_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// A single-texel checkerboard — the highest spatial frequency a texture can
/// carry, and the pattern that aliases hardest under minification: a naive
/// point sample lands on a fully black or fully white texel with no middle
/// ground, where a filtered sample of the same footprint averages towards
/// grey. `size` is 64, so the chain built over it has seven levels below the
/// base (64 → 32 → … → 1), plenty of room for the CPU rasteriser's own
/// derivative-based level selection to land well above zero at the distance
/// below.
Rgba8Image _fineCheckerboard() {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = (x + y).isEven ? 0 : 255;
      final at = (y * size + x) * 4;
      pixels[at] = on;
      pixels[at + 1] = on;
      pixels[at + 2] = on;
      pixels[at + 3] = 255;
    }
  }
  return Rgba8Image(width: size, height: size, pixels: pixels);
}

/// Renders [checkerboard] (as the KTX2 bytes [encode] produces from it) on a
/// small, distant, camera-facing plane and returns the rendered patch of
/// pixels the plane actually covers.
Future<Uint8List> _renderPatch(
  Rgba8Image checkerboard,
  Uint8List Function(Rgba8Image) encode,
) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final handle = await uploadEncodedImage(
    device,
    encode(checkerboard),
    sampling: const TextureSampling(),
  );
  // Not a hardware limit reached honestly, as `wg-00`/`net-00` name theirs —
  // a genuine test-authoring failure if it ever fires, since every format
  // and size above is this package's own and chosen to be unobjectionable.
  if (handle == null) {
    fail('the device left the texture out — see report, none was wired up.');
  }

  // Camera-facing, far enough that a 64px-square texture covers only a
  // handful of screen pixels: at z = -60 with fovY = 1.0 rad the frustum is
  // about 65 units tall, so a plane 6 units square covers roughly
  // 6 / 65 * 48 ≈ 4.4 pixels — comfortably inside the mip chain's own seven
  // levels below the base, and far past the one level (`footprint <= 1.0`)
  // `BoundTexture.sample` needs before it looks at a second one at all.
  final plane =
      MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 6.0, depth: 6.0).build(),
          ),
          Material(
            name: 'checker',
            lighting: LightingModel.unlit,
            albedo: handle,
            albedoSampler: SamplerOptions.trilinearRepeat,
          ),
          name: 'checker',
        )
        ..setPosition(0.0, 0.0, -60.0)
        ..setRotation(Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2));

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 200.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  final scene = Scene()
    ..add(plane)
    ..add(camera);

  final renderer = Renderer.create(device: device);
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
  );
  final frame = (await device.readPixels(result.frame))!.buffer.asUint8List();

  // The plane's own screen footprint: roughly a 5x5 block centred on the
  // frame, generous enough either way not to catch the empty sky around it
  // — this test's claim is about the pattern inside the patch, not its exact
  // edge.
  const patchRadius = 3;
  final cx = _width ~/ 2;
  final cy = _height ~/ 2;
  final patch = Uint8List((patchRadius * 2) * (patchRadius * 2) * 4);
  var i = 0;
  for (var y = cy - patchRadius; y < cy + patchRadius; y++) {
    for (var x = cx - patchRadius; x < cx + patchRadius; x++) {
      final at = (y * _width + x) * 4;
      patch[i * 4] = frame[at];
      patch[i * 4 + 1] = frame[at + 1];
      patch[i * 4 + 2] = frame[at + 2];
      patch[i * 4 + 3] = frame[at + 3];
      i++;
    }
  }
  return patch;
}

/// The mean of a patch's red channel — every channel of this texture is the
/// same grey once decoded, so one is enough.
double _meanRed(Uint8List patch) {
  final reds = <double>[for (var i = 0; i < patch.length; i += 4) patch[i].toDouble()];
  return reds.reduce((a, b) => a + b) / reds.length;
}

void main() {
  test(
    'a gamma-correct chain reads brighter at distance than the engine\'s '
    'own linear-space one, on the same bytes',
    () async {
      final checkerboard = _fineCheckerboard();

      final gammaCorrect = await _renderPatch(
        checkerboard,
        // `srgb: true` is the whole of what this compares: the same bytes,
        // filtered knowing they are gamma-encoded.
        (image) => writeKtx2WithMips(image, srgb: true),
      );
      final enginesOwnChain = await _renderPatch(
        checkerboard,
        // A single level, tagged as *linear* UNorm rather than sRGB, which is
        // what makes `_uploadKtx2` take the `_uploadRgba8` branch and build a
        // chain itself with `MipChain.build` — the plain box filter this
        // package's own doc comment says darkens sRGB data. The shader reads
        // every `base_color_texture` as sRGB regardless of the file's own
        // tag (`readSurface`'s `toLinear` calls are unconditional), so both
        // renders decode their sampled texel the same way; only the bytes
        // arriving at that decode differ.
        (image) => writeKtx2(
          vkFormat: VkFormat.r8g8b8a8UNorm,
          pixelWidth: image.width,
          pixelHeight: image.height,
          levels: [image.pixels],
        ),
      );

      final gammaCorrectMean = _meanRed(gammaCorrect);
      final enginesOwnMean = _meanRed(enginesOwnChain);

      // Not a threshold picked to make this pass: `mip_chain_test.dart`
      // already pins the byte this checkerboard's small levels converge to
      // gamma-correctly (above 160, on the way to the ~188 a linear-light
      // average of black and white decodes to) against the naive answer
      // (128). Decoded through the same sRGB curve the shader applies to
      // both, that gap widens rather than shrinks — comfortable room for
      // "visibly brighter" without pinning an exact byte a filter's rounding
      // could nudge.
      expect(
        gammaCorrectMean,
        greaterThan(enginesOwnMean + 15),
        reason:
            'gamma-correct chain read $gammaCorrectMean, '
            'engine\'s own linear-space chain read $enginesOwnMean — the '
            'gamma-correct one should render distinctly brighter, not the '
            'same or darker',
      );
    },
  );
}
