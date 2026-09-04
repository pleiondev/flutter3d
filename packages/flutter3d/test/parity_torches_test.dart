/// The torch fixture has more casters than the atlas has rows.
///
///     flutter test test/parity_torches_test.dart
///
/// `ParityScene.torchesRunningOut` exists to compare two backends on a frame
/// where the cube atlas cannot hold every caster, so that they have to agree
/// about *which* lights go without. It was built against four rows and six
/// torches; `Renderer.kShadowedLights` then became six, every torch got a row,
/// and the fixture went on being called "running out" while nothing ran out.
/// Nothing failed, because the only thing checking it is a recorded grid, and a
/// grid of a full atlas is a perfectly good grid.
///
/// Two claims are worth holding here rather than in a picture, because both are
/// about the fixture's arithmetic and neither needs a GPU:
///
///   * the frame turns somebody away, and says so;
///   * *who* it turns away is not the tail of the list. The rows go to whichever
///     lights look largest from the camera, and if that order happened to match
///     the order the lights were added in, the fixture would pass with the
///     ranking replaced by a constant — which is the state its predecessor was
///     found in.
///
/// The second is computed from the fixture's own geometry rather than read out
/// of the renderer, deliberately: what is being pinned is where the torches
/// stand, and a test that asked the allocator would agree with it about a
/// fixture that had stopped posing the question.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

({Renderer renderer, FakeBackend device}) _engine() {
  final device = FakeBackend();
  final texel = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  )!;
  return (
    renderer: Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    ),
    device: device,
  );
}

void main() {
  test('two torches ask for a row and do not get one', () {
    // Mutation: put the torch count back to six in `buildParityScene`. Every
    // caster fits, `shadowsDenied` reports 0, and this goes red — which is
    // exactly the state the fixture spent its last release in, with nothing
    // saying so.
    final engine = _engine();
    final built = buildParityScene(
      engine.device,
      which: ParityScene.torchesRunningOut,
    );
    final frame = engine.renderer.render(
      width: 320,
      height: 240,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: paritySettingsFor(ParityScene.torchesRunningOut),
    );

    final casters = built.scene.lights.where((l) => l.castsShadow).length;
    expect(
      casters,
      greaterThan(Renderer.kShadowedLights),
      reason:
          'the fixture asks for $casters rows and the atlas has '
          '${Renderer.kShadowedLights}: nothing here is contended',
    );
    expect(
      frame.shadowsDenied,
      casters - Renderer.kShadowedLights,
      reason: 'the frame did not report the casters it turned away',
    );
  });

  test('relevance and scene order pick different torches', () {
    // Mutation: replace `_torchStandoffs` with the formula it came from —
    // positions walking away from the camera down the room, `z = 1 + i` — so
    // that the first six torches written down are also the six nearest. The
    // two sets below become equal and this goes red. That formula is what the
    // fixture used to have, and with six rows for six torches it made the
    // ranking unobservable.
    final engine = _engine();
    final built = buildParityScene(
      engine.device,
      which: ParityScene.torchesRunningOut,
    );

    final eye = built.camera.readWorldPosition(Vector3.zero());
    final casters = built.scene.lights
        .where((light) => light.castsShadow)
        .toList(growable: false);

    // The renderer's own rule, restated: how large the lit sphere looks from
    // the camera. Every torch here carries the same range, so this is nearest
    // first — see `Renderer._collectShadowCandidates`.
    double priority(LightNode light) {
      final at = light.readWorldPosition(Vector3.zero());
      return light.range / (at - eye).length;
    }

    final byRelevance = casters.toList()
      ..sort((a, b) => priority(b).compareTo(priority(a)));

    final kept = byRelevance
        .take(Renderer.kShadowedLights)
        .map((light) => light.name)
        .toSet();
    final firstWritten = casters
        .take(Renderer.kShadowedLights)
        .map((light) => light.name)
        .toSet();

    expect(
      kept,
      isNot(equals(firstWritten)),
      reason:
          'the six most relevant torches are the six written down first, so '
          'this fixture cannot tell an allocator that ranks from one that '
          'takes the first six it is handed',
    );
  });
}
