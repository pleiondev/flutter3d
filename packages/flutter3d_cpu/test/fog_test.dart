/// Distance fades a surface toward the fog, and no fog leaves it alone.
///
/// **Why this file exists.** Fog was written into the three particle shaders and
/// into none of the five that draw surfaces. `ApplyFog` lives in `color.glsl`
/// inside `WriteSurface`, which `lambert`, `pbr`, `blinn_phong`, `toon` and
/// `unlit` all call — but the transcription here had split that one function
/// into "write the geometry" and "return the colour", and the fog went with
/// neither. So this rasteriser drew every road, wall and car at full contrast to
/// the horizon while cheerfully accepting a `FogSettings`, and a test that
/// passed one was measuring a renderer with no weather.
///
/// Nothing caught it because nothing asked. The golden sets are recorded with
/// the default `FogSettings()`, whose density is zero — the one case where the
/// bug and the fix agree exactly.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 64;

/// A white wall filling the view, [away] metres from the camera.
///
/// White and unlit on purpose: the surface's own colour is then the brightest
/// thing the frame can hold, so anything darker in the result came from the fog
/// and not from a light nobody placed.
({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _wall({
  required double away,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
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

  final scene = Scene();
  // Wide enough to fill the frame at any distance used here, so the two
  // distances differ in fog and in nothing else.
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(away * 4, away * 4, 0.5)).build(),
      ),
      engine.Material(
        name: 'wall',
        baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
        lighting: LightingModel.unlit,
      ),
      name: 'wall',
    )..setPosition(0.0, 0.0, away),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.3,
      far: 2000.0,
    ),
  )..lookAt(Vector3(0.0, 0.0, 1.0));
  scene.add(camera);

  return (device: device, renderer: renderer, scene: scene, camera: camera);
}

/// The mean of one channel over the frame, from 0 to 255.
Future<double> _mean(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it, {
  required FogSettings fog,
  int channel = 0,
}) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    // Tone mapping off: it is a curve between the fog and the pixel, and this
    // test is about the fog.
    settings: RenderSettings(fog: fog, tonemap: false, bloom: BloomSettings(enabled: false)),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  final bytes = pixels!.buffer.asUint8List();

  var total = 0;
  var count = 0;
  for (var i = channel; i < bytes.length; i += 4) {
    total += bytes[i];
    count++;
  }
  return total / count;
}

void main() {
  test('a far surface fades toward the fog and a near one does not', () async {
    // Mutation: leave `_writeLit` returning the colour unfogged, which is what
    // it did. Both distances come back the same white and this fails on the
    // first expectation — which is the whole of what was wrong.
    final fog = FogSettings(color: Vector3(0.0, 0.0, 0.0), density: 0.02);

    final near = await _mean(_wall(away: 5.0), fog: fog);
    final far = await _mean(_wall(away: 200.0), fog: fog);

    expect(near, greaterThan(200.0), reason: 'five metres of black fog is nothing');
    expect(far, lessThan(near * 0.25), reason: 'two hundred metres of it is most of the wall');
  });

  test('the fog takes its own colour, not a darkening', () async {
    // Mutation: multiply by the transmittance instead of mixing toward the fog
    // colour. Distance would then always darken, and a car disappearing into a
    // pale morning would go black rather than white.
    final white = FogSettings(color: Vector3(1.0, 1.0, 1.0), density: 0.02);
    final black = FogSettings(color: Vector3(0.0, 0.0, 0.0), density: 0.02);

    final intoWhite = await _mean(_wall(away: 200.0), fog: white);
    final intoBlack = await _mean(_wall(away: 200.0), fog: black);

    expect(intoWhite, greaterThan(intoBlack + 100.0));
  });

  test('no fog is byte-identical to the fog nobody asked for', () async {
    // The early return at zero density is not an optimisation. The golden sets
    // — thirty scenes, zero-pixel threshold, two backends — are all recorded
    // with the default `FogSettings()`, and this is the property that lets them
    // stay recorded.
    final none = FogSettings();
    final explicitlyOff = FogSettings(color: Vector3(1.0, 0.0, 0.0), density: 0.0);

    final a = await _mean(_wall(away: 200.0), fog: none);
    final b = await _mean(_wall(away: 200.0), fog: explicitlyOff);

    expect(a, b);
    expect(a, greaterThan(200.0), reason: 'and it is still the white wall');
  });

  test('density decides how far the view carries', () async {
    final thin = FogSettings(color: Vector3(0.0, 0.0, 0.0), density: 0.002);
    final thick = FogSettings(color: Vector3(0.0, 0.0, 0.0), density: 0.02);

    final inThin = await _mean(_wall(away: 100.0), fog: thin);
    final inThick = await _mean(_wall(away: 100.0), fog: thick);

    expect(inThin, greaterThan(inThick));
  });
}
