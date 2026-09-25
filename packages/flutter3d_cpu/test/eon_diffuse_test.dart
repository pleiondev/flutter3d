/// The energy-preserving Oren–Nayar diffuse — `L8`: a rough dielectric
/// stops reading as plastic, and a white one still keeps every bit of the
/// light.
///
///     dart test test/eon_diffuse_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const int _size = 48;

/// The HDR frame of a sphere of [grey] and [roughness], drawn by [lighting]
/// with no specular, so what is left is the diffuse. Lit by one light from
/// straight behind the camera when [lit], and by a white ambient of one
/// from everywhere alike when not.
Float32List _render({
  required DiffuseModel model,
  LightingModel lighting = LightingModel.pbr,
  double roughness = 1.0,
  double grey = 0.8,
  bool lit = true,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 2.0);
  final sphere = MeshNode(
    DeviceMesh.upload(device, const SphereShape().build()),
    Material(
      lighting: lighting,
      baseColor: Vector4(grey, grey, grey, 1.0),
      roughness: roughness,
    ),
  );
  final scene = Scene()
    ..add(sphere)
    ..add(camera)
    ..ambientIntensity = lit ? 0.0 : 1.0;
  if (lit) scene.add(LightNode(intensity: 3.0));
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      specular: 0.0,
      diffuseModel: model,
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// The mean red over the pixels of the sphere between [from] and [to] of
/// its radius on screen.
double _ring(Float32List hdr, double from, double to) {
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
      if (d < radius * from || d > radius * to) continue;
      sum += hdr[(y * _size + x) * 4];
      count++;
    }
  }
  return sum / count;
}

/// How bright the sphere's outer ring is against its middle.
double _flatness(Float32List hdr) => _ring(hdr, 0.75, 1.0) / _ring(hdr, 0, 0.3);

/// The mean red over the whole frame.
double _mean(Float32List hdr) {
  var sum = 0.0;
  for (var i = 0; i < hdr.length; i += 4) {
    sum += hdr[i];
  }
  return sum / (hdr.length / 4);
}

void main() {
  test('Lambert is the default', () {
    expect(const RenderSettings().diffuseModel, DiffuseModel.lambert);
    expect(
      const RenderSettings()
          .copyWith(diffuseModel: DiffuseModel.eon)
          .diffuseModel,
      DiffuseModel.eon,
    );
  });

  // The golden scene's name. Lit from the eye, a rough sphere under Lambert
  // darkens towards its rim by the cosine; under Oren–Nayar the facets
  // turned back to the light and the eye at once hold the rim up — the
  // flat look of the full moon, and of clay.
  for (final (name, lighting) in <(String, LightingModel)>[
    ('pbr', LightingModel.pbr),
    ('pbrLayered', LightingModel.pbrLayered),
  ]) {
    test('rough-dielectrics: $name holds its rim up', () {
      final lambert = _flatness(
        _render(model: DiffuseModel.lambert, lighting: lighting),
      );
      final eon = _flatness(
        _render(model: DiffuseModel.eon, lighting: lighting),
      );
      // Mutation: drop the `r * s_over_t` term of the single scattering in
      // the mirror, and the rim falls below even Lambert's.
      expect(eon, greaterThan(lambert * 1.15));
    });
  }

  test('a smooth surface is Lambert', () {
    final lambert = _mean(
      _render(model: DiffuseModel.lambert, roughness: 0.02),
    );
    final eon = _mean(_render(model: DiffuseModel.eon, roughness: 0.02));
    expect(eon / lambert, closeTo(1.0, 0.02));
  });

  test('white under light from everywhere keeps all of it, grey saturates', () {
    // A white surface lit alike from every side reflects everything under
    // either lobe: that is what energy-preserving means.
    final whiteLambert = _mean(
      _render(model: DiffuseModel.lambert, grey: 1.0, lit: false),
    );
    final whiteEon = _mean(
      _render(model: DiffuseModel.eon, grey: 1.0, lit: false),
    );
    // Mutation: drop the multiple-scattering half of `eonAlbedo`, and white
    // loses five per cent of its light over the sphere, most of it where the
    // sphere faces the eye. Not to the digit: the portable sRGB decode
    // leaves white a hair above one, and the bounces between the facets
    // multiply that hair.
    expect(whiteEon / whiteLambert, closeTo(1.0, 5e-3));

    // A grey one loses a little more at each bounce between the facets: most
    // where it faces the eye, next to nothing at its rim, some five per cent
    // over the sphere.
    final greyLambert = _mean(
      _render(model: DiffuseModel.lambert, grey: 0.5, lit: false),
    );
    final greyEon = _mean(
      _render(model: DiffuseModel.eon, grey: 0.5, lit: false),
    );
    expect(greyEon, lessThan(greyLambert * 0.97));
  });

  test('the lobe integrates to its albedo, and white to one', () {
    // A white furnace by quadrature: the lobe times the cosine, over the
    // hemisphere of light, at a few view angles and roughnesses. What
    // `pbr.glsl` gives the ambient has to be what it gives direct light
    // from every side, or the two halves of the picture disagree.
    for (final r in <double>[0.3, 1.0]) {
      for (final muO in <double>[0.2, 0.6, 1.0]) {
        final v = Vector3(math.sqrt(1.0 - muO * muO), 0.0, muO);
        for (final rho in <double>[1.0, 0.5]) {
          var sum = 0.0;
          const steps = 96;
          for (var i = 0; i < steps; i++) {
            // Uniform in the cosine, which makes the measure dμ dφ.
            final muI = (i + 0.5) / steps;
            final sinI = math.sqrt(1.0 - muI * muI);
            for (var j = 0; j < steps * 2; j++) {
              final phi = (j + 0.5) / (steps * 2) * 2.0 * math.pi;
              final l = Vector3(
                sinI * math.cos(phi),
                sinI * math.sin(phi),
                muI,
              );
              final f = PbrShader.eonLobe(
                Vector3.all(rho),
                r,
                muI,
                muO,
                l.dot(v),
              );
              sum += f.x * muI;
            }
          }
          final integral = sum * (1.0 / steps) * (2.0 * math.pi / (steps * 2));
          final albedo = PbrShader.eonAlbedo(Vector3.all(rho), r, muO).x;
          // The fit of the one-bounce albedo is a fit, so not to the digit.
          expect(integral, closeTo(albedo, 0.01), reason: 'r $r μ $muO ρ $rho');
          if (rho == 1.0) expect(integral, closeTo(1.0, 0.01));
        }
      }
    }
  });
}
