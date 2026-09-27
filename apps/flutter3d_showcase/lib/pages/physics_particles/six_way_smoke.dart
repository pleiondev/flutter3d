/// Three puffs of smoke between a red light and a blue one, each side of each
/// puff taking the light on that side through a six-way sheet.
///
/// Quoted by `six_way_smoke.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SixWaySmokeDemo extends ShowcaseDemo {
  bool sixWay = true;
  double angle = 0.0;
  double intensity = 12.0;
  double ambient = 0.0;

  late final ParticleSystem _particles;
  late final SixWayMaterial _sheet;
  late final ParticleContributor _lit;
  late final ParticleContributor _plain;
  late final LightNode _red;
  late final LightNode _blue;

  static const int _cell = 24;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.0
      ..yaw = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    // #region upload
    final ({Uint8List positive, Uint8List negative}) baked = _bakeBall(_cell);
    TextureHandle upload(Uint8List bytes) =>
        context.device.createTextureFromPixels(
          width: _cell,
          height: _cell,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(bytes),
        )!;
    _sheet = SixWayMaterial(
      positive: upload(baked.positive),
      negative: upload(baked.negative),
    );
    // #endregion upload

    // #region puffs
    _particles = ParticleSystem(capacity: 8);
    _burst();
    _lit = ParticleContributor(_particles, sixWay: _sheet);
    _plain = ParticleContributor(_particles);
    context.renderer.addContributor(_lit);
    // #endregion puffs

    // #region lights
    LightNode point(Vector3 colour) =>
        LightNode(type: LightType.point, intensity: intensity, color: colour)
          ..castsShadow = false;
    _red = point(Vector3(1.0, 0.2, 0.1));
    _blue = point(Vector3(0.1, 0.2, 1.0));
    final Scene scene = Scene()
      ..ambientIntensity = 0.0
      ..defaultLightWhenUnlit = false
      ..add(_red)
      ..add(_blue);
    // #endregion lights

    // A dark wall far behind, so the frame has something with bounds.
    return scene..add(
      MeshNode(
        DeviceMesh.upload(
          context.device,
          CuboidShape(size: Vector3(40.0, 40.0, 0.1)).build(),
        ),
        Material(
          lighting: LightingModel.unlit,
          baseColor: Vector4(0.04, 0.04, 0.05, 1.0),
        ),
        name: 'backdrop',
      )..setPosition(0.0, 0.0, -6.0),
    );
  }

  /// Three puffs in a row that stand still for eight seconds.
  void _burst() {
    for (final double x in <double>[-0.4, 0.0, 0.4]) {
      _particles.burst(
        ParticleEffect(
          count: 1,
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
          lifetime: const Range.exact(8.0),
          size: const Range.exact(1.6),
          color: Vector4(1.0, 1.0, 1.0, 1.0),
        ),
        Vector3(x, 0.0, x * 0.5),
      );
    }
  }

  @override
  void update(DemoContext context, double dt) {
    _particles.advance(dt);
    if (_particles.aliveCount == 0) _burst();

    // #region orbit
    final double c = math.cos(angle) * 3.0;
    final double s = math.sin(angle) * 3.0;
    _red
      ..setPosition(-c, 0.0, -s)
      ..intensity = intensity;
    _blue
      ..setPosition(c, 0.0, s)
      ..intensity = intensity;
    _sheet.ambient.setValues(ambient, ambient, ambient);
    // #endregion orbit

    // #region swap
    final ParticleContributor shown = sixWay ? _lit : _plain;
    final ParticleContributor hidden = sixWay ? _plain : _lit;
    if (context.renderer.removeContributor(hidden)) {
      context.renderer.addContributor(shown);
    }
    // #endregion swap
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Six-way sheet',
      value: () => sixWay,
      onChanged: (bool v) => sixWay = v,
    ),
    SliderControl(
      'Lights around the puffs',
      min: 0.0,
      max: 2.0 * math.pi,
      value: () => angle,
      onChanged: (double v) => angle = v,
      format: (double v) => '${(v * 180.0 / math.pi).round()} deg',
    ),
    SliderControl(
      'Light intensity',
      min: 0.0,
      max: 24.0,
      value: () => intensity,
      onChanged: (double v) => intensity = v,
      format: (double v) => v.toStringAsFixed(1),
    ),
    SliderControl(
      'Ambient',
      min: 0.0,
      max: 0.3,
      value: () => ambient,
      onChanged: (double v) => ambient = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_particles.aliveCount != 3 || !_lit.isActive) {
      throw StateError('the three puffs are not alive');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the frame drew nothing');
    }
    // #endregion check
  }
}

// #region bake
/// A six-way sheet of one frame, [n] pixels square, of a soft ball of smoke.
///
/// Single scattering along the six axes: the light reaching a voxel from one
/// side is the density summed along its row to that side's face, and each
/// pixel marches once from the viewer through its column. The layout is the
/// one `SixWayMaterial` reads: positive holds right, top, back and coverage,
/// negative holds left, bottom, front and emission, unpremultiplied, and the
/// rows run bottom to top.
({Uint8List positive, Uint8List negative}) _bakeBall(int n) {
  const double extinction = 6.0;
  final double step = 2.0 / n;
  double at(int i) => -1.0 + (i + 0.5) * step;
  int index(int x, int y, int z) => (z * n + y) * n + x;

  final Float64List sigma = Float64List(n * n * n);
  for (var z = 0; z < n; z++) {
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final double r =
            math.sqrt(at(x) * at(x) + at(y) * at(y) + at(z) * at(z)) / 0.8;
        sigma[index(x, y, z)] = extinction * ((1.0 - r) * 2.5).clamp(0.0, 1.0);
      }
    }
  }

  // How much the smoke takes out between each voxel and the face each light
  // comes in through: right, left, top, bottom, back (from -z), front.
  final List<Float64List> depth = List<Float64List>.generate(
    6,
    (_) => Float64List(n * n * n),
  );
  void sweep(Float64List into, int Function(int a, int b, int s) voxel) {
    for (var a = 0; a < n; a++) {
      for (var b = 0; b < n; b++) {
        var total = 0.0;
        for (var s = 0; s < n; s++) {
          final int i = voxel(a, b, s);
          into[i] = total + sigma[i] * step * 0.5;
          total += sigma[i] * step;
        }
      }
    }
  }

  sweep(depth[0], (int y, int z, int s) => index(n - 1 - s, y, z));
  sweep(depth[1], (int y, int z, int s) => index(s, y, z));
  sweep(depth[2], (int x, int z, int s) => index(x, n - 1 - s, z));
  sweep(depth[3], (int x, int z, int s) => index(x, s, z));
  sweep(depth[4], (int x, int y, int s) => index(x, y, s));
  sweep(depth[5], (int x, int y, int s) => index(x, y, n - 1 - s));

  int byte(double v) => (v.clamp(0.0, 1.0) * 255.0 + 0.5).floor();
  final Uint8List positive = Uint8List(n * n * 4);
  final Uint8List negative = Uint8List(n * n * 4);
  final Float64List lit = Float64List(6);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      lit.fillRange(0, 6, 0.0);
      var through = 1.0;
      for (var z = n - 1; z >= 0; z--) {
        final int i = index(x, y, z);
        final double absorbed = 1.0 - math.exp(-sigma[i] * step);
        final double weight = through * absorbed;
        for (var d = 0; d < 6; d++) {
          lit[d] += weight * math.exp(-depth[d][i]);
        }
        through *= 1.0 - absorbed;
      }
      final double coverage = 1.0 - through;
      final double scale = coverage > 1e-4 ? 1.0 / coverage : 0.0;
      final int out = (y * n + x) * 4;
      positive
        ..[out] = byte(lit[0] * scale)
        ..[out + 1] = byte(lit[2] * scale)
        ..[out + 2] = byte(lit[4] * scale)
        ..[out + 3] = byte(coverage);
      negative
        ..[out] = byte(lit[1] * scale)
        ..[out + 1] = byte(lit[3] * scale)
        ..[out + 2] = byte(lit[5] * scale)
        ..[out + 3] = 0;
    }
  }
  return (positive: positive, negative: negative);
}

// #endregion bake
