/// `soft-particles`: a particle fades by how far the opaque scene lies behind
/// it, over its contributor's softness, instead of being cut by the depth test
/// along a hard line — drawn by the software backend through a real renderer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// How far behind the particle the wall's face stands, in metres.
const double _gap = 0.25;

/// Which of the three stages draws the particle.
enum _Stage { disc, sprite, sixWay }

/// One particle two metres across, five metres ahead, over a black wall [_gap]
/// behind it — or over nothing, without [wall] — drawn with [softness]; the
/// red of the middle pixel, linear.
double _centre({
  required _Stage stage,
  required double softness,
  bool wall = true,
  RenderSettings settings = const RenderSettings(),
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle upload(int width, int height, Uint8List bytes) =>
      device.createTextureFromPixels(
        width: width,
        height: height,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(bytes),
      )!;

  final particles = ParticleSystem(capacity: 1)
    ..burst(
      ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: const Range.exact(2.0),
        color: Vector4(0.8, 0.5, 0.2, 1.0),
      ),
      Vector3(0.0, 0.0, -5.0),
    );

  final camera = CameraNode();
  final scene = Scene()..add(camera);
  if (wall) {
    // Unlit and black, so what the frame holds there is the particle alone.
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(20.0, 20.0, 1.0)).build(),
        ),
        Material(
          lighting: LightingModel.unlit,
          baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      )..setPosition(0.0, 0.0, -5.0 - _gap - 0.5),
    );
  }

  final white = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
  final sheet = stage == _Stage.sixWay
      ? bakeSixWay(density: smokePuff(), frames: 1, columns: 1, cell: 16)
      : null;
  final renderer = Renderer.create(device: device)
    ..addContributor(
      ParticleContributor(
        particles,
        texture: stage == _Stage.sprite ? upload(4, 4, white) : null,
        sixWay: sheet == null
            ? null
            : SixWayMaterial(
                positive: upload(sheet.width, sheet.height, sheet.positive),
                negative: upload(sheet.width, sheet.height, sheet.negative),
                ambient: Vector3(1.0, 1.0, 1.0),
              ),
        softness: softness,
      ),
    );
  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings.copyWith(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
    ),
  );
  final frame = device.readHdrPixels(result.frame);
  // The composite encodes; the comparison is of light.
  final encoded = frame[((_size ~/ 2) * _size + _size ~/ 2) * 4];
  return encoded <= 0.04045
      ? encoded / 12.92
      : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
}

void main() {
  for (final stage in _Stage.values) {
    group('soft-particles, ${stage.name}', () {
      test('fades by how far the wall lies behind, over the softness', () {
        final hard = _centre(stage: stage, softness: 0.0);
        final soft = _centre(stage: stage, softness: 1.0);
        expect(hard, greaterThan(0.05), reason: 'the particle is drawn');
        // The quad faces the camera, so every fragment of it is five metres
        // along the axis and the wall a quarter of a metre behind: a softness
        // of one leaves a quarter.
        expect(soft / hard, closeTo(_gap / 1.0, 0.02));
      });

      test('is untouched a softness or more in front of the scene', () {
        expect(
          _centre(stage: stage, softness: 0.2),
          _centre(stage: stage, softness: 0.0),
          reason: 'the fade saturates at one',
        );
      });

      test('is untouched where nothing was drawn behind it', () {
        expect(
          _centre(stage: stage, softness: 1.0, wall: false),
          _centre(stage: stage, softness: 0.0, wall: false),
          reason: 'the sky is infinitely far, and a zero depth says so',
        );
      });
    });
  }

  test('soft-particles: under weighted blended transparency too', () {
    const settings = RenderSettings(
      transparency: TransparencyMode.weightedBlended,
    );
    final hard = _centre(stage: _Stage.disc, softness: 0.0, settings: settings);
    final soft = _centre(stage: _Stage.disc, softness: 1.0, settings: settings);
    expect(soft / hard, closeTo(_gap, 0.02));
  });

  test('soft-particles: drawn hard when the transparent pass is off', () {
    const settings = RenderSettings(disabledPasses: <String>{'transparent'});
    expect(
      _centre(stage: _Stage.disc, softness: 1.0, settings: settings),
      _centre(stage: _Stage.disc, softness: 0.0, settings: settings),
      reason:
          'with no pass to draw it where the depth is readable, it is '
          'drawn in the scene pass with none, as at nought',
    );
  });
}
