/// Ambient occlusion darkens what cannot see the sky.
///
///     flutter test test/ssao_test.dart
///
/// It arrived after the hemispheric ambient rather than before, and the order
/// was the point: occlusion darkens the ambient term, and while that term was
/// one grey scalar at 0.06 a correct occlusion took six per cent off the
/// corners and was invisible. The temptation then is to multiply everything,
/// which is not occlusion but dirt, and reads as a mistake under direct light.
///
/// Three things have to hold:
///
///   * off is *exactly* off — every golden in every set is recorded against
///     that, and "nearly one" is not the same claim as one. Said without a
///     number on purpose: this line carried "thirty-one goldens" for eight
///     scenes past the point where that was true, and the rule that recounts
///     the scenes reads the scripts, `ARCHITECTURE.md` and the site, not Dart;
///   * an inside corner goes darker than a flat wall lit the same way;
///   * the sky, where nothing was drawn, occludes nothing — otherwise every
///     silhouette in the frame gains a dark outline, which is the classic way
///     this effect is got wrong.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 80;
const int _height = 64;

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// Two walls meeting at a right angle, lit only by ambient.
///
/// Only by ambient, because occlusion multiplies the ambient term and a
/// directional light in shot would be ninety per cent of every pixel. The
/// ambient is turned well up for the same reason — the default 0.06 is what
/// made this effect impossible to see before there was anything to see it in.
({Scene scene, CameraNode camera}) _corner() {
  final scene = Scene()..ambientIntensity = 0.9;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  MeshNode slab(Vector3 size, Vector3 at, String name) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(
      name: name,
      baseColor: Vector4(0.7, 0.7, 0.7, 1.0),
      lighting: LightingModel.lambert,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  // Floor and back wall, meeting along z = 2. The corner between them is the
  // only enclosed place in the scene.
  scene.add(slab(Vector3(8.0, 0.4, 8.0), Vector3(0.0, -0.2, 0.0), 'floor'));
  scene.add(slab(Vector3(8.0, 4.0, 0.4), Vector3(0.0, 2.0, 2.2), 'wall'));

  final camera = CameraNode()
    ..setPosition(0.0, 1.6, -3.4)
    ..lookAt(Vector3(0.0, 0.35, 2.0));
  return (scene: scene, camera: camera);
}

RenderSettings _settings({required bool ao}) => RenderSettings(
  bloom: const BloomSettings(enabled: false),
  ambientOcclusion: AmbientOcclusionSettings(
    enabled: ao,
    // Wide enough to reach across the corner in a scene measured in
    // metres. The default half-metre is a room; this scene is one.
    radius: 0.8,
    strength: 1.0,
  ),
);

/// One slab in front of nothing at all.
///
/// Convex and isolated, so a correct occlusion pass has nothing to find on it —
/// which makes any darkening a defect rather than a matter of degree.
({Scene scene, CameraNode camera}) _lone() {
  final scene = Scene()..ambientIntensity = 0.9;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(1.6, 1.6, 0.4)).build(),
      ),
      Material(
        name: 'slab',
        baseColor: Vector4(0.7, 0.7, 0.7, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'slab',
    ),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, -3.0)
    ..lookAt(Vector3.zero());
  return (scene: scene, camera: camera);
}

Future<Uint8List> _draw(RenderSettings settings, {bool lone = false}) async {
  final engine = _engine();
  final room = lone ? _lone() : _corner();
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: settings,
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

int _luma(Uint8List rgba, int x, int y) {
  final i = (y * _width + x) * 4;
  return (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
}

void main() {
  test('off is exactly off', () async {
    // The claim the whole set of goldens rests on, and it is a claim about
    // arithmetic rather than about appearance: the multiplier has to be one,
    // not a value that rounds to it.
    //
    // **Two independent things make it one, and that was measured rather than
    // assumed.** The composite zeroes the strength when there is no occlusion
    // to apply, *and* the sampler that must not be left unbound gets a 1×1
    // white texture. Breaking either one alone leaves this test green — both
    // mutations were applied and both passed — because the other still carries
    // it. Breaking both together fails here. That is worth knowing before
    // someone deletes one of them as redundant: it is redundant, deliberately,
    // and the redundancy is the reason no mismatch between the two can darken
    // a frame that asked for nothing.
    final without = await _draw(_settings(ao: false));
    final plain = await _draw(
      const RenderSettings(bloom: BloomSettings(enabled: false)),
    );
    expect(
      without,
      orderedEquals(plain),
      reason: 'a disabled occlusion changed the picture',
    );
  });

  test('an inside corner goes darker than the open floor', () async {
    // Mutation: drop the range check, or the hemisphere flip, or read the
    // depth from the wrong channel. The corner stops darkening, which is the
    // whole effect.
    final without = await _draw(_settings(ao: false));
    final with_ = await _draw(_settings(ao: true));

    // Rows read off the frame rather than guessed at. Every pixel of this
    // scene is 204 with the occlusion off — flat ambient on flat grey, wall and
    // floor alike — so there is no brightness to navigate by, and the first
    // version of this test picked its two rows blind and got them the wrong way
    // round. Row 46 is where the floor meets the wall; row 60 is open floor
    // near the camera.
    var corner = 0, open = 0;
    for (var x = _width ~/ 3; x < _width * 2 ~/ 3; x++) {
      corner += without[(46 * _width + x) * 4] - with_[(46 * _width + x) * 4];
      open += without[(60 * _width + x) * 4] - with_[(60 * _width + x) * 4];
    }
    expect(corner, greaterThan(0), reason: 'the corner did not darken at all');
    expect(
      corner,
      greaterThan(open * 3),
      reason:
          'the corner darkened no more than the open floor did: this is '
          'a uniform dimming, not occlusion',
    );
  });

  test('nothing near a silhouette darkens against empty background', () async {
    // The classic way this effect is got wrong. A tap that lands where nothing
    // was drawn is a tap looking *out* of the scene, which is the opposite of
    // being enclosed — but the cleared buffer holds a depth of zero, and zero
    // is nearer than anything, so an unguarded comparison counts it as an
    // occluder. The result is a dark rim around every silhouette in the frame,
    // and it is convincing enough to be mistaken for contact shadow.
    //
    // A lone slab is the whole test: it is convex, isolated, and its own back
    // is the only thing it cannot see, so a correct pass leaves it untouched
    // everywhere. Only its edges have sky to look at.
    //
    // Mutation: remove the `there.a <= 0` guard in the sample loop.
    final without = await _draw(_settings(ao: false), lone: true);
    final with_ = await _draw(_settings(ao: true), lone: true);

    var worst = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final delta = _luma(without, x, y) - _luma(with_, x, y);
        if (delta > worst) worst = delta;
      }
    }
    expect(
      worst,
      lessThanOrEqualTo(2),
      reason:
          'an isolated convex slab darkened by $worst: something is '
          'treating the empty background as an occluder',
    );
  });
}
