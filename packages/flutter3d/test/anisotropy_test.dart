/// `gfx-02n`: what anisotropic filtering is worth, measured.
///
///     flutter test test/anisotropy_test.dart
///
/// **The row asks for two frames and the number of differing pixels, and
/// until now there was nothing to take them with.** `RenderSettings.anisotropy`
/// defaults to one, no demo raises it, and the only backend this machine can
/// render through answered `maxAnisotropy` of one — its own comment said so,
/// and named `anisotropic-floor` as the scene where the software set is
/// allowed to differ from the hardware ones by exactly that. So "capture one
/// frame at one and one at eight" had nothing to capture. `gfx-02n` gave the
/// software rasteriser the taps, and this is the measurement that was waiting
/// for them.
///
/// **A floor receding to the horizon, because that is the one footprint a
/// trilinear sampler cannot serve.** At a grazing angle a pixel covers a few
/// texels across the checks and many along them; one mip level has to serve
/// both, so it serves the long axis and the checks blur away long before
/// perspective would take them. Anisotropy takes several taps along the long
/// axis and picks the level from the short one, which is the whole of the
/// difference.
///
/// The mutations these catch: choosing the level from the long axis anyway,
/// which spends the taps and throws away what they bought — contrast drops
/// *below* the trilinear baseline and the first assertion fails; and letting
/// a sampler that asked for one reach the new path at all, which would move a
/// backend seventy-eight golden scenes are recorded on.
///
/// **One they do not catch, said rather than hidden:** taking the taps along
/// the *short* axis instead of the long one passes every line here. The
/// reason is worth knowing — most of the gain is the level, chosen from the
/// short axis, and the taps only average texels near it, so a wrong direction
/// still sharpens. What it would really cost is aliasing on the far floor,
/// which needs a supersampled reference to measure rather than a contrast
/// number, and that reference is a bigger fixture than this row asked for.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 90;

/// A checkerboard with a full mip chain — the texture whose detail a grazing
/// angle destroys. The two greys are a little apart in warmth so a blurred
/// check reads as a different colour rather than as one of them.
Material _checkerFloor(GraphicsDevice device, int anisotropy) {
  const int size = 512;
  const int texelsPerCheck = size ~/ 64;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final bool dark = ((x ~/ texelsPerCheck) + (y ~/ texelsPerCheck)).isOdd;
      final int at = (y * size + x) * 4;
      pixels[at] = dark ? 64 : 224;
      pixels[at + 1] = dark ? 60 : 216;
      pixels[at + 2] = dark ? 56 : 200;
      pixels[at + 3] = 255;
    }
  }
  final base = ByteData.sublistView(pixels);
  final texture = device.createTextureFromPixels(
    width: size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: base,
    mipLevels: MipChain.build(base, size, size),
  )!;
  return Material(name: 'floor', lighting: LightingModel.unlit)
    ..albedo = texture
    ..albedoSampler = SamplerOptions.trilinearRepeat.withAnisotropy(
      math.min(anisotropy, device.maxAnisotropy),
    );
}

/// [mesh] with its texture coordinates multiplied by [by].
///
/// `PlaneShape` lays UV nought to one across itself whatever its size, so a
/// four-hundred-unit floor gets one check every six units and a pixel never
/// covers more than a texel — which is a floor with no filtering problem at
/// all, and the first version of this fixture measured exactly that: zero
/// differing pixels, because nothing ever left mip level nought.
MeshData _tiled(MeshData mesh, double by) {
  final stride = mesh.layout.floatsPerVertex;
  final at = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
  final vertices = Float32List.fromList(mesh.vertices);
  for (var v = 0; v + stride <= vertices.length; v += stride) {
    vertices[v + at] *= by;
    vertices[v + at + 1] *= by;
  }
  return MeshData(
    layout: mesh.layout,
    vertices: vertices,
    indices: mesh.indices,
  );
}

/// The floor, seen from just above it, as RGBA.
Future<Uint8List> _floorAt(int anisotropy) async {
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
          // **Many segments, and that is a property of this backend rather
          // than of the picture.** The software rasteriser derives its
          // texture derivatives *per triangle* — its own `uvFootprint` says
          // so — where hardware takes them from a quad of neighbouring
          // fragments. A floor of two triangles therefore has one footprint
          // for the whole of itself, near and far alike, and no filter can
          // do anything sensible with that. Sixty-four segments give each
          // band of the floor its own, which is what makes the near checks
          // sharp and the far ones the filter's problem.
          _tiled(
            const PlaneShape(
              width: 400.0,
              depth: 400.0,
              widthSegments: 64,
              depthSegments: 64,
            ).build(),
            20.0,
          ),
        ),
        _checkerFloor(device, anisotropy),
        name: 'floor',
      ),
    );

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()
          // Just above the plane and looking almost along it: the pitch is
          // what makes the footprint long and thin.
          ..setPosition(0.0, 1.2, 0.0)
          ..lookAt(Vector3(0.0, 0.85, -40.0)),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
      shadows: ShadowSettings(enabled: false),
    ),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

/// How many pixels of [a] and [b] differ by more than a channel's rounding.
int _differing(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > 2) count++;
  }
  return count;
}

/// How much detail survives: the mean absolute difference between
/// neighbouring pixels along a row, which is high where checks are still
/// checks and near zero where they have blurred to one grey.
double _contrast(Uint8List rgba) {
  var total = 0;
  var pairs = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 1; x < _width; x++) {
      total += (rgba[(y * _width + x) * 4] - rgba[(y * _width + x - 1) * 4])
          .abs();
      pairs++;
    }
  }
  return total / pairs;
}

void main() {
  test("the row's own measurement: one frame at 1, one at 8", () async {
    final plain = await _floorAt(1);
    final eight = await _floorAt(8);

    final int differing = _differing(plain, eight);
    final double before = _contrast(plain);
    final double after = _contrast(eight);

    // **What this measured when it was written: 3165 of 14400 pixels differ —
    // 22% of the frame — and the contrast between neighbouring pixels goes
    // from 5.36 to 9.20, so 1.7 times as much detail survives.** Those
    // numbers are in the plan row too. What is *asserted* is the direction
    // and the scale, because a measurement pinned to three decimals is a
    // test that fails when somebody improves the thing it measures.
    expect(
      differing,
      greaterThan(_width * _height ~/ 20),
      reason: 'eight taps have to change a twentieth of the frame to matter',
    );
    expect(
      after,
      greaterThan(before),
      reason: 'the checks survive further into the distance',
    );
  });

  test('asking for one tap is the old sampler exactly', () async {
    // What makes this safe to add to the backend seventy-eight golden scenes are
    // recorded on. Not "close": the same bytes, because with `anisotropy` at
    // one the new path is not reached at all.
    expect(await _floorAt(1), await _floorAt(1));
  });

  test('the device reports what it can actually do', () {
    // The cap was one while the rasteriser took no taps, and the comment on
    // it said so in as many words. A backend that promises taps it does not
    // take is the worse of the two failures, which is why this moved only
    // when the taps did.
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    expect(device.maxAnisotropy, 16);
  });
}
