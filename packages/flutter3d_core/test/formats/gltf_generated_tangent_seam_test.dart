/// A glTF primitive without TANGENT whose UVs are mirrored across a shared
/// edge, loaded: the frames are MikkTSpace's, split at the seam, and a morph
/// target still covers every vertex.
///
///     dart test test/formats/gltf_generated_tangent_seam_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';

/// Two quads meeting at x = 0 with u = 1 - |x|: the left half's UVs are the
/// right half's mirrored, and the two vertices on the seam are shared.
const List<double> _positions = <double>[
  -1, 0, 0, 0, 0, 0, 1, 0, 0, //
  -1, 1, 0, 0, 1, 0, 1, 1, 0,
];
const List<double> _normals = <double>[
  0, 0, 1, 0, 0, 1, 0, 0, 1, //
  0, 0, 1, 0, 0, 1, 0, 0, 1,
];
const List<double> _texcoords = <double>[0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1];
const List<int> _indices = <int>[0, 1, 4, 0, 4, 3, 1, 2, 5, 1, 5, 4];

/// Each vertex lifted by its own index, so a copy given the wrong vertex's
/// delta shows which.
List<double> get _lift => <double>[
  for (var v = 0; v < 6; v++) ...<double>[0, 0, v + 1.0],
];

Uint8List _file() {
  final floats = Float32List.fromList(<double>[
    ..._positions,
    ..._normals,
    ..._texcoords,
    ..._lift,
  ]);
  final bytes = BytesBuilder()
    ..add(floats.buffer.asUint8List())
    ..add(Uint16List.fromList(_indices).buffer.asUint8List());
  final buffer = bytes.toBytes();
  Map<String, Object?> view(int offset, int length) => <String, Object?>{
    'buffer': 0,
    'byteOffset': offset,
    'byteLength': length,
  };
  Map<String, Object?> accessor(int view, int count, String type, int kind) =>
      <String, Object?>{
        'bufferView': view,
        'componentType': kind,
        'count': count,
        'type': type,
      };
  return Uint8List.fromList(
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
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'NORMAL': 1,
                  'TEXCOORD_0': 2,
                },
                'indices': 4,
                'targets': <Object?>[
                  <String, Object?>{'POSITION': 3},
                ],
              },
            ],
          },
        ],
        'accessors': <Object?>[
          accessor(0, 6, 'VEC3', 5126),
          accessor(1, 6, 'VEC3', 5126),
          accessor(2, 6, 'VEC2', 5126),
          accessor(3, 6, 'VEC3', 5126),
          accessor(4, 12, 'SCALAR', 5123),
        ],
        'bufferViews': <Object?>[
          view(0, 72),
          view(72, 72),
          view(144, 48),
          view(192, 72),
          view(264, 24),
        ],
        'buffers': <Object?>[
          <String, Object?>{
            'byteLength': buffer.length,
            'uri':
                'data:application/octet-stream;base64,${base64Encode(buffer)}',
          },
        ],
      }),
    ),
  );
}

void main() {
  test('the seam is split and the morph target follows the copies', () async {
    final asset = await GltfLoader().load(_file());
    final mesh = asset.surfaces.single.mesh;
    final stride = mesh.layout.floatsPerVertex;
    final tangent = mesh.layout.floatOffsetOf(VertexLayout.tangent.name);
    double signAt(int corner) =>
        mesh.vertices[mesh.indices[corner] * stride + tangent + 3];

    // Both halves' own handedness on the seam, which one vertex cannot hold:
    // the left half keeps the originals, the right half points at copies.
    //
    // Mutation: passing `splitSeams: false` to the loader's
    // `generateTangents` keeps six vertices and the right half's seam corners
    // take the left half's sign.
    expect(mesh.vertexCount, 8);
    for (final corner in <int>[0, 1, 2, 3, 4, 5]) {
      expect(signAt(corner), -1.0, reason: 'left corner $corner');
    }
    for (final corner in <int>[6, 7, 8, 9, 10, 11]) {
      expect(signAt(corner), 1.0, reason: 'right corner $corner');
    }

    // The target covers the copies, and each copy lifts with its source: the
    // seam does not tear open when the shape blends.
    //
    // Mutation: dropping `_withCopies` leaves a six-vertex target on an
    // eight-vertex mesh, which `MeshData` refuses.
    final target = mesh.morphTargets.single;
    expect(target.vertexCount, 8);
    expect(target.positions.sublist(18, 24), <double>[0, 0, 2, 0, 0, 5]);
    expect(asset.warnings.where((w) => w.contains('morph')), isEmpty);
  });
}
