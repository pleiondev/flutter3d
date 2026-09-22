/// `surfaceMaterialToJson`/`surfaceMaterialFromJson`: `doc-25`'s own
/// remaining half, once `mat-01` absorbed the rest — the public codec for a
/// [SurfaceMaterial]'s own scalar and colour fields that `writeFmat` and
/// `readFmat` are built on rather than duplicating.
///
///     dart test test/surface_material_json_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a default material writes only baseColor — everything else is '
      'already the reader\'s own default', () {
    expect(surfaceMaterialToJson(SurfaceMaterial()).keys, <String>[
      'baseColor',
    ]);
  });

  test('an empty json reads back every field at the same default '
      'SurfaceMaterial\'s own constructor gives it', () {
    final surface = surfaceMaterialFromJson(const <String, Object?>{});
    final defaults = SurfaceMaterial();

    expect(surface.metallic, defaults.metallic);
    expect(surface.roughness, defaults.roughness);
    expect(surface.normalScale, defaults.normalScale);
    expect(surface.occlusionStrength, defaults.occlusionStrength);
    expect(surface.emissiveStrength, defaults.emissiveStrength);
    expect(surface.alphaMode, defaults.alphaMode);
    expect(surface.alphaCutoff, defaults.alphaCutoff);
    expect(surface.doubleSided, defaults.doubleSided);
    expect(surface.unlit, defaults.unlit);
  });

  test('every field that differs from the default is written, and reads '
      'back the exact value', () {
    final surface = SurfaceMaterial(
      name: 'brick',
      baseColor: Vector4(0.6, 0.3, 0.2, 1.0),
      metallic: 0.4,
      roughness: 0.8,
      normalScale: 1.5,
      occlusionStrength: 0.9,
      emissive: Vector3(0.1, 0.2, 0.3),
      emissiveStrength: 2.0,
      alphaMode: SurfaceAlphaMode.blend,
      alphaCutoff: 0.3,
      doubleSided: true,
      unlit: true,
    );

    final json = surfaceMaterialToJson(surface);
    final back = surfaceMaterialFromJson(json);

    expect(back.name, 'brick');
    expect(back.baseColor, Vector4(0.6, 0.3, 0.2, 1.0));
    expect(back.metallic, 0.4);
    expect(back.roughness, 0.8);
    expect(back.normalScale, 1.5);
    expect(back.occlusionStrength, 0.9);
    expect(back.emissive, Vector3(0.1, 0.2, 0.3));
    expect(back.emissiveStrength, 2.0);
    expect(back.alphaMode, SurfaceAlphaMode.blend);
    expect(back.alphaCutoff, 0.3);
    expect(back.doubleSided, isTrue);
    expect(back.unlit, isTrue);
  });

  test('the name fallback is read only when the json itself says nothing', () {
    expect(
      surfaceMaterialFromJson(const <String, Object?>{}, name: 'fallback').name,
      'fallback',
    );
    expect(
      surfaceMaterialFromJson(const <String, Object?>{
        'name': 'from the file',
      }, name: 'fallback').name,
      'from the file',
    );
  });

  test('an alpha mode this build has never heard of warns and reads as '
      'opaque', () {
    final warnings = <String>[];
    final surface = surfaceMaterialFromJson(const <String, Object?>{
      'alphaMode': 'wobbly',
    }, warnings: warnings);

    expect(surface.alphaMode, SurfaceAlphaMode.opaque);
    expect(warnings.single, contains('wobbly'));
  });

  test('texture bindings are never read from json — the caller\'s own '
      'resolved bindings pass straight through', () {
    const albedo = TextureBinding(imageIndex: 3);
    final surface = surfaceMaterialFromJson(const <String, Object?>{
      // Even a json shaped like a texture slot under one of these keys
      // must not be mistaken for a binding: resolving one needs a whole
      // document's own image list, which this function is never given.
      'baseColorTexture': 'brick.png',
    }, baseColorTexture: albedo);

    expect(surface.baseColorTexture, same(albedo));
    expect(surface.normalTexture, isNull);
  });
}
