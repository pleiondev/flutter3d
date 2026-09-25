/// The split sum, the energy compensation and the least roughness all answer
/// to the one GGX lobe the lit stage evaluates.
///
///     dart test test/brdf_dfg_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_core/src/engine/render/engine_tables.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_ltc.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

/// The engine's LTC table as the software rasteriser samples it.
BoundTexture _table() {
  final device = CpuDevice(
    width: 1,
    height: 1,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final pixels = device.readHdrPixels(EngineTables.of(device).ltc);
  final texture = CpuTexture(64, 128, TextureFormat.r32g32b32a32Float)
    ..pixels.setAll(0, pixels);
  return BoundTexture(texture, SamplerOptions.linearClamp);
}

/// The split sum of `pbr.glsl`'s own lobe — GGX of alpha `roughness²` with
/// height-correlated Smith — at a view of cosine [mu], the long way: the
/// half vector drawn from `D · cos θh` on a [steps]² grid, each sample
/// weighted by what is left of `D · Vis · cos θl` over that density. Returns
/// the albedo and its share weighted by Schlick's `(1 − v·h)⁵`.
({double albedo, double fresnel}) _splitSum(
  double roughness,
  double mu, {
  int steps = 512,
}) {
  final alpha = roughness * roughness;
  final a2 = alpha * alpha;
  final vx = math.sqrt(1.0 - mu * mu);
  var albedo = 0.0;
  var fresnel = 0.0;
  for (var i = 0; i < steps; i++) {
    final u1 = (i + 0.5) / steps;
    final cosH = math.sqrt((1.0 - u1) / (1.0 + (a2 - 1.0) * u1));
    final sinH = math.sqrt(1.0 - cosH * cosH);
    for (var j = 0; j < steps; j++) {
      final phi = 2.0 * math.pi * (j + 0.5) / steps;
      final hx = sinH * math.cos(phi);
      final vDotH = vx * hx + mu * cosH;
      final nDotL = 2.0 * vDotH * cosH - mu;
      if (vDotH <= 0.0 || nDotL <= 0.0) continue;
      final lambdaV = nDotL * math.sqrt(mu * mu * (1.0 - a2) + a2);
      final lambdaL = mu * math.sqrt(nDotL * nDotL * (1.0 - a2) + a2);
      final vis = 0.5 / (lambdaV + lambdaL);
      final w = vis * nDotL * 4.0 * vDotH / cosH;
      albedo += w;
      fresnel += w * math.pow(1.0 - vDotH, 5.0);
    }
  }
  final n = steps * steps;
  return (albedo: albedo / n, fresnel: fresnel / n);
}

/// A frame of [scene] as the numbers the material wrote: the measurement
/// settings, and the display encoding the composite writes undone.
Float32List _render({
  required int size,
  required Scene scene,
  required CameraNode camera,
  required CpuDevice device,
  bool compensate = false,
}) {
  final result = Renderer.create(device: device).render(
    width: size,
    height: size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(energyCompensation: compensate).forMeasurement(),
  );
  double linear(double e) =>
      e <= 0.04045 ? e / 12.92 : math.pow((e + 0.055) / 1.055, 2.4).toDouble();
  return Float32List.fromList(<double>[
    for (final e in device.readHdrPixels(result.frame)) linear(e),
  ]);
}

CpuDevice _device(int size) => CpuDevice(
  width: size,
  height: size,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// A white metal sphere of [roughness] inside an environment that is white
/// all round, and no light but that: every pixel of it is the split sum's
/// albedo at that pixel's view.
Float32List _furnace(double roughness, int size) {
  final device = _device(size);
  const cube = 4;
  final faces = <ByteData>[
    for (var face = 0; face < 6; face++)
      ByteData.sublistView(
        Uint8List.fromList(<int>[
          for (var i = 0; i < cube * cube; i++) ...<int>[255, 255, 255, 255],
        ]),
      ),
  ];
  const levels = 3;
  final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, const SphereShape().build()),
        Material(
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          metallic: 1.0,
          roughness: roughness,
        ),
      ),
    )
    ..add(camera)
    ..environment = device.createCubeTextureFromPixels(
      size: cube,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: faces,
      mipLevels: EnvironmentMap.prefilter(faces, size: cube, levels: levels),
    )
    ..environmentLevels = levels
    ..ambientIntensity = 1.0
    ..defaultLightWhenUnlit = false;
  return _render(size: size, scene: scene, camera: camera, device: device);
}

/// The red channel at pixel ([x], [y]).
double _red(Float32List hdr, int size, int x, int y) => hdr[(y * size + x) * 4];

void main() {
  group('the split sum is the integral of the lobe the lights evaluate', () {
    final table = _table();
    for (final (roughness, mu) in <(double, double)>[
      (0.3, 1.0),
      (0.5, 1.0),
      (0.5, 0.2),
      (0.7, 0.5),
      (1.0, 1.0),
      (1.0, 0.2),
    ]) {
      test('roughness $roughness, n·v $mu', () {
        final expected = _splitSum(roughness, mu);
        final dfg = envBrdf(table, roughness, mu);
        // Within two hundredths: the table is 64 entries a side and half
        // floats. Mutation: Karis' analytic fit in place of the table reads
        // 0.725 against 0.916 at roughness one half head-on, and 0.45
        // against 0.31 and 0.64 at roughness one.
        expect(dfg.scale + dfg.bias, closeTo(expected.albedo, 0.02));
        expect(dfg.bias, closeTo(expected.fresnel, 0.01));
      });
    }
  });

  test('a white metal in a white furnace reflects its lobe\'s albedo', () {
    const size = 64;
    const centre = size ~/ 2;
    for (final roughness in <double>[0.5, 1.0]) {
      final hdr = _furnace(roughness, size);
      final head = _red(hdr, size, centre, centre);
      expect(head, closeTo(_splitSum(roughness, 1.0).albedo, 0.03));
    }
    // A rough metal brightens towards its rim, as its albedo rises towards
    // grazing. Mutation: the analytic fit is flat in the view at roughness
    // one, and the rim comes out no brighter than the middle.
    final rough = _furnace(1.0, size);
    // The last pixel of the sphere along the middle row: the background is
    // the one-texel black a scene's sky leaves, far below any of it.
    final rim = <double>[
      for (var x = centre; x < size; x++) _red(rough, size, x, centre),
    ].lastWhere((value) => value > 0.1);
    expect(rim, greaterThan(_red(rough, size, centre, centre) * 1.3));
  });

  test('energy compensation barely moves a polished metal', () {
    // White metal of roughness 0.3, lit from the camera's side: its lobe
    // already keeps ninety-nine per cent of the light head-on, so there is
    // next to nothing to put back.
    double brightness({required bool compensate}) {
      const size = 48;
      final device = _device(size);
      final camera = CameraNode()..setPosition(0.0, 0.0, 2.0);
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(device, const SphereShape().build()),
            Material(
              baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
              metallic: 1.0,
              roughness: 0.3,
            ),
          ),
        )
        ..add(LightNode(intensity: 3.0, castsShadow: false))
        ..add(camera)
        ..ambientIntensity = 0.0;
      final hdr = _render(
        size: size,
        scene: scene,
        camera: camera,
        device: device,
        compensate: compensate,
      );
      var sum = 0.0;
      for (var i = 0; i < hdr.length; i += 4) {
        sum += hdr[i];
      }
      return sum;
    }

    // Mutation: the compensation's albedo from the analytic fit, 0.835 here
    // head-on, and the highlight gains a fifth that was never lost.
    expect(
      brightness(compensate: true) / brightness(compensate: false),
      closeTo(1.0, 0.04),
    );
  });

  test('a mirror\'s highlight keeps its light', () {
    // A white metal plane seen straight down through a narrow lens, with the
    // sun behind the camera: the highlight spreads over many pixels, and its
    // sum over them is what the lobe reflects. A glTF roughness of nought and
    // one of 0.06 both reflect all but a trace of the light.
    double highlight(double roughness) {
      const size = 256;
      final device = _device(size);
      final camera =
          CameraNode(
              projection: const PerspectiveProjection(
                fovYRadians: 0.2,
                near: 0.5,
                far: 10.0,
              ),
            )
            ..setPosition(0.0, 2.0, 0.0)
            ..setRotationYawPitchRoll(0.0, -math.pi / 2, 0.0);
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              const PlaneShape(width: 4.0, depth: 4.0).build(),
            ),
            Material(
              baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
              metallic: 1.0,
              roughness: roughness,
            ),
          ),
        )
        // Dim, so the peak of the narrowest lobe stays inside a half float.
        ..add(
          LightNode(intensity: 0.01, castsShadow: false)
            ..setRotationYawPitchRoll(0.0, -math.pi / 2, 0.0),
        )
        ..add(camera)
        ..ambientIntensity = 0.0;
      final hdr = _render(
        size: size,
        scene: scene,
        camera: camera,
        device: device,
      );
      var sum = 0.0;
      for (var i = 0; i < hdr.length; i += 4) {
        sum += hdr[i];
      }
      return sum;
    }

    // Mutation: the old least roughness, 0.02, under the old guard of 10⁻⁶
    // on the denominator: the guard cuts the peak, and roughness nought
    // keeps under a third of what 0.06 does.
    expect(highlight(0.0) / highlight(0.06), closeTo(1.0, 0.1));
  });
}
