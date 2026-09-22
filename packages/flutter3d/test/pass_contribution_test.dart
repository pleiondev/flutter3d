/// `gfx-42n`: what one pass actually did to a frame.
///
///     flutter test test/pass_contribution_test.dart
///
/// **Both halves are needed, and that is the whole claim.** A per-pass switch
/// on its own gives two pictures somebody has to eyeball. A deterministic
/// reference rasteriser on its own gives no pair to difference. Together they
/// answer the question asked of every effect that ships off by default —
/// *what is this doing to my picture* — as a number rather than an opinion.
///
/// Every engine surveyed for the parity work has the switch. None of them has
/// the second half.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A bright ball on black, rendered with [settings].
Future<ByteData> _frame(RenderSettings settings) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.4).build()),
        Material(
          name: 'hot',
          baseColor: Vector4(8.0, 8.0, 8.0, 1.0),
          lighting: LightingModel.unlit,
        ),
      ),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: settings,
  );
  return (await device.readPixels(frame.frame))!;
}

/// The same frame with and without one named pass.
Future<PassContribution> _contributionOf(String pass) async {
  const with_ = RenderSettings(bloom: BloomSettings(intensity: 0.8));
  final without = RenderSettings(
    bloom: const BloomSettings(intensity: 0.8),
    disabledPasses: <String>{pass},
  );
  return contributionBetween(
    await _frame(without),
    await _frame(with_),
    width: _size,
    height: _size,
  );
}

void main() {
  test('a pass that ran shows up as a measurable difference', () async {
    // One settings value produces both frames, which is what makes this a
    // contribution rather than two renders somebody hopes are comparable.
    final bloom = await _contributionOf('bloom');

    expect(bloom.isIdentical, isFalse);
    expect(bloom.changedPixels, greaterThan(0));
    expect(
      bloom.worstChannelDelta,
      greaterThan(0),
      reason: 'a glow that changes pixels by nothing is not a glow',
    );
  });

  test(
    'the count and the worst are both reported, because either alone lies',
    () async {
      // A pass that moves every pixel by one is a rounding; a pass that moves
      // forty pixels to black is a hole in the picture. Neither number can tell
      // those apart on its own, which is why the type carries both.
      final bloom = await _contributionOf('bloom');
      expect(bloom.changedFraction, greaterThan(0.0));
      expect(bloom.changedFraction, lessThanOrEqualTo(1.0));
      expect(
        bloom.meanChannelDelta,
        greaterThan(0.0),
        reason:
            'the mean is over the pixels that changed, so an effect in a '
            'corner reports its own strength rather than the frame\'s size',
      );
    },
  );

  test('the change is bounded, which is how a leak would show', () async {
    // A glow around a ball in the middle should not reach the frame's edge.
    // This is the shape of the check that catches an effect wrapping or
    // bleeding somewhere it was never meant to be.
    final bloom = await _contributionOf('bloom');
    final bounds = bloom.bounds!;

    expect(bounds.left, lessThan(bounds.right));
    expect(bounds.top, lessThan(bounds.bottom));
    expect(
      bounds.right - bounds.left,
      lessThan(_size),
      reason:
          'the glow of a small ball covering the whole width would be a '
          'wrap rather than a bloom',
    );
  });

  test('a pass with nothing to do contributes exactly nothing', () async {
    // Ambient occlusion is off in these settings, so disabling it by name
    // cannot change a pixel — and the difference has to be exactly zero
    // rather than nearly so, or the measure has noise in it and every number
    // above is suspect.
    final ao = await _contributionOf('ssao');
    expect(ao.isIdentical, isTrue);
    expect(ao.bounds, isNull);
    expect(ao.meanChannelDelta, 0.0);
  });

  test(
    'frames of different sizes are refused rather than differenced',
    () async {
      // A difference between two different pictures is not a contribution, and
      // returning a number for it would be worse than throwing.
      final frame = await _frame(const RenderSettings());
      expect(
        () =>
            contributionBetween(frame, frame, width: _size, height: _size + 1),
        throwsArgumentError,
      );
    },
  );
}
