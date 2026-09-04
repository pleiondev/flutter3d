/// `bindMaterial`: the half of the standalone-material path that touches a
/// device.
///
///     flutter test test/material_bind_test.dart
///
/// **The half that had nothing.** `material_loader_test.dart` covers
/// `loadMaterialDocument`, which is pure — bytes in, a document out. What it
/// leaves is everything after: resolving the document's image paths, uploading
/// them, and carrying the two things a standalone material exists for into the
/// `Material` the renderer draws with — the application's own parameters and
/// the textures its own shader samples. `bindMaterial` and `loadMaterial` are
/// exported from `flutter3d.dart` and were called by nothing in this
/// repository, so an author reading the API was the first person to run them.
///
/// KTX2 images rather than PNGs, for the reason `texture_upload_test.dart`
/// gives: that path never reaches `ui.instantiateImageCodec`, so this runs with
/// no live binding and no sample files.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';
import 'package:flutter3d/src/engine/assets/material_loader.dart';
import 'package:flutter3d/src/engine/assets/surface_material.dart';
import 'package:flutter3d/src/engine/render/lighting_model.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/build_ktx2.dart';

/// A material naming a shader of the application's own, with one parameter and
/// two textures that shader samples by slot name.
MaterialDocument _document() => MaterialDocument(
  surface: SurfaceMaterial(name: 'water'),
  images: const <String>['ramp.ktx2', 'flow.ktx2'],
  lighting: const LightingModel(
    'Water',
    'Water',
    usesFragInfo: false,
    usesAlbedoTexture: false,
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  ),
  parameterBlock: 'WaterParams',
  parameters: <String, Float32List>{
    'wave': Float32List.fromList(<double>[0.25, 1.5, 0.0, 0.0]),
  },
  extraTextures: const <String, TextureBinding>{
    'ramp_texture': TextureBinding(imageIndex: 0),
    'flow_texture': TextureBinding(imageIndex: 1),
  },
);

void main() {
  test(
    'an application\'s own textures and parameters reach the material',
    () async {
      // **The seam, end to end on the reading side.** Nothing about `ramp_texture`
      // or `WaterParams` is known to this engine: the document names them, this
      // function carries them across, and the encoder binds them by those names.
      //
      // Mutation: drop the `extraTextures: extra` argument from the `Material`
      // that `bindMaterial` returns — the two slots come back empty and this
      // fails. Drop `parameters: document.parameters` and the second group does.
      final device = FakeBackend();
      final material = await bindMaterial(
        _document(),
        device: device,
        resolveUri: (uri) async => buildKtx2(vkFormat: VkFormat.bc7UNormBlock),
      );

      expect(material.extraTextures.keys, <String>[
        'ramp_texture',
        'flow_texture',
      ]);
      expect(material.extraTextures['ramp_texture'], isNotNull);
      expect(material.parameterBlock, 'WaterParams');
      expect(material.parameters['wave']!.first, 0.25);
      expect(
        material.lighting.shaderName,
        'Water',
        reason: 'a file that names a shader wins over the scene\'s model',
      );
    },
  );

  test('an image it cannot read costs the slot and not the material', () async {
    // The rule stated on `bindMaterial`: a missing map should cost a map, not
    // the level. The slot is absent rather than bound to nothing, which matters
    // more here than for the built-in maps — those get a neutral texture, and
    // for an application's own shader there is no such thing as neutral.
    //
    // Mutation: put the handle in the map regardless of whether it resolved
    // (drop the `if (handle != null)`) — the encoder then binds a null and this
    // fails on the key being there.
    final device = FakeBackend();
    final warnings = <String>[];
    final material = await bindMaterial(
      _document(),
      device: device,
      resolveUri: (uri) async =>
          uri == 'ramp.ktx2' ? throw StateError('not there') : buildKtx2(),
      warnings: warnings,
    );

    expect(material.extraTextures.keys, <String>['flow_texture']);
    expect(warnings.single, contains('ramp.ktx2'));
  });
}
