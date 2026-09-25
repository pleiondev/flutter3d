/// The layered metal-rough model — `M1`: an index of refraction, a specular
/// strength and tint, and a clear coat, drawn by `PbrLayered`.
///
///     dart test test/material_layers_test.dart
library;

import 'dart:io';
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
  Material Function(CpuDevice device) material, {
  bool environment = false,
  Set<String> disabledPasses = const <String>{},
}) {
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
  if (environment) {
    // Dark grey all round but for the face behind the sphere, -Z, which is
    // green on one half and blue on the other: what the glass lets through
    // is told apart by its colour, and where a ray bent to by its hue.
    const cube = 8;
    final faces = <ByteData>[
      for (var face = 0; face < 6; face++)
        ByteData.sublistView(
          Uint8List.fromList(<int>[
            for (var i = 0; i < cube * cube; i++)
              ...(face != 5
                  ? <int>[30, 30, 30, 255]
                  : (i % cube < cube ~/ 2
                        ? <int>[0, 230, 0, 255]
                        : <int>[0, 0, 230, 255])),
          ]),
        ),
    ];
    const levels = 4;
    scene
      ..environment = device.createCubeTextureFromPixels(
        size: cube,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: faces,
        mipLevels: EnvironmentMap.prefilter(faces, size: cube, levels: levels),
      )
      ..environmentLevels = levels
      ..ambientIntensity = 1.0;
  }
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      disabledPasses: disabledPasses,
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

  test(
    'an index of nought reflects fully: a black dielectric is a white metal',
    () {
      // `KHR_materials_ior`'s special case: nought is an infinite index, whose
      // Fresnel is one at every angle. A black dielectric has no diffuse, so
      // what is left is a reflection of one head-on and at grazing — exactly a
      // white metal's, under the light and the environment both.
      Material sphere(double metallic, Vector4 colour, double ior) => Material(
        lighting: LightingModel.pbrLayered,
        baseColor: colour,
        metallic: metallic,
        roughness: 0.4,
        extensions: MaterialExtensions(ior: ior),
      );
      final infinite = _render(
        (_) => sphere(0.0, Vector4(0.0, 0.0, 0.0, 1.0), 0.0),
        environment: true,
      ).hdr;
      final metal = _render(
        (_) => sphere(1.0, Vector4(1.0, 1.0, 1.0, 1.0), 1.5),
        environment: true,
      ).hdr;
      // Mutation: reading nought as the clamp to one (`r` from `max(ior, 1)`
      // alone) leaves a head-on reflection of nothing and only a grazing rim,
      // which misses the metal by most of its brightness.
      expect(_largestDifference(infinite, metal), lessThan(1e-4));
      expect(_peak(infinite), greaterThan(0.1));
    },
  );

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
          pixels: ByteData.sublistView(Uint8List.fromList(<int>[0, 0, 0, 255])),
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

  group('transmission', () {
    /// A white glass sphere in the green-backed environment.
    ///
    /// Read through the environment, as a draw outside the transparent pass
    /// reads it: with that pass on, the sphere splits the frame and the glass
    /// reads the copy of the scene, whose backdrop here is the clear colour
    /// rather than the cube — `M3`, held in `transmission_glass_test.dart`.
    Float32List glass(MaterialExtensions? layers) => _render(
      (_) => Material(
        lighting: LightingModel.pbrLayered,
        baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
        roughness: 0.05,
        extensions: layers,
      ),
      environment: true,
      disabledPasses: const <String>{'transparent'},
    ).hdr;

    /// The centre pixel's colour.
    Vector3 centre(Float32List hdr) {
      final i = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
      return Vector3(hdr[i], hdr[i + 1], hdr[i + 2]);
    }

    test('transmission-glass: the environment behind shows through', () {
      final white = centre(glass(null));
      final clear = centre(glass(MaterialExtensions(transmission: 1.0)));
      // White scatters the room's light back, all colours alike; clear
      // glass shows what is behind it, which has no red in it.
      //
      // Mutation: drop the `ambient +=` of the transmitted light from the
      // mirror. The centre is the diffuse white's grey again.
      expect(white.y, lessThan(white.x * 1.5));
      expect(clear.y + clear.z, greaterThan(clear.x * 3.0));
    });

    test('a volume takes away the colours its attenuation says', () {
      final clear = centre(
        glass(MaterialExtensions(transmission: 1.0, thickness: 1.0)),
      );
      final tinted = centre(
        glass(
          MaterialExtensions(
            transmission: 1.0,
            thickness: 1.0,
            attenuationDistance: 0.5,
            attenuationColor: Vector3(1.0, 0.2, 0.2),
          ),
        ),
      );
      // Two attenuation distances of green at 0.2 leave four per cent of it.
      // Mutation: leave `transmittance` at one. The two match.
      expect(tinted.y, lessThan(clear.y * 0.5));
    });

    test('dispersion parts the colours of a refracting sphere', () {
      final plain = glass(
        MaterialExtensions(transmission: 1.0, thickness: 1.0),
      );
      final spread = glass(
        MaterialExtensions(transmission: 1.0, thickness: 1.0, dispersion: 20.0),
      );
      // Mutation: use one ray for all three channels in `transmitted`.
      expect(_largestDifference(plain, spread), greaterThan(0.01));
    });

    test('a thick sphere bends what is behind it, a thin one does not', () {
      final thin = glass(MaterialExtensions(transmission: 1.0, ior: 1.8));
      final thick = glass(
        MaterialExtensions(transmission: 1.0, ior: 1.8, thickness: 1.0),
      );
      expect(_largestDifference(thin, thick), greaterThan(0.01));
    });
  });

  test('iridescence colours the reflection, and at nought changes nothing', () {
    final plain = _hdr((_) => _paint(roughness: 0.3));
    final film = _hdr(
      (_) =>
          _paint(roughness: 0.3, layers: MaterialExtensions(iridescence: 1.0)),
    );
    final none = _hdr(
      (_) => _paint(
        roughness: 0.3,
        layers: MaterialExtensions(iridescenceThicknessMaximum: 250.0),
      ),
    );
    // Mutation: drop `withFilm` from the mirror's `shade`. The film is the
    // plain picture.
    expect(_largestDifference(plain, film), greaterThan(0.01));
    expect(_largestDifference(plain, none), 0.0);
  });

  test('the multiscatter term reads the film, as the specular does', () {
    // The mirror builds one single-scatter albedo, film included, and feeds
    // both the environment's specular and Fdez-Agüera's multiple term from
    // it. `pbr.glsl` has to build it once too: a second, film-free `single`
    // inside the compensation block tints the multiscatter share of a rough
    // iridescent surface differently on the GPU than here.
    //
    // Mutation: give the compensation block back its own
    // `vec3 single = f0 * ab.x + f90 * ab.y;`. There are three, one plain.
    final glsl = File(
      '${Directory.current.parent.path}/flutter3d_shaders/shaders/lib/pbr.glsl',
    ).readAsStringSync();
    final singles = RegExp(
      r'vec3 single = ([^;]*\bab\.x[^;]*);',
    ).allMatches(glsl).map((m) => m.group(1)!).toList();
    expect(singles, hasLength(2));
    expect(singles.where((s) => s.contains('g_irid_fresnel')), hasLength(1));
  });
}
