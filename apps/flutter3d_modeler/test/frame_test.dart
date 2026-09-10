/// The viewport, drawn — not the camera arithmetic, the picture.
///
///     flutter test test/frame_test.dart
///
/// **The seam this covers is the one an application cannot see any other way.**
/// A stage can be assembled correctly and draw nothing: a light pointing away, a
/// camera inside the subject, a mesh uploaded with a layout the material does
/// not read. None of that is visible to a test that asserts on the scene graph,
/// and all of it is visible in eight hundred pixels.
///
/// Through `staging.dart`, because `no test builds its own world` in
/// `tool/structure.dart` says so and because a harness that built its own cube
/// would agree with any bug the application's cube has.
///
/// Counted pixels rather than a golden. A golden of a lit cube fails the day
/// somebody moves the fill light by five degrees and teaches nothing; what is
/// asserted here is that the subject was drawn, that it is lit from one side,
/// and that framing it put it in front of the camera.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_mesh/testing.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 100;
const int _pixels = _width * _height;

/// What a frame is made of: how much of it is not the background, how bright
/// the brightest of that is, and how many distinct shades there are.
({int subject, int bright, int shades}) _describe(Uint8List rgba) {
  final shades = <int>{};
  var subject = 0;
  var bright = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final luminance =
        (rgba[i] * 30 + rgba[i + 1] * 59 + rgba[i + 2] * 11) ~/ 100;
    // The background is `#0E1112`, which lands at 17 through this weighting.
    // Anything above 24 is something that was drawn into it.
    if (luminance > 24) subject++;
    if (luminance > 120) bright++;
    shades.add(luminance >> 4);
  }
  return (subject: subject, bright: bright, shades: shades.length);
}

Future<Uint8List> _draw(
  GraphicsDevice device,
  Renderer renderer,
  ModelerStage stage,
) async {
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: stage.scene,
    views: stage.views(),
    settings: const RenderSettings(),
  );
  final pixels = await device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

void main() {
  test('the cube a project starts as is drawn, and it is lit', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();

    final frame = _describe(await _draw(it.device, renderer, stage));

    // A framed cube seen from a three-quarter angle covers between a sixth and
    // two thirds of the viewport. Both bounds matter: too little is a cube
    // that did not draw or is far away, too much is a camera inside it.
    expect(
      frame.subject,
      greaterThan(_pixels ~/ 6),
      reason: 'the cube did not draw, or is not in front of the camera',
    );
    expect(
      frame.subject,
      lessThan(_pixels * 2 ~/ 3),
      reason: 'the camera is inside the cube, or the framing did not happen',
    );

    // **Lit from a direction, which is a stronger claim than "lit".** A `pbr`
    // material with no light on it at all still comes back bright here — the
    // renderer's neutral environment is what a material samples when nothing
    // else lights it — so a check for brightness passes on a scene with the
    // lights turned off, and the first version of this file made exactly that
    // mistake. What separates the two is the *spread*: with both lights at
    // zero the frame holds four bands of luminance and every drawn pixel is in
    // the bright one; with the key and the fill where `staging.dart` puts
    // them, it holds eight and a face is in shadow.
    expect(
      frame.shades,
      greaterThanOrEqualTo(6),
      reason: 'the faces are all one value, so no light has a direction',
    );
    expect(
      frame.subject - frame.bright,
      greaterThan(_pixels ~/ 100),
      reason: 'no face is in shadow: the key light is not reaching one side',
    );
  });

  test('the background is the one the design names, not the default', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    // Pushed far enough away that the corner pixel is background and nothing
    // else, without moving the camera off the subject.
    stage.orbit
      ..distance = 40
      ..apply();

    final rgba = await _draw(it.device, renderer, stage);

    // Top-left pixel. `#0E1112` through the composite, which tone maps: what
    // is asserted is the hue rather than the exact byte — blue above green
    // above red, all of them dark — because a flat dark background that had
    // gone grey or gone blue would both pass a "is it dark" check.
    final r = rgba[0];
    final g = rgba[1];
    final b = rgba[2];
    expect(r, lessThan(60), reason: 'the background is not dark');
    expect(g, greaterThanOrEqualTo(r));
    expect(b, greaterThanOrEqualTo(g));
  });

  test('orbiting changes the picture, and does not lose the subject', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();

    final before = await _draw(it.device, renderer, stage);
    // A quarter turn, the way a drag of two hundred pixels would.
    stage.orbit
      ..rotate(200, 0)
      ..apply();
    final after = await _draw(it.device, renderer, stage);

    expect(
      after,
      isNot(equals(before)),
      reason: 'the camera moved and the frame did not follow it',
    );
    expect(
      _describe(after).subject,
      greaterThan(_pixels ~/ 6),
      reason: 'the subject left the view when the camera turned',
    );
  });

  group('the spike, drawn', () {
    // `mesh-01`'s last line: the half-edge cube with a face extruded, rendered
    // by the software rasteriser and held to a recorded picture. Everything
    // before this is arithmetic — the Euler characteristic, the volume — and
    // arithmetic cannot say that the mesh a person would see is the mesh the
    // operation built.
    test('a cube with one face extruded matches its reference', () async {
      final frame = await renderFrame(
        width: 240,
        height: 160,
        build: (FrameRequest request) {
          final stage = ModelerStage.build(device: request.device);
          // The stage's own cube, replaced by the extruded one: the scene, the
          // lights and the camera stay the application's, which is what
          // `no test builds its own world` is about, and only the geometry
          // under test changes.
          final subject = stage.subject as MeshNode;
          subject.mesh = DeviceMesh.upload(
            request.device,
            EditMesh.cuboid().extrudeFace(0, 0.5).toMeshData(),
          );
          stage.frameSubject();
          return (scene: stage.scene, camera: stage.camera);
        },
      );

      await expectMatchesGolden(frame, 'test/goldens/mesh-spike-extrude.png');
    });
  });

  group('the operations, drawn', () {
    // `mesh-33`: four fixtures from `flutter3d_mesh/testing.dart`, each one
    // the smallest shape that would *look* wrong if the operation under it
    // broke. Everything else about these operations is arithmetic — Euler
    // characteristics, volumes, counts — and arithmetic cannot say that a wall
    // is there, that a cut went in straight, that a pole closed, or that a rim
    // still shades hard.
    //
    // Zero tolerance, because the rasteriser is deterministic and these are
    // pictures of geometry rather than of lighting: a pixel that moved is a
    // vertex that moved.
    for (final subject in <(String, EditMesh Function())>[
      ('mesh-extrude', extrudedBox),
      ('mesh-loop-cut', cutCylinder),
      ('mesh-lathe', turnedProfile),
      ('mesh-sharp-vs-smooth', sharpAgainstSmooth),
    ]) {
      test('${subject.$1} matches its reference', () async {
        final frame = await renderFrame(
          width: 240,
          height: 160,
          build: (FrameRequest request) {
            final stage = ModelerStage.build(device: request.device);
            final node = stage.subject as MeshNode;
            node.mesh = DeviceMesh.upload(
              request.device,
              subject.$2().toMeshData(),
            );
            stage.frameSubject();
            return (scene: stage.scene, camera: stage.camera);
          },
        );

        await expectMatchesGolden(frame, 'test/goldens/${subject.$1}.png');
      });
    }
  });
}
