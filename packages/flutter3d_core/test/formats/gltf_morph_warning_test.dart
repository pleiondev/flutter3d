/// A morph-target warning names the primitive it is about.
///
///     dart test test/formats/gltf_morph_warning_test.dart
///
/// The three warnings `_readMorphTargets` can add were written with their
/// interpolations escaped — `'\$label has \${targets.length} …'` — so every
/// one of them said, literally, `$label has ${targets.length} morph target(s)`.
/// Nothing failed, because nothing read them: a warning is for a person, and a
/// person reading that one learns only that something, somewhere, was dropped.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  test('a target dropped by flat shading says which primitive and how '
      'many vertices', () async {
    // One triangle with no NORMAL, so the loader flat-shades it and rebuilds
    // its vertices — the one path on which a target's deltas stop lining up.
    final positions = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]);
    final asset = await GltfLoader().load(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
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
                    'targets': <Object?>[
                      <String, Object?>{'POSITION': 0},
                    ],
                  },
                ],
              },
            ],
            'accessors': <Object?>[
              <String, Object?>{
                'bufferView': 0,
                'componentType': 5126,
                'count': 3,
                'type': 'VEC3',
              },
            ],
            'bufferViews': <Object?>[
              <String, Object?>{'buffer': 0, 'byteLength': 36},
            ],
            'buffers': <Object?>[
              <String, Object?>{
                'byteLength': 36,
                'uri':
                    'data:application/octet-stream;base64,'
                    '${base64Encode(positions.buffer.asUint8List())}',
              },
            ],
          }),
        ),
      ),
    );

    final warning = asset.warnings.singleWhere(
      (w) => w.contains('morph target'),
    );
    expect(warning, startsWith('meshes[0].primitives[0] has 1 morph target'));
    expect(warning, contains('3 vertices from 3'));
    expect(warning, isNot(contains(r'$')));
  });
}
