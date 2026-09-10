/// Two eyes drawn into one frame, against the same two drawn separately.
///
///     flutter test test/stereo_test.dart
///
/// **This is the specification of stereo rendering, and it is deliberately
/// written about the meaning rather than about the mechanism.** A pair of views
/// side by side in one target is how the engine draws a headset frame today,
/// because that is what an Android surface swapchain can hold. If it later
/// draws the same pair into the two slices of an array texture — which is what
/// multiview means — this file should pass unchanged, and fail in exactly the
/// place a multiview implementation gets it wrong: per-view data leaking from
/// one eye into the other.
///
/// So the claim under test is: **a view drawn beside another is the same
/// picture as that view drawn alone.** Everything a frame does that is not
/// per-view — a full-screen effect compiled for `views.first`, a blur that
/// crosses the middle of the target — breaks it, which is why
/// `RenderSettings.forStereo` exists and why the last group here shows what it
/// is for rather than asserting it in prose.
///
/// The software rasteriser rather than a device: this is about what the
/// renderer submits, and the backend that shares nothing with a GPU is the one
/// that cannot make two views agree by accident.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One eye, and the pair is twice as wide.
const int _eyeWidth = 64;
const int _eyeHeight = 64;

/// Half the distance between the eyes, in metres. A real one, because the
/// whole point of a stereo frame is that the two views are *not* the same.
const double _halfIpd = 0.032;

/// Roughly the angles a headset states for its left eye: wider outward than
/// inward, and mirrored for the right.
const double _outward = 1.19175359259;
const double _inward = 1.0;

Projection _eyeProjection({required bool left}) => OffAxisProjection(
  tanLeft: left ? -_outward : -_inward,
  tanRight: left ? _inward : _outward,
  tanDown: -_outward,
  tanUp: _outward,
  near: 0.1,
  far: 100.0,
);

/// A scene with something at several depths and off to the sides, so that the
/// two eyes genuinely see different pictures.
({Scene scene, CameraNode left, CameraNode right}) _world() {
  final uploads = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();

  void box(String name, Vector3 at, Vector3 size, Vector4 color) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(uploads, CuboidShape(size: size).build()),
        engine.Material(
          name: name,
          baseColor: color,
          lighting: LightingModel.unlit,
        ),
        name: name,
      )..setPosition(at.x, at.y, at.z),
    );
  }

  // Near and off-centre, which is where parallax is largest.
  box(
    'near',
    Vector3(-0.25, 0.0, -0.9),
    Vector3(0.3, 0.3, 0.3),
    Vector4(1.0, 0.2, 0.2, 1.0),
  );
  box(
    'middle',
    Vector3(0.4, -0.1, -2.2),
    Vector3(0.6, 0.6, 0.6),
    Vector4(0.2, 1.0, 0.3, 1.0),
  );
  // Far and wide: only one eye sees the whole of it.
  box(
    'far',
    Vector3(-1.6, 0.3, -5.0),
    Vector3(1.4, 1.4, 0.4),
    Vector4(0.3, 0.4, 1.0, 1.0),
  );
  box(
    'floor',
    Vector3(0.0, -1.2, -3.0),
    Vector3(8.0, 0.2, 8.0),
    Vector4(0.7, 0.7, 0.7, 1.0),
  );

  final left = scene.add(
    CameraNode(projection: _eyeProjection(left: true), name: 'left'),
  )..setPosition(-_halfIpd, 0.0, 0.0);
  final right = scene.add(
    CameraNode(projection: _eyeProjection(left: false), name: 'right'),
  )..setPosition(_halfIpd, 0.0, 0.0);

  return (scene: scene, left: left, right: right);
}

RenderView _view(CameraNode camera, ViewportRect where) => RenderView(
  camera: camera,
  viewportFraction: where,
  clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
);

Future<Uint8List> _draw({
  required int width,
  required int height,
  required Scene scene,
  required List<RenderView> views,
  required RenderSettings settings,
}) async {
  final it = cpuTestDevice(width: width, height: height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  final result = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: views,
    settings: settings,
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// The left or right half of a pair, as a frame of its own.
Uint8List _half(Uint8List pair, {required bool left}) {
  final out = Uint8List(_eyeWidth * _eyeHeight * 4);
  final rowBytes = _eyeWidth * 4;
  final offset = left ? 0 : rowBytes;
  for (var y = 0; y < _eyeHeight; y++) {
    final from = y * rowBytes * 2 + offset;
    out.setRange(y * rowBytes, (y + 1) * rowBytes, pair, from);
  }
  return out;
}

/// How much of a frame is not the clear colour, as a guard against a
/// comparison between two empty pictures.
int _drawnPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > 8 || rgba[i + 1] > 8 || rgba[i + 2] > 8) count++;
  }
  return count;
}

void main() {
  // What a headset frame is drawn with. Named here rather than inline because
  // every test in the file has to use the same one for the comparison to mean
  // anything.
  final stereoSettings = const RenderSettings(tonemap: false).forStereo();

  group('a pair drawn together is two views drawn apart', () {
    late Uint8List pairLeft;
    late Uint8List pairRight;
    late Uint8List aloneLeft;
    late Uint8List aloneRight;

    setUp(() async {
      final world = _world();
      final pair = await _draw(
        width: _eyeWidth * 2,
        height: _eyeHeight,
        scene: world.scene,
        views: <RenderView>[
          _view(world.left, const ViewportRect(0.0, 0.0, 0.5, 1.0)),
          _view(world.right, const ViewportRect(0.5, 0.0, 0.5, 1.0)),
        ],
        settings: stereoSettings,
      );
      pairLeft = _half(pair, left: true);
      pairRight = _half(pair, left: false);

      aloneLeft = await _draw(
        width: _eyeWidth,
        height: _eyeHeight,
        scene: world.scene,
        views: <RenderView>[
          _view(world.left, const ViewportRect(0.0, 0.0, 1.0, 1.0)),
        ],
        settings: stereoSettings,
      );
      aloneRight = await _draw(
        width: _eyeWidth,
        height: _eyeHeight,
        scene: world.scene,
        views: <RenderView>[
          _view(world.right, const ViewportRect(0.0, 0.0, 1.0, 1.0)),
        ],
        settings: stereoSettings,
      );
    });

    test('there is a picture in both halves at all', () {
      // The guard the rest of the file rests on: two black frames agree
      // perfectly and prove nothing.
      final quarter = _eyeWidth * _eyeHeight ~/ 4;
      expect(_drawnPixels(pairLeft), greaterThan(quarter));
      expect(_drawnPixels(pairRight), greaterThan(quarter));
    });

    test('the left half is the left eye', () {
      final difference = compareFrames(pairLeft, aloneLeft);
      expect(
        difference.differing,
        0,
        reason:
            'the left eye changed when a second view was added: $difference',
      );
    });

    test('the right half is the right eye', () {
      final difference = compareFrames(pairRight, aloneRight);
      expect(
        difference.differing,
        0,
        reason:
            'the right eye changed when it was drawn beside another: '
            '$difference',
      );
    });

    test('the two eyes see different pictures', () {
      // Without this, an implementation that drew the same view twice — or one
      // that let the first view's matrices govern both halves — would pass
      // every check above.
      final difference = compareFrames(pairLeft, pairRight);
      expect(
        difference.percent,
        greaterThan(2.0),
        reason: 'the halves are too alike for two eyes 64 mm apart',
      );
    });

    test('the frustum being off-axis is visible in the frame', () async {
      // The two cameras stand in different places, so a pair would come out
      // different even from a frustum whose shear terms had been dropped — the
      // check above would pass on a symmetrised eye. This one asks the
      // question directly: the same eye, same vertical angle, drawn once with
      // its own asymmetric frustum and once with the symmetric frustum of that
      // angle.
      final world = _world();
      final symmetric = OffAxisProjection.symmetric(
        fovYRadians: _eyeProjection(left: true).verticalFieldOfView!,
        near: 0.1,
        far: 100.0,
      );
      world.left.projection = symmetric;
      final symmetricEye = await _draw(
        width: _eyeWidth,
        height: _eyeHeight,
        scene: world.scene,
        views: <RenderView>[
          _view(world.left, const ViewportRect(0.0, 0.0, 1.0, 1.0)),
        ],
        settings: stereoSettings,
      );

      // A modest share of the frame, because most of it is background: what
      // moves is the geometry, and it moves by the tenth of the width the
      // shear amounts to. The worst channel is what says it moved properly
      // rather than by a rounding step.
      final difference = compareFrames(aloneLeft, symmetricEye);
      expect(difference.worstChannel, greaterThan(64));
      expect(
        difference.percent,
        greaterThan(1.0),
        reason:
            'the eye drew the same picture with and without its off-axis '
            'terms, which means they are not reaching the frame: $difference',
      );
    });
  });

  group('what forStereo takes out, and why', () {
    test('a blur across the whole frame carries one eye into the other', () async {
      // Bloom is a full-frame effect: it does not know the target has a seam
      // down the middle. This is the claim `RenderSettings.forStereo` is making
      // when it turns bloom off, asserted rather than left as prose — and it is
      // what a multiview implementation will have to answer differently, since
      // there the two eyes are separate slices and a blur cannot cross between
      // them.
      final world = _world();
      final bloomy = const RenderSettings(
        tonemap: false,
        bloom: BloomSettings(threshold: 0.2, intensity: 1.5),
      );

      final pair = await _draw(
        width: _eyeWidth * 2,
        height: _eyeHeight,
        scene: world.scene,
        views: <RenderView>[
          _view(world.left, const ViewportRect(0.0, 0.0, 0.5, 1.0)),
          _view(world.right, const ViewportRect(0.5, 0.0, 0.5, 1.0)),
        ],
        settings: bloomy,
      );
      final alone = await _draw(
        width: _eyeWidth,
        height: _eyeHeight,
        scene: world.scene,
        views: <RenderView>[
          _view(world.left, const ViewportRect(0.0, 0.0, 1.0, 1.0)),
        ],
        settings: bloomy,
      );

      final difference = compareFrames(_half(pair, left: true), alone);
      expect(
        difference.differing,
        greaterThan(0),
        reason:
            'the left eye came out identical with a full-frame blur on, which '
            'would mean this test no longer demonstrates anything',
      );
    });
  });
}
