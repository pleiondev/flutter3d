/// A project's lights are lux and candela since version 2 of `.f3dproj`,
/// as a `LightNode`'s are; a version 1 file held the engine's pre-1.0 unit
/// and is lifted as it is read.
///
///     dart test test/project_lights_in_lux_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show LightNode, Scene;
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

ModelProject _opened(Uint8List bytes) => switch (readProject(bytes)) {
  ProjectOpened(:final project) => project,
  final ProjectRefused refused => fail(refused.because),
};

ModelProject _withLight(double intensity) => ModelProject(
  lighting: SceneLighting(
    lights: <ProjectLight>[
      ProjectLight(type: LightType.point, intensity: intensity),
    ],
  ),
);

void main() {
  test('a project is written at version 2', () {
    final bytes = writeProject(_withLight(800.0));
    expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 2);
    expect(projectVersion, 2);
  });

  test('a light keeps its candela through a save', () {
    // Mutation: multiply by the old unit on the way in whatever the file's
    // version, and 800 cd opens as 4.6 million.
    final read = _opened(writeProject(_withLight(800.0)));
    expect(read.lighting.lights.single.intensity, 800.0);
  });

  test("a version 1 file's lights are lifted from the old unit", () {
    // The same bytes with the header saying version 1: the number in it is
    // the pre-1.0 unit, one of which is the default light. Mutation: read
    // it as it is, and every light of an old project is 5 790 times too dim.
    final bytes = writeProject(_withLight(2.5));
    ByteData.sublistView(bytes).setUint32(4, 1, Endian.little);
    final read = _opened(bytes);
    expect(
      read.lighting.lights.single.intensity,
      2.5 * LightNode.defaultIntensity,
    );
  });

  test('a new light is the default light, in its own unit', () {
    expect(ProjectLight().intensity, LightNode.defaultIntensity);
  });

  test('the sync hands the scene the number the project holds', () {
    final scene = Scene();
    LightingSync().sync(scene, _withLight(800.0).lighting);
    expect(scene.lights.single.intensity, 800.0);
  });
}
