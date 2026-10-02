/// The `material-language` golden's lighting model is the program's own
/// answer — `P8`.
///
///     flutter test test/material_language_test.dart
///
/// A golden scene is a constant, so `GoldenExtras.rimGlow` is written out by
/// hand. This holds it to what `BundledMaterials` builds from the source the
/// bundle carries, flag by flag, so a change to `shaders/rim_glow.f3dmat`
/// that samples a map or reads the metalness cannot leave the scene binding
/// what the stage no longer declares.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_example/src/spike/golden_extras.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the golden binds what the source reads', () {
    final program = parseMaterial(
      File('shaders/rim_glow.f3dmat').readAsStringSync(),
    );
    final built = describeMaterial(
      program,
    ).lightingModel(label: program.name, shaderName: program.name);
    const written = GoldenExtras.rimGlow;

    expect(written.shaderName, built.shaderName);
    expect(written.vertexShaderName, built.vertexShaderName);
    expect(written.usesFragInfo, built.usesFragInfo);
    expect(written.usesFogInfo, built.usesFogInfo);
    expect(written.usesAlbedoTexture, built.usesAlbedoTexture);
    expect(written.usesMaterialMaps, built.usesMaterialMaps);
    expect(written.usesMetallicRoughnessMap, built.usesMetallicRoughnessMap);
    expect(written.usesMetallic, built.usesMetallic);
    expect(written.usesLightList, built.usesLightList);
    expect(written.usesMaterialParameters, built.usesMaterialParameters);
    expect(written.usesEnvironment, built.usesEnvironment);
    expect(written.vertexStageMorphs, built.vertexStageMorphs);
  });
}
