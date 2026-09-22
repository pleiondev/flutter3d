/// `fmt-15`: a primitive compressed with `KHR_draco_mesh_compression` or
/// `EXT_meshopt_compression`, whose fallback `POSITION` accessor has no
/// `bufferView` of its own — the shape an exporter leaves when the real data
/// lives in the compression extension's own buffer and no fallback was
/// written at all.
///
///     dart test test/compressed_primitive_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

final class _BytesSource extends AssetSource {
  const _BytesSource(this.bytes);

  final Uint8List bytes;

  @override
  String get key => 'memory:fixture';

  @override
  Future<Uint8List> read() async => bytes;

  @override
  AssetUriResolver get resolveUri =>
      (request) async => throw StateError('nothing to resolve');
}

/// A handwritten glTF: one mesh, one primitive, `extensionName` named on it,
/// and a `POSITION` accessor with [bufferView] set or left out — the two
/// shapes this row's own acceptance line distinguishes.
Uint8List _compressedPrimitiveGltf(
  String extensionName, {
  bool bufferView = false,
}) {
  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
            'extensions': <String, Object?>{extensionName: <String, Object?>{}},
          },
        ],
      },
    ],
    'accessors': <Object?>[
      <String, Object?>{
        if (bufferView) 'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
      },
    ],
    if (bufferView) ...<String, Object?>{
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      ],
      'buffers': <Object?>[
        <String, Object?>{
          'byteLength': 36,
          'uri':
              'data:application/octet-stream;base64,'
              '${base64Encode(Float32List(9).buffer.asUint8List())}',
        },
      ],
    },
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(document)));
}

void main() {
  // What each extension's warning says when the primitive cannot be read
  // through it. They used to say the same thing. `gfx-82n` made Draco a
  // decoder, so an extension object with nothing in it — which is what this
  // handwritten file has — is now a payload that *did not decode*, with the
  // reason; meshopt on a primitive is still simply not where that extension
  // lives.
  for (final (String extensionName, String complaint) in <(String, String)>[
    ('KHR_draco_mesh_compression', 'did not decode: the extension names no'),
    ('EXT_meshopt_compression', 'not implemented'),
  ]) {
    group(extensionName, () {
      test('with no buffer view on its own POSITION, the primitive is '
          'skipped rather than decoded as zeros', () async {
        final document = await decodeModel(
          ModelLoadRequest(
            source: _BytesSource(_compressedPrimitiveGltf(extensionName)),
          ),
        );

        // fmt-15's own acceptance line: a handwritten glTF like this one
        // reads back as zero surfaces, with a warning — not a degenerate
        // triangle pinched to the origin.
        //
        // Mutation: read `reader.hasBufferView` backwards (skip when it
        // *does* have one) — the primitive below, which does have a real
        // buffer view, would then be the one skipped instead of this one.
        expect(document.surfaces, isEmpty);
        expect(
          document.warnings.any((String w) => w.contains('no buffer view')),
          isTrue,
          reason: document.warnings.join('\n'),
        );
      });

      test('with a real buffer view on its own POSITION, the primitive is '
          'still read from it', () async {
        final document = await decodeModel(
          ModelLoadRequest(
            source: _BytesSource(
              _compressedPrimitiveGltf(extensionName, bufferView: true),
            ),
          ),
        );

        // Mutation: skip every compressed primitive regardless of
        // `hasBufferView` — this one, which an exporter gave a real
        // fallback to, would come back empty too.
        expect(document.surfaces, hasLength(1));
        expect(
          document.warnings.any((String w) => w.contains(complaint)),
          isTrue,
          reason: document.warnings.join('\n'),
        );
      });
    });
  }
}
