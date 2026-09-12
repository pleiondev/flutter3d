/// `mat-15`'s own disposal rule: switching presets gives the old environment
/// handle back rather than leaking it.
///
///     flutter test test/material_studio_environment_test.dart
library;

import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/ui/material_studio_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the first preset binds a fresh environment', () {
    final device = FakeBackend();
    final scene = Scene();
    final environment = MaterialStudioEnvironment(device: device, scene: scene);

    final presets = materialStudioSkyPresets();
    environment.apply(presets[0].sky);

    expect(environment.current, isNotNull);
    expect(scene.environment, same(environment.current));
    expect(scene.environmentLevels, greaterThan(0));
    expect(scene.ambientIntensity, 1.0);
    expect(device.releasedTextures, isEmpty);
  });

  test('a later preset releases the one it replaces', () {
    final device = FakeBackend();
    final scene = Scene();
    final environment = MaterialStudioEnvironment(device: device, scene: scene);

    final presets = materialStudioSkyPresets();
    environment.apply(presets[0].sky);
    final first = environment.current;

    environment.apply(presets[1].sky);
    final second = environment.current;

    expect(second, isNotNull);
    expect(second, isNot(same(first)));
    expect(device.releasedTextures, <TextureHandle?>[first]);
  });

  test('closing the studio releases whatever preset is bound', () {
    final device = FakeBackend();
    final scene = Scene();
    final environment = MaterialStudioEnvironment(device: device, scene: scene);

    environment.apply(materialStudioSkyPresets()[2].sky);
    final bound = environment.current;
    environment.dispose();

    expect(device.releasedTextures, <TextureHandle?>[bound]);
    expect(environment.current, isNull);
  });

  test('every preset is enabled and named once', () {
    final presets = materialStudioSkyPresets();
    expect(presets, hasLength(3));
    expect(presets.map((p) => p.sky.enabled), everyElement(isTrue));
    expect(presets.map((p) => p.name).toSet(), hasLength(3));
  });
}
