/// `gltfSiblingUris`/`embedGltfSiblings` — `ui-36n`'s own row: a `.gltf`
/// with an external `.bin` and textures, rewritten into one self-contained
/// file before it ever reaches a decoder.
///
///     flutter test test/gltf_siblings_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_modeler/src/files/gltf_siblings.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _gltf(Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, Object?> _decode(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

void main() {
  group('gltfSiblingUris', () {
    test('names a relative buffer and image uri, decoded', () {
      final gltf = _gltf(<String, Object?>{
        'buffers': <Object?>[
          <String, Object?>{'uri': 'scene%20data.bin', 'byteLength': 4},
        ],
        'images': <Object?>[
          <String, Object?>{'uri': 'textures/base.png'},
        ],
      });
      expect(gltfSiblingUris(gltf), <String>{
        'scene data.bin',
        'textures/base.png',
      });
    });

    test('a data: URI names nothing to go and find', () {
      final gltf = _gltf(<String, Object?>{
        'buffers': <Object?>[
          <String, Object?>{'uri': 'data:application/octet-stream;base64,AA=='},
        ],
      });
      expect(gltfSiblingUris(gltf), isEmpty);
    });

    test(
      'a buffer with no uri at all — the GLB binary chunk case — names nothing',
      () {
        final gltf = _gltf(<String, Object?>{
          'buffers': <Object?>[
            <String, Object?>{'byteLength': 4},
          ],
        });
        expect(gltfSiblingUris(gltf), isEmpty);
      },
    );

    test(
      'a .glb or other non-JSON bytes name nothing rather than throwing',
      () {
        expect(
          gltfSiblingUris(Uint8List.fromList(<int>[0x67, 0x6c, 0x54, 0x46])),
          isEmpty,
        );
      },
    );

    test('no buffers or images at all names nothing', () {
      expect(
        gltfSiblingUris(_gltf(<String, Object?>{'asset': <String, Object?>{}})),
        isEmpty,
      );
    });
  });

  group('embedGltfSiblings', () {
    test('rewrites a matched buffer uri to a data: URI carrying its bytes', () {
      final gltf = _gltf(<String, Object?>{
        'buffers': <Object?>[
          <String, Object?>{'uri': 'scene.bin', 'byteLength': 4},
        ],
      });
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final rewritten = embedGltfSiblings(gltf, <String, Uint8List>{
        'scene.bin': bytes,
      });
      final json = _decode(rewritten);
      final uri = (json['buffers']! as List).single as Map;
      expect(uri['uri'], startsWith('data:application/octet-stream;base64,'));
      // Mutation: swap `base64Encode` for a plain string, and this comes
      // back as anything but the four bytes handed in.
      final payload = (uri['uri'] as String).split(',').last;
      expect(base64Decode(payload), orderedEquals(bytes));
    });

    test('matches by the uri\'s own last path segment', () {
      final gltf = _gltf(<String, Object?>{
        'images': <Object?>[
          <String, Object?>{'uri': 'textures/base.png'},
        ],
      });
      final bytes = Uint8List.fromList(<int>[9, 9]);

      final rewritten = embedGltfSiblings(gltf, <String, Uint8List>{
        'base.png': bytes,
      });
      final json = _decode(rewritten);
      final entry = (json['images']! as List).single as Map;
      expect(entry['uri'], contains('data:'));
    });

    test('a uri with no matching sibling is left exactly as it was', () {
      final gltf = _gltf(<String, Object?>{
        'buffers': <Object?>[
          <String, Object?>{'uri': 'missing.bin', 'byteLength': 4},
        ],
      });
      final rewritten = embedGltfSiblings(gltf, <String, Uint8List>{
        'unrelated.bin': Uint8List(0),
      });
      final json = _decode(rewritten);
      expect((json['buffers']! as List).single, <String, Object?>{
        'uri': 'missing.bin',
        'byteLength': 4,
      });
    });

    test('an already-embedded data: URI is left alone even if a sibling '
        'would otherwise match it', () {
      const dataUri = 'data:application/octet-stream;base64,AA==';
      final gltf = _gltf(<String, Object?>{
        'buffers': <Object?>[
          <String, Object?>{'uri': dataUri},
        ],
      });
      // Mutation: drop the `uri.startsWith('data:')` half of the guard, and
      // this sibling — named for the data URI's own last "path" segment,
      // the same lookup a real sibling goes through — replaces an already
      // self-contained buffer with a second, different one.
      final key = Uri.decodeComponent(dataUri).split('/').last;
      final rewritten = embedGltfSiblings(gltf, <String, Uint8List>{
        key: Uint8List.fromList(<int>[9, 9, 9]),
      });
      expect(rewritten, same(gltf));
    });

    test('no siblings at all returns the same bytes, not a copy', () {
      final gltf = _gltf(<String, Object?>{
        'buffers': <Object?>[
          <String, Object?>{'uri': 'scene.bin', 'byteLength': 4},
        ],
      });
      expect(embedGltfSiblings(gltf, const <String, Uint8List>{}), same(gltf));
    });

    test('non-JSON bytes come back unchanged rather than throwing', () {
      final bytes = Uint8List.fromList(<int>[0x67, 0x6c, 0x54, 0x46]);
      expect(
        embedGltfSiblings(bytes, <String, Uint8List>{'a': Uint8List(0)}),
        same(bytes),
      );
    });
  });

  group('a real sample', () {
    test('Cube.gltf, with its own external Cube.bin embedded, decodes with no '
        'resolver at all — the row\'s own "opens ... and gives the same '
        'document as .glb of the same mesh"', () async {
      final gltfBytes = File(
        '../../packages/flutter3d_samples/assets/cube/Cube.gltf',
      ).readAsBytesSync();
      final binBytes = File(
        '../../packages/flutter3d_samples/assets/cube/Cube.bin',
      ).readAsBytesSync();

      // The real file also names a base-colour texture this fixture does
      // not carry — the sample was never shipped with one. Embedding only
      // the geometry buffer and leaving the texture unresolved is the
      // honest case a person handing over an incomplete folder produces,
      // and this is what proves it degrades rather than refuses.
      final needed = gltfSiblingUris(gltfBytes);
      expect(needed, containsAll(<String>['Cube.bin']));

      final embedded = embedGltfSiblings(gltfBytes, <String, Uint8List>{
        'Cube.bin': binBytes,
      });
      // The buffer is gone from what is still missing; the texture, never
      // supplied, is still there for the decoder's own warning to name.
      expect(gltfSiblingUris(embedded), <String>{'Cube_BaseColor.png'});

      // No `resolveUri` passed — if the geometry still needed one, this
      // would throw rather than silently decode something smaller than
      // the real mesh; only the texture is left to warn about.
      final asset = await GltfLoader().load(embedded);
      expect(asset.surfaces, isNotEmpty);
      expect(asset.surfaces.first.mesh.vertexCount, greaterThan(0));
    });
  });
}
