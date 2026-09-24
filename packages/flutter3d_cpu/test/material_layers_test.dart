/// The layered metal-rough model — `M1`: an index of refraction, a specular
/// strength and tint, and a clear coat, drawn by `PbrLayered`.
///
///     dart test test/material_layers_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const int _size = 48;

/// The HDR frame of a sphere drawn with [material], lit from the camera's
/// side, and the device it was drawn on.
({Float32List hdr, CpuDevice device}) _render(
  Material Function(CpuDevice device) material,
) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 2.0);
  final sphere = MeshNode(
    DeviceMesh.upload(device, const SphereShape().build()),
    material(device),
  );
  final light = LightNode(intensity: 3.0)
    ..setRotationYawPitchRoll(0.3, -0.4, 0.0);
  final scene = Scene()
    ..add(sphere)
    ..add(light)
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
    ),
  );
  return (hdr: device.readHdrPixels(result.frame), device: device);
}

Float32List _hdr(Material Function(CpuDevice device) material) =>
    _render(material).hdr;

/// A dielectric sphere: red, rough enough that its own highlight is broad.
Material _paint({
  LightingModel lighting = LightingModel.pbrLayered,
  MaterialExtensions? layers,
  TextureHandle? coatMap,
  TextureHandle? sheenMap,
  double roughness = 0.6,
}) => Material(
  lighting: lighting,
  baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
  roughness: roughness,
  extensions: layers,
  coatMap: coatMap,
  sheenMap: sheenMap,
);

/// The mean of the blue channel over the outer ring of the sphere, where a
/// sheen lives: pixels whose distance from the centre is 80–100% of its
/// radius on screen.
double _rimBlue(Float32List hdr) {
  var sum = 0.0;
  var count = 0;
  const centre = _size / 2.0;
  // The sphere's radius on screen at this camera distance, a little inside.
  const radius = _size * 0.28;
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final d = math.sqrt(
        (x + 0.5 - centre) * (x + 0.5 - centre) +
            (y + 0.5 - centre) * (y + 0.5 - centre),
      );
      if (d < radius * 0.8 || d > radius) continue;
      sum += hdr[(y * _size + x) * 4 + 2];
      count++;
    }
  }
  return sum / count;
}

/// The brightest red value in [hdr].
double _peak(Float32List hdr) {
  var peak = 0.0;
  for (var i = 0; i < hdr.length; i += 4) {
    peak = math.max(peak, hdr[i]);
  }
  return peak;
}

/// The mean of the green channel, which a red base barely has: what is left
/// is almost all reflection.
double _meanGreen(Float32List hdr) {
  var sum = 0.0;
  for (var i = 1; i < hdr.length; i += 4) {
    sum += hdr[i];
  }
  return sum / (hdr.length / 4);
}

double _largestDifference(Float32List a, Float32List b) {
  var largest = 0.0;
  for (var i = 0; i < a.length; i++) {
    largest = math.max(largest, (a[i] - b[i]).abs());
  }
  return largest;
}

void main() {
  test('with every layer at its default it draws plain metal-rough', () {
    final plain = _hdr((_) => _paint(lighting: LightingModel.pbr));
    final layered = _hdr((_) => _paint(layers: MaterialExtensions()));
    // Not byte for byte: an index of 1.5 gives a reflectance of
    // 0.04000000000000001, a hair off the plain stage's literal.
    expect(_largestDifference(plain, layered), lessThan(1e-5));
  });

  test('clearcoat-car-paint: a sharp coat over a rough base', () {
    final bare = _hdr((_) => _paint());
    final coated = _hdr(
      (_) => _paint(
        layers: MaterialExtensions(clearcoat: 1.0, clearcoatRoughness: 0.15),
      ),
    );
    // Rougher than a real lacquer only so the highlight is wider than a
    // pixel of a 48-pixel frame.
    //
    // Mutation: drop `vec3(g_coat * CoatLobe(light))` from the mirror's
    // `shade`. The coated sphere peaks no higher than the bare one.
    expect(_peak(coated), greaterThan(_peak(bare) * 1.5));
  });

  test('a coat map scales the coat', () {
    final bare = _hdr((_) => _paint());
    final masked = _hdr(
      (device) => _paint(
        layers: MaterialExtensions(clearcoat: 1.0, clearcoatRoughness: 0.05),
        // Red nought: no coat anywhere, whatever the factor says.
        coatMap: device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(Uint8List.fromList(<int>[0, 255, 0, 0])),
        ),
      ),
    );
    // Mutation: bind `fallbackAlbedo` for the coat map in the encoder. The
    // coat comes back at full strength.
    expect(_largestDifference(bare, masked), lessThan(1e-5));
  });

  test('a denser dielectric reflects more head-on', () {
    final glass = _meanGreen(
      _hdr((_) => _paint(layers: MaterialExtensions(ior: 1.5))),
    );
    final diamond = _meanGreen(
      _hdr((_) => _paint(layers: MaterialExtensions(ior: 2.4))),
    );
    // Mutation: take `f0` from 0.04 in the mirror's layered `shade`. The two
    // come out equal.
    expect(diamond, greaterThan(glass * 1.2));
  });

  test('specular strength and tint scale the dielectric reflection', () {
    final full = _meanGreen(
      _hdr((_) => _paint(layers: MaterialExtensions(ior: 1.49))),
    );
    final none = _meanGreen(
      _hdr((_) => _paint(layers: MaterialExtensions(specular: 0.0))),
    );
    final tinted = _meanGreen(
      _hdr(
        (_) => _paint(
          layers: MaterialExtensions(specularColor: Vector3(1.0, 0.0, 1.0)),
        ),
      ),
    );
    // With no reflection the green left is the base's own 0.05 tint alone.
    expect(none, lessThan(full * 0.8));
    // A tint without green takes the green out of the head-on reflection.
    expect(tinted, lessThan(full));
  });

  test('sheen-fabric: the rim of a dark cloth catches light', () {
    final bare = _hdr((_) => _paint());
    final velvet = _hdr(
      (_) => _paint(
        layers: MaterialExtensions(
          sheenColor: Vector3(0.2, 0.4, 1.0),
          sheenRoughness: 0.5,
        ),
      ),
    );
    // Mutation: drop `..add(sheen)` from the mirror's `shade`. The rim is as
    // dark as the bare sphere's, less the albedo scaling.
    expect(_rimBlue(velvet), greaterThan(_rimBlue(bare) * 1.5));
  });

  test('the sheen\'s albedo dims the layer beneath', () {
    // A sheen with no lobe of its own left would only darken: the table's
    // albedo, applied to the base. Held against the base alone through the
    // red channel, which a blue sheen adds nothing to.
    final bare = _hdr((_) => _paint());
    final velvet = _hdr(
      (_) => _paint(
        layers: MaterialExtensions(
          sheenColor: Vector3(0.0, 0.0, 1.0),
          sheenRoughness: 0.5,
        ),
      ),
    );
    var bareRed = 0.0;
    var velvetRed = 0.0;
    for (var i = 0; i < bare.length; i += 4) {
      bareRed += bare[i];
      velvetRed += velvet[i];
    }
    // Mutation: leave `sheenScale` at one in `readOnMaps`. The red matches.
    expect(velvetRed, lessThan(bareRed * 0.99));
    expect(velvetRed, greaterThan(bareRed * 0.5));
  });

  test('a sheen map tints the sheen', () {
    final bare = _hdr((_) => _paint());
    final masked = _hdr(
      (device) => _paint(
        layers: MaterialExtensions(sheenColor: Vector3(1.0, 1.0, 1.0)),
        // Black colour: no sheen, whatever the factor says.
        sheenMap: device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(
            Uint8List.fromList(<int>[0, 0, 0, 255]),
          ),
        ),
      ),
    );
    // Mutation: bind `fallbackAlbedo` for the sheen map. The sheen returns.
    expect(_largestDifference(bare, masked), lessThan(1e-5));
  });

  test('anisotropy-disc: the highlight stretches, and turns with rotation', () {
    Float32List brushed(double rotation) => _hdr(
      (_) => _paint(
        roughness: 0.3,
        layers: MaterialExtensions(
          anisotropyStrength: 0.9,
          anisotropyRotation: rotation,
        ),
      ),
    );
    final along = brushed(0.0);
    final across = brushed(math.pi / 2);
    final isotropic = _hdr((_) => _paint(roughness: 0.3));
    // Mutation: drop the anisotropic branch of the mirror's `shade`. All three
    // are the same picture.
    expect(_largestDifference(along, isotropic), greaterThan(0.05));
    expect(_largestDifference(along, across), greaterThan(0.05));
  });

  test('no anisotropy is the isotropic lobe exactly', () {
    final plain = _hdr((_) => _paint(roughness: 0.3));
    final zero = _hdr(
      (_) => _paint(
        roughness: 0.3,
        layers: MaterialExtensions(anisotropyRotation: 1.0),
      ),
    );
    expect(_largestDifference(plain, zero), 0.0);
  });
}
