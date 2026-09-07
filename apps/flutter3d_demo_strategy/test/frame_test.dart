/// The hillside and the crowd on it, drawn — not the simulation, the picture.
///
///     flutter test test/frame_test.dart
///
/// **The seam this covers is the one the other demos found the hard way.** A
/// simulation can be right while the picture is wrong, and every test in the
/// strategy package is about the simulation: it can tell a unit walked to a
/// place and cannot tell whether anything was drawn there. The platformer's
/// version of this file crashed on its first run inside the software
/// rasteriser, four frames of stack from anywhere anybody would have looked,
/// because a vertex clipped by the near plane rounds its `w` to zero — and no
/// simulation test could have seen it.
///
/// Counted pixels rather than a golden, for the reason the other two give: a
/// golden of a scene this size fails on every vertex anybody moves and teaches
/// nothing. What is asserted here is that ground was drawn, that a crowd
/// changed it, and that the picture is not one flat colour.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const int _width = 160;
const int _height = 100;

/// What a frame is made of: how much is not the clear colour, and how varied.
({int lit, int deep, int bright, int shades}) _describe(Uint8List rgba) {
  final buckets = <int>{};
  var lit = 0;
  var deep = 0;
  var bright = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final int luminance =
        (rgba[i] * 30 + rgba[i + 1] * 59 + rgba[i + 2] * 11) ~/ 100;
    if (luminance > 6) lit++;
    // Three, not six: the background this camera sees past the edge of the
    // hillside lands under six, and only the fog goes below three. Measured —
    // see the two bounds below.
    if (luminance <= 3) deep++;
    if (luminance > 60) bright++;
    buckets.add(luminance >> 4);
  }
  return (lit: lit, deep: deep, bright: bright, shades: buckets.length);
}

const int _pixels = _width * _height;

void main() {
  test('the map is drawn, and the crowd is in it', () async {
    // The game's own assembly, not a likeness of it: `stage` is what `main`
    // calls, and a harness that built its own hillside would agree with every
    // bug this one has.
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final staged = stage(device: it.device, workers: 40);

    final scene = Scene(name: 'map');
    staged.visuals.addTo(scene);
    scene.add(
      LightNode(
        type: LightType.directional,
        color: vm.Vector3(1.0, 0.96, 0.88),
        intensity: 3.2,
        name: 'sun',
      )..lookAt(vm.Vector3(0.35, -1.0, 0.5)),
    );
    final camera = scene.add(CameraNode(name: 'camera'));
    final views = <RenderView>[RenderView(camera: camera)];

    Future<Uint8List> draw() async {
      staged.match.step(1.0 / 60.0);
      staged.visuals.sync();
      staged.camera.place(1.0 / 60.0);
      camera
        ..setPositionFrom(staged.camera.eye)
        ..lookAt(staged.camera.target);

      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: views,
        settings: const RenderSettings(),
      );
      final pixels = await it.device.readPixels(result.frame);
      expect(pixels, isNotNull, reason: 'the frame could not be read back');
      return pixels!.buffer.asUint8List();
    }

    // A few frames, because the first is the camera's cut and the ones after
    // it are what a player sees.
    for (var i = 0; i < 3; i++) {
      await draw();
    }
    final Uint8List before = await draw();
    final first = _describe(before);

    expect(
      first.lit,
      greaterThan(_width * _height ~/ 4),
      reason:
          'the ground did not draw: a quarter of the frame is the least a '
          'hillside under this camera covers',
    );
    expect(
      first.shades,
      greaterThan(2),
      reason: 'one flat colour is a frame with nothing lit in it',
    );
    // **The fog is drawn, and it has not swallowed the game** — two bounds,
    // because each catches a different way of getting it wrong and neither
    // catches the other. The tiles over unexplored ground are near-black slabs
    // ten metres deep, so a fog that never reaches the frame leaves nothing
    // dark in it, and one placed over the camp instead of beyond it leaves
    // nothing bright. Neither shows up in a simulation test: the lattice is
    // right in both.
    //
    // Measured, not guessed, and the first threshold moved because of it. As
    // drawn: 4138 pixels darker than three and 10686 brighter than sixty, of
    // 16000. With the fog batches never filled: **nought** below three — but
    // 948 below six, which is the background past the edge of the hillside and
    // is why counting unlit pixels let that mistake through. With the
    // visibility test dropped, so that explored ground is covered too: 6628
    // bright.
    expect(
      first.deep,
      greaterThan(_pixels ~/ 20),
      reason: 'no fog reached the frame at all',
    );
    expect(
      first.bright,
      greaterThan(_pixels ~/ 2),
      reason: 'the fog covered the ground the camera is looking at',
    );

    // Send this side's crowd somewhere and let the other side's get on with its
    // work: the picture has to change, which is what says the batch is being
    // written rather than uploaded once. Both halves of that are worth having
    // here — an order given from outside and a policy giving its own — because
    // the drawing cannot tell them apart and neither should this test.
    // Ninety frames rather than the two hundred and forty this started with:
    // the fog is two batches of a couple of thousand slabs, and the software
    // rasteriser fills every one of them, so the frames here cost three times
    // what they used to. A second and a half is still four metres of walking,
    // which is all this needs to see.
    Squad(staged.mine).moveTo(vm.Vector3(80.0, 0.0, 40.0));
    for (var i = 0; i < 90; i++) {
      await draw();
    }
    final Uint8List after = await draw();

    // Byte for byte rather than by any summary: under a camera looking down at
    // ground that fills the frame, every pixel is lit in both pictures, so a
    // count of lit pixels is saturated and cannot see a crowd cross it. What
    // says the batch is written every frame rather than uploaded once is that
    // the pixels are not the same pixels.
    expect(
      after,
      isNot(equals(before)),
      reason: 'nothing in the picture changed while the crowd walked',
    );
  });
}
