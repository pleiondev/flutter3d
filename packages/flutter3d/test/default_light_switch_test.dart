/// `Scene.defaultLightWhenUnlit`: the switch for the light nobody added.
///
///     flutter test test/default_light_switch_test.dart
///
/// A scene with nothing lighting it is lit by one directional light anyway, so
/// that a first scene does not read as a broken renderer. That default is a
/// guess about intent, and until this switch existed there was no way to say
/// it had guessed wrong: turning the only lamp off — hiding it, or dialling it
/// to zero — dropped the live count to nothing and therefore turned a *bright*
/// light on, which is the opposite of what was asked. The workaround was to
/// park a black light in the scene to keep the count above zero.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The light buffer a real frame ended up with, drawn through the fake device
/// so the question is answered by the renderer rather than by re-deriving what
/// the renderer would have done.
LightBuffer _framedLights(Scene scene) {
  final renderer = Renderer.create(device: FakeBackend());
  renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
  );
  return renderer.lights;
}

Scene _scene() => Scene()..add(CameraNode()..setPosition(0.0, 0.0, 4.0));

void main() {
  test('an empty scene is still lit, because that is the useful default', () {
    expect(_framedLights(_scene()).count, 1);
  });

  test('and the switch is what turns that off', () {
    final scene = _scene()..defaultLightWhenUnlit = false;
    expect(_framedLights(scene).count, 0);
  });

  test('a scene whose only light is hidden counts as unlit', () {
    // The case that made the switch necessary: this scene has a light node in
    // it, so "there are no lights" is not what its author would say — but the
    // buffer is filled from live lights, and a hidden one is not live.
    final scene = _scene()..add(LightNode()..visible = false);
    expect(_framedLights(scene).count, 1, reason: 'the default light, still');

    scene.defaultLightWhenUnlit = false;
    expect(_framedLights(scene).count, 0, reason: 'off is off');
  });

  test('a scene at zero intensity counts as unlit too', () {
    final scene = _scene()
      ..defaultLightWhenUnlit = false
      ..add(LightNode(intensity: 0.0));
    expect(_framedLights(scene).count, 0);
  });

  test('a live light is untouched by the switch either way', () {
    for (final unlitDefault in <bool>[true, false]) {
      final scene = _scene()
        ..defaultLightWhenUnlit = unlitDefault
        ..add(LightNode(intensity: 2.0));
      expect(_framedLights(scene).count, 1);
    }
  });
}
