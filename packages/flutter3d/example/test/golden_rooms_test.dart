/// The two rooms added for the effects nothing had ever recorded.
///
///     flutter test test/golden_rooms_test.dart
///
/// A golden cannot be checked here — recording one needs a device and a run of
/// `tool/golden.sh` — but the thing that goes wrong first can be. A room
/// arranged so that the effect it exists for has nothing to do produces a
/// reference nobody can tell from a correct one: a floor with no reflection in
/// it and a corner with no darkening look exactly like a floor and a corner,
/// and both of these scenes are the first frame of their effect in this
/// repository, so neither has an older picture to be caught against.
///
/// So each room is drawn twice through the software rasteriser — once with its
/// effect on and once off — and what is asserted is that the two differ. That
/// is a claim about the *fixture*; `flutter3d_cpu/test/reflections_test.dart`
/// and `ssao_test.dart` are where the arithmetic behind each effect is pinned.
///
/// The camera is the demo's own `OrbitController`, framed on the room and set
/// to the scene's yaw and pitch, so the frame drawn here is the frame the
/// recorder will see. The size is smaller: a rasteriser written in Dart is slow
/// and the question is whether the effect reaches pixels, not which ones.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_example/src/spike/golden_extras.dart';
import 'package:flutter3d_example/src/spike/golden_scenes.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 120;

/// Draws [room] as the demo would draw it for the scene named [sceneName].
Future<Uint8List> _draw(
  String sceneName,
  List<MeshNode> Function(GraphicsDevice) room, {
  required double ambient,
  required bool effectOn,
}) async {
  final scene = goldenSceneNamed(sceneName)!;
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );

  final world = Scene(name: sceneName)..ambientIntensity = ambient;
  for (final node in room(it.device)) {
    world.add(node);
  }
  // The sun is out in both rooms — see `_batchForGolden` — so the only light
  // here is the ambient the room is lit by.
  final camera = world.add(CameraNode(name: 'eye'));
  OrbitController(camera, yaw: scene.yaw, pitch: scene.pitch)
    ..frameBounds(world.computeBounds())
    ..yaw = scene.yaw
    ..pitch = scene.pitch
    ..apply()
    ..syncProjectionDepth(camera);

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: world,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      bloom: BloomSettings(enabled: scene.bloom),
      shadows: ShadowSettings(enabled: scene.shadows),
      reflections: effectOn
          ? scene.reflections
          : const ReflectionSettings(enabled: false),
      ambientOcclusion: effectOn
          ? scene.ambientOcclusion
          : const AmbientOcclusionSettings(enabled: false),
    ),
  );
  final pixels = await it.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

/// Pixels where [b] is brighter than [a] by more than a channel of noise, and
/// pixels where it is darker.
({int brighter, int darker}) _moved(Uint8List a, Uint8List b) {
  var brighter = 0, darker = 0;
  for (var i = 0; i < a.length; i += 4) {
    final delta = (b[i] + b[i + 1] + b[i + 2]) - (a[i] + a[i + 1] + a[i + 2]);
    if (delta > 8) brighter++;
    if (delta < -8) darker++;
  }
  return (brighter: brighter, darker: darker);
}

void main() {
  test('the mirror room puts something in its floor', () async {
    // Mutation: raise the floor's roughness in `GoldenExtras.mirrorRoom` past
    // the shader's polish cut-off of 0.18 — 0.5 will do. The march declines
    // every pixel of the floor, the count goes from 274 to **0**, and this goes
    // red. That is exactly the reference this scene would otherwise have
    // recorded: a floor under two glowing blocks, indistinguishable from a
    // correct one until somebody compared it to nothing.
    final off = await _draw(
      'screen-space-reflections',
      GoldenExtras.mirrorRoom,
      ambient: 0.25,
      effectOn: false,
    );
    final on = await _draw(
      'screen-space-reflections',
      GoldenExtras.mirrorRoom,
      ambient: 0.25,
      effectOn: true,
    );

    // 274 of 19200 at this size when it was written: the two blocks' mirror
    // images, running from their feet towards the camera.
    final moved = _moved(off, on);
    expect(
      moved.brighter,
      greaterThan(150),
      reason:
          'switching reflections on lit ${moved.brighter} pixels: there is '
          'nothing in this floor for the golden to be a picture of',
    );
    // Added light, never removed: the pass adds what the march found to the
    // scene. Darker pixels would mean it had rewritten something.
    expect(moved.darker, 0, reason: 'the reflection pass darkened the frame');
  });

  test('the occlusion corner has corners to darken', () async {
    // Mutation: take both walls out of `GoldenExtras.occlusionCorner` and stand
    // the box in the open. What is left is a box on a floor, which still
    // occludes a little at its own foot — 337 pixels against 951 — so the count
    // falls under the threshold below rather than to zero. A room with no
    // corner in it is what this is here to catch, and a box on a plain is one.
    final off = await _draw(
      'ambient-occlusion-corner',
      GoldenExtras.occlusionCorner,
      ambient: 0.9,
      effectOn: false,
    );
    final on = await _draw(
      'ambient-occlusion-corner',
      GoldenExtras.occlusionCorner,
      ambient: 0.9,
      effectOn: true,
    );

    // 951 of 19200 at this size when it was written: the line where the two
    // walls meet, the band where each meets the floor, and the crevices either
    // side of the box.
    final moved = _moved(off, on);
    expect(
      moved.darker,
      greaterThan(400),
      reason:
          'switching occlusion on darkened ${moved.darker} pixels: this room '
          'has no corner the pass can find',
    );
    // And not the whole frame: an occlusion that darkens everything is a
    // dimmer, and a golden of one says nothing about corners.
    expect(
      moved.darker,
      lessThan(_width * _height ~/ 2),
      reason: 'more than half the frame darkened: this is a dimming',
    );
    expect(
      moved.brighter,
      0,
      reason: 'the occlusion pass brightened the frame',
    );
  });
}
