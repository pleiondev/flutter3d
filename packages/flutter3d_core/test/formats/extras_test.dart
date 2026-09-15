/// `fmt-19`: `extras` on node/material/skin/clip/document, and
/// `TextureBinding.transform` from `KHR_texture_transform` — carried
/// through a decode → write → decode round trip, not applied to anything
/// that draws (the existing "not applied" warning stays exactly where it
/// was).
///
///     dart test test/extras_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

/// Deep JSON equality for two `extras` values — a decoder hands back a plain
/// `Map<String, Object?>` and a writer takes one, so round-tripping both
/// through `jsonEncode`/`jsonDecode` and comparing the result is "the same
/// JSON", which is what the row's own acceptance line asks for, rather than
/// "the same Dart object" or "the same Map insertion order".
void expectSameJson(Object? a, Object? b, {String? reason}) {
  expect(jsonDecode(jsonEncode(a)), jsonDecode(jsonEncode(b)), reason: reason);
}

SurfaceMaterial _withExtras(SurfaceMaterial m, Map<String, Object?> extras) =>
    SurfaceMaterial(
      name: m.name,
      baseColor: m.baseColor,
      metallic: m.metallic,
      roughness: m.roughness,
      baseColorTexture: m.baseColorTexture,
      metallicRoughnessTexture: m.metallicRoughnessTexture,
      normalTexture: m.normalTexture,
      normalScale: m.normalScale,
      occlusionTexture: m.occlusionTexture,
      occlusionStrength: m.occlusionStrength,
      emissiveTexture: m.emissiveTexture,
      emissive: m.emissive,
      emissiveStrength: m.emissiveStrength,
      alphaMode: m.alphaMode,
      alphaCutoff: m.alphaCutoff,
      doubleSided: m.doubleSided,
      unlit: m.unlit,
      extras: extras,
    );

ModelNode _nodeWithExtras(ModelNode n, Map<String, Object?> extras) =>
    ModelNode(
      name: n.name,
      translation: n.translation,
      rotation: n.rotation,
      scale: n.scale,
      children: n.children,
      surfaces: n.surfaces,
      extras: extras,
    );

/// A JSON value covering every shape `extras` can hold: a string, a number,
/// a bool, `null`, a nested object and a nested list — not just a flat
/// string-to-string map, which byte-for-byte equality could pass by luck if
/// the writer only ever handled the simplest case.
const Map<String, Object?> _sampleExtras = <String, Object?>{
  'a string': 'value',
  'a number': 1.5,
  'a bool': true,
  'a null': null,
  'nested': <String, Object?>{
    'list': <Object?>[1, 'two', false, null],
  },
};

void main() {
  group('extras on node, material and document', () {
    test('survive a decode, write, decode round trip byte for byte', () async {
      final source = await GltfLoader().load(_sample('BoxTextured.glb'));
      expect(source.nodes, isNotEmpty);
      expect(source.materials, isNotEmpty);

      final annotated = PlainModelDocument(
        surfaces: source.surfaces,
        materials: <SurfaceMaterial>[
          _withExtras(source.materials.first, _sampleExtras),
          ...source.materials.skip(1),
        ],
        images: source.images,
        nodes: <ModelNode>[
          _nodeWithExtras(source.nodes.first, _sampleExtras),
          ...source.nodes.skip(1),
        ],
        asset: DocumentAsset(
          generator: source.asset?.generator,
          extras: _sampleExtras,
        ),
      );

      final bytes = GltfWriter(annotated).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      // Mutation: drop any one of the three writer sites (node/material/
      // document) — the matching field below reads back null instead of
      // the JSON matching, which is what actually distinguishes "written"
      // from "silently dropped".
      expectSameJson(
        readBack.nodes.first.extras,
        _sampleExtras,
        reason: 'node extras',
      );
      expectSameJson(
        readBack.materials.first.extras,
        _sampleExtras,
        reason: 'material extras',
      );
      expectSameJson(
        readBack.asset?.extras,
        _sampleExtras,
        reason: 'document extras',
      );
    });

    test('a material or node with none of this round-trips to null, not an '
        'empty object', () async {
      final source = await GltfLoader().load(_sample('Box.glb'));
      expect(source.nodes.first.extras, isNull);

      final bytes = GltfWriter(source).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      // Mutation: always write `'extras': node.extras ?? const {}` — every
      // node in every file this writer touches would carry a needless empty
      // object forever after its first save.
      expect(readBack.nodes.first.extras, isNull);
    });
  });

  group('extras on a skin', () {
    test('survive the round trip', () async {
      final source = await GltfLoader().load(
        _sample('simple_skin/SimpleSkin.gltf'),
      );
      expect(source.skins, isNotEmpty);
      final skin = source.skins.first;

      final annotated = PlainModelDocument(
        surfaces: source.surfaces,
        materials: source.materials,
        images: source.images,
        nodes: source.nodes,
        skins: <ModelSkin>[
          ModelSkin(
            name: skin.name,
            joints: skin.joints,
            inverseBindMatrices: skin.inverseBindMatrices,
            skeletonRoot: skin.skeletonRoot,
            extras: _sampleExtras,
          ),
        ],
      );

      final bytes = GltfWriter(annotated).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      expect(readBack.skins, isNotEmpty);
      // Mutation: drop the skin's own `extras` line in the writer — this
      // reads back null instead of matching.
      expectSameJson(readBack.skins.first.extras, _sampleExtras);
    });
  });

  group('extras on an animation clip', () {
    test('survive the round trip', () async {
      final source = await GltfLoader().load(_sample('BoxAnimated.glb'));
      expect(source.animations, isNotEmpty);
      final clip = source.animations.first;

      final annotated = PlainModelDocument(
        surfaces: source.surfaces,
        materials: source.materials,
        images: source.images,
        nodes: source.nodes,
        animations: <AnimationClip>[
          AnimationClip(
            name: clip.name,
            tracks: clip.tracks,
            extras: _sampleExtras,
          ),
        ],
      );

      final bytes = GltfWriter(annotated).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      expect(readBack.animations, isNotEmpty);
      // Mutation: drop the clip's own `extras` line in the writer — this
      // reads back null instead of matching.
      expectSameJson(readBack.animations.first.extras, _sampleExtras);
    });
  });

  group('TextureBinding.transform from KHR_texture_transform', () {
    test('is carried through, and the "not applied" warning stays', () async {
      final source = await GltfLoader().load(_sample('BoxTextured.glb'));
      final material = source.materials.first;
      final texture = material.baseColorTexture!;

      final transformedTexture = TextureBinding(
        imageIndex: texture.imageIndex,
        texCoordSet: texture.texCoordSet,
        sampling: texture.sampling,
        transform: TextureTransform(
          offset: Vector2(0.25, 0.5),
          scale: Vector2(2.0, 3.0),
          rotation: 0.7853981633974483, // pi/4
        ),
      );
      final withTransform = SurfaceMaterial(
        name: material.name,
        baseColor: material.baseColor,
        metallic: material.metallic,
        roughness: material.roughness,
        baseColorTexture: transformedTexture,
        metallicRoughnessTexture: material.metallicRoughnessTexture,
        normalTexture: material.normalTexture,
        normalScale: material.normalScale,
        occlusionTexture: material.occlusionTexture,
        occlusionStrength: material.occlusionStrength,
        emissiveTexture: material.emissiveTexture,
        emissive: material.emissive,
        emissiveStrength: material.emissiveStrength,
        alphaMode: material.alphaMode,
        alphaCutoff: material.alphaCutoff,
        doubleSided: material.doubleSided,
        unlit: material.unlit,
      );

      final annotated = PlainModelDocument(
        surfaces: source.surfaces,
        materials: <SurfaceMaterial>[
          withTransform,
          ...source.materials.skip(1),
        ],
        images: source.images,
        nodes: source.nodes,
      );

      final bytes = GltfWriter(annotated).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      final readTransform =
          readBack.materials.first.baseColorTexture!.transform;
      expect(readTransform, isNotNull);
      // Mutation: read `offset`/`scale` swapped, or drop `rotation` — any of
      // these three numbers wrong is exactly what this line catches.
      expect(readTransform!.offset.x, closeTo(0.25, 1e-6));
      expect(readTransform.offset.y, closeTo(0.5, 1e-6));
      expect(readTransform.scale.x, closeTo(2.0, 1e-6));
      expect(readTransform.scale.y, closeTo(3.0, 1e-6));
      expect(readTransform.rotation, closeTo(0.7853981633974483, 1e-9));

      // The row's own second acceptance line: the warning stays, because
      // nothing anywhere samples through this transform yet.
      //
      // Mutation: delete the warning now that the data is carried — reads
      // as "fixed" until a renderer actually applies it, which is not this
      // row.
      expect(
        readBack.warnings.any(
          (w) =>
              w.contains('KHR_texture_transform') &&
              w.contains('no offset, scale or rotation is applied'),
        ),
        isTrue,
        reason: readBack.warnings.join('\n'),
      );
    });

    test('a texture with none of this reads back with a null transform, '
        'and the file gains no unasked-for extension', () async {
      final source = await GltfLoader().load(_sample('BoxTextured.glb'));
      final texture = source.materials.first.baseColorTexture!;
      expect(texture.transform, isNull);

      final bytes = GltfWriter(source).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      // Mutation: always write the `KHR_texture_transform` extension with
      // the identity values — this reads back non-null instead of null, and
      // the file would carry `extensionsUsed: ["KHR_texture_transform"]`
      // for every texture, not only the ones that asked for it.
      expect(readBack.materials.first.baseColorTexture!.transform, isNull);
    });
  });
}
