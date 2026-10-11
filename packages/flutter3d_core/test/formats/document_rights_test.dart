/// Who made a model and on what terms: glTF's `asset.copyright`, and the
/// author and licence of its `KHR_xmp_json_ld` packet, read into
/// [DocumentAsset] and written back.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Future<GltfAsset> _chair() => GltfLoader().load(
  File('test/formats/fixtures/rights/chair.gltf').readAsBytesSync(),
);

void main() {
  test('a glTF says its copyright, its author and its licence', () async {
    final asset = (await _chair()).asset!;
    expect(asset.copyright, '© 2026 Ada Modeller');
    expect(asset.author, 'Ada Modeller');
    expect(asset.license, 'CC-BY-4.0');
    expect(asset.generator, 'flutter3d test');
  });

  test('the three survive a write and a read', () async {
    final source = await _chair();
    final back = await GltfLoader().load(GltfWriter(source).writeGlb());
    expect(back.asset!.copyright, '© 2026 Ada Modeller');
    expect(back.asset!.author, 'Ada Modeller');
    expect(back.asset!.license, 'CC-BY-4.0');
  });

  test('an XMP key nothing here reads survives a write and a read', () async {
    final source = await _chair();
    expect(source.asset!.xmp!['xmp:CreatorTool'], 'Blender 4.2');
    final back = await GltfLoader().load(GltfWriter(source).writeGlb());
    final xmp = back.asset!.xmp!;
    // Mutation: write only the keys this package reads, and these two go.
    expect(xmp['xmp:CreatorTool'], 'Blender 4.2');
    expect(xmp['dc:title'], <String, Object?>{
      '@language': 'en',
      '@value': 'Chair',
    });
    expect((xmp['@context']! as Map)['xmp'], 'http://ns.adobe.com/xap/1.0/');
  });

  test('fields set by hand are written as a packet of their own', () async {
    final source = await _chair();
    final document = PlainModelDocument(
      surfaces: source.surfaces,
      materials: source.materials,
      images: source.images,
      asset: const DocumentAsset(
        author: 'Grace Sculptor',
        license: 'CC0-1.0',
        copyright: '© 2026 Grace Sculptor',
      ),
    );
    final back = await GltfLoader().load(GltfWriter(document).writeGlb());
    expect(back.asset!.author, 'Grace Sculptor');
    expect(back.asset!.license, 'CC0-1.0');
    expect(back.asset!.copyright, '© 2026 Grace Sculptor');
  });

  test('a changed author replaces the packet\'s, and keeps the rest', () async {
    final source = await _chair();
    final document = PlainModelDocument(
      surfaces: source.surfaces,
      materials: source.materials,
      images: source.images,
      asset: source.asset!.copyWith(author: 'Grace Sculptor'),
    );
    final back = await GltfLoader().load(GltfWriter(document).writeGlb());
    expect(back.asset!.author, 'Grace Sculptor');
    expect(back.asset!.license, 'CC-BY-4.0');
    expect(back.asset!.xmp!['xmp:CreatorTool'], 'Blender 4.2');
  });

  test('a file that says nothing has none of them', () async {
    final source = await _chair();
    final plain = PlainModelDocument(
      surfaces: source.surfaces,
      materials: source.materials,
      images: source.images,
    );
    final back = await GltfLoader().load(GltfWriter(plain).writeGlb());
    expect(back.asset?.author, isNull);
    expect(back.asset?.license, isNull);
    expect(back.asset?.copyright, isNull);
  });

  test('two assets differing in a right are not equal', () {
    const a = DocumentAsset(license: 'CC0-1.0');
    expect(a == const DocumentAsset(license: 'CC0-1.0'), isTrue);
    expect(a == const DocumentAsset(license: 'CC-BY-4.0'), isFalse);
    expect(a == const DocumentAsset(author: 'x', license: 'CC0-1.0'), isFalse);
  });
}
