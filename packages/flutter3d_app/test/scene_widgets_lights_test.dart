/// `Light3D.sun()` and `Light3D.lamp()`: lights named for what they are,
/// in lux and candela a default camera shows well.
///
///     flutter test test/scene_widgets_lights_test.dart
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

LightNode _light(Scene scene) =>
    scene.root.children.whereType<LightNode>().single;

void main() {
  late SceneWidgetsMount mount;
  late Scene scene;

  setUp(() {
    final device = CpuDevice(
      width: 8,
      height: 8,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    scene = Scene();
    mount = SceneWidgets.mount(
      scene: scene,
      renderer: Renderer.create(device: device),
      device: device,
    );
    addTearDown(mount.dispose);
  });

  test('the sun is a warm directional light of 15 000 lux that casts, '
      'shining down', () {
    // Mutation: default `Light3D.sun`'s intensity to the pre-1.0 unit, and
    // the sun is a third as bright as the number it documents.
    mount.update(const <Widget>[Light3D.sun()]);
    final sun = _light(scene);
    expect(sun.type, LightType.directional);
    expect(sun.intensity, 15000.0);
    expect(sun.intensity, Light3D.sunIlluminance);
    expect(sun.castsShadow, isTrue);
    expect(sun.color.r, 1.0);
    expect(sun.color.b, lessThan(sun.color.r));
    // Down, not along the node's resting −Z: a sun given no direction must
    // not light the scene from the horizon.
    final forward = sun.readDirection();
    expect(forward.y, lessThan(-0.8));
  });

  test('a lamp is an 800-lumen bulb in candela, warm white', () {
    mount.update(<Widget>[Light3D.lamp(position: Vector3(0.0, 2.0, 0.0))]);
    final lamp = _light(scene);
    expect(lamp.type, LightType.point);
    expect(lamp.intensity, closeTo(800.0 / (4.0 * math.pi), 1e-9));
    expect(
      Photometric.toLumens(lamp.intensity, type: LightType.point),
      closeTo(800.0, 1e-9),
    );
    expect(lamp.color.b, lessThan(lamp.color.g));
    expect(lamp.worldMatrix.getTranslation(), Vector3(0.0, 2.0, 0.0));
  });

  test('the plain constructors default to the same photometric numbers', () {
    mount.update(<Widget>[
      Light3D.point(position: Vector3.zero()),
      const Light3D(),
    ]);
    final lights = scene.root.children.whereType<LightNode>().toList();
    expect(lights.first.intensity, Light3D.lampIntensity);
    expect(lights.last.intensity, Light3D.sunIlluminance);
  });

  test('a sun told its direction shines that way', () {
    mount.update(<Widget>[Light3D.sun(direction: Vector3(0.0, 0.0, -1.0))]);
    expect(_light(scene).readDirection().z, closeTo(-1.0, 1e-6));
  });
}
