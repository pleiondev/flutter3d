/// The package tested with itself: a frame drawn with no GPU, and a reference
/// image that fails when the picture changes.
///
///     flutter test test/golden_test.dart
///
/// **What is being checked is the promise, not the pixels.** That a scene can be
/// drawn on a machine with no display; that drawing it twice gives the same
/// bytes, which is what lets the tolerance be zero; that a missing reference is
/// recorded rather than failed; and that a changed picture is caught.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 40;
const int _height = 32;

/// A wall of one colour, filling the view.
FrameBuilder _wall(Vector4 colour) => (GraphicsDevice device) {
  final scene = Scene();
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(40.0, 40.0, 1.0)).build(),
      ),
      Material(name: 'wall', baseColor: colour, lighting: LightingModel.unlit),
    )..setPosition(0.0, 0.0, -8.0),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 60.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  scene.add(camera);

  return (scene: scene, camera: camera);
};

/// A directory this test owns and removes, so a run leaves nothing behind.
Directory _scratch() =>
    Directory.systemTemp.createTempSync('flutter3d_testing_');

void main() {
  test('a scene is drawn with no GPU at all', () async {
    // The whole premise. Mutation: none available — this is either possible or
    // the package has no reason to exist.
    final frame = await renderFrame(
      width: _width,
      height: _height,
      build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
    );

    expect(frame.width, _width);
    expect(frame.height, _height);
    expect(frame.pixels, hasLength(_width * _height * 4));
    // Red at the middle, so something was actually drawn rather than cleared.
    final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
    expect(frame.pixels[at], greaterThan(frame.pixels[at + 1]));
  });

  test('and drawing it twice gives the same bytes', () async {
    // **This is what lets the tolerance be zero.** A software rasteriser has no
    // driver, no clock and no thread to disagree with itself, so a difference
    // between two runs would be a bug rather than noise — and a package that
    // told users to allow "a few pixels" would be telling them to stop watching.
    final once = await renderFrame(
      width: _width,
      height: _height,
      build: _wall(Vector4(0.2, 0.7, 0.3, 1.0)),
    );
    final twice = await renderFrame(
      width: _width,
      height: _height,
      build: _wall(Vector4(0.2, 0.7, 0.3, 1.0)),
    );

    expect(twice.pixels, equals(once.pixels));
  });

  group('a reference image', () {
    test('is recorded when there is none, rather than failed', () async {
      // A new test has nothing to compare against. Refusing would mean every one
      // starts red for a reason that is not about the code.
      //
      // Mutation: throw instead of recording — fails here.
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wall.png';

      final frame = await renderFrame(
        width: _width,
        height: _height,
        build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
      );
      await expectMatchesGolden(frame, path);

      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'the first run should leave a reference behind',
      );
    });

    test('and then holds the picture to it', () async {
      // Recorded once, compared twice: the same scene passes against its own
      // reference. Mutation: compare against the wrong file — fails.
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wall.png';

      final first = await renderFrame(
        width: _width,
        height: _height,
        build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
      );
      await expectMatchesGolden(first, path);

      final again = await renderFrame(
        width: _width,
        height: _height,
        build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
      );
      await expectMatchesGolden(again, path);
    });

    test('and catches a picture that changed', () async {
      // **The failure the package exists to produce.** A material edited by
      // accident, a light moved, a shader regressed — all of it arrives here.
      //
      // Mutation: compare `differing` against the tolerance instead of
      // `percent`, or default the tolerance to 100 — a changed picture passes
      // and this fails.
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wall.png';

      final red = await renderFrame(
        width: _width,
        height: _height,
        build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
      );
      await expectMatchesGolden(red, path);

      final green = await renderFrame(
        width: _width,
        height: _height,
        build: _wall(Vector4(0.1, 0.9, 0.1, 1.0)),
      );
      await expectLater(
        expectMatchesGolden(green, path),
        throwsA(isA<TestFailure>()),
      );
    });

    test('and says so when the sizes disagree', () async {
      // A golden recorded at another resolution is not a rendering failure and
      // should not read as one — the message names the real cause, which is that
      // somebody changed the size and did not re-record.
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wall.png';

      final small = await renderFrame(
        width: _width,
        height: _height,
        build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
      );
      await expectMatchesGolden(small, path);

      final large = await renderFrame(
        width: _width * 2,
        height: _height,
        build: _wall(Vector4(0.9, 0.1, 0.1, 1.0)),
      );
      await expectLater(
        expectMatchesGolden(large, path),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
