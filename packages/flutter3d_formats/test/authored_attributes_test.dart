/// Which vertex attributes a file actually declared, as opposed to what a
/// decoder filled in to satisfy a requested layout.
///
///     dart test test/authored_attributes_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

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

/// A one-triangle glTF whose primitive declares exactly [attributes] — a
/// subset of `{'NORMAL', 'TEXCOORD_0'}` on top of the `POSITION` every
/// primitive needs.
Uint8List _triangleGltf(Set<String> attributes) {
  final positions = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final normals = Float32List.fromList(<double>[0, 0, 1, 0, 0, 1, 0, 0, 1]);
  final texcoords = Float32List.fromList(<double>[0, 0, 1, 0, 0, 1]);

  final buffers = <Float32List>[
    positions,
    if (attributes.contains('NORMAL')) normals,
    if (attributes.contains('TEXCOORD_0')) texcoords,
  ];
  final blob = BytesBuilder();
  final byteOffsets = <int>[];
  for (final buffer in buffers) {
    byteOffsets.add(blob.length);
    blob.add(buffer.buffer.asUint8List());
  }
  final wholeBuffer = base64Encode(blob.toBytes());

  var next = 0;
  final accessors = <Object?>[
    <String, Object?>{
      'bufferView': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC3',
      'min': <Object?>[0, 0, 0],
      'max': <Object?>[1, 1, 0],
    },
  ];
  final bufferViews = <Object?>[
    <String, Object?>{
      'buffer': 0,
      'byteOffset': byteOffsets[next++],
      'byteLength': positions.lengthInBytes,
    },
  ];
  final gltfAttributes = <String, Object?>{'POSITION': 0};

  if (attributes.contains('NORMAL')) {
    bufferViews.add(<String, Object?>{
      'buffer': 0,
      'byteOffset': byteOffsets[next++],
      'byteLength': normals.lengthInBytes,
    });
    accessors.add(<String, Object?>{
      'bufferView': bufferViews.length - 1,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC3',
    });
    gltfAttributes['NORMAL'] = accessors.length - 1;
  }
  if (attributes.contains('TEXCOORD_0')) {
    bufferViews.add(<String, Object?>{
      'buffer': 0,
      'byteOffset': byteOffsets[next++],
      'byteLength': texcoords.lengthInBytes,
    });
    accessors.add(<String, Object?>{
      'bufferView': bufferViews.length - 1,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC2',
    });
    gltfAttributes['TEXCOORD_0'] = accessors.length - 1;
  }

  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0, 'name': 'triangle'},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{'attributes': gltfAttributes},
        ],
      },
    ],
    'accessors': accessors,
    'bufferViews': bufferViews,
    'buffers': <Object?>[
      <String, Object?>{
        'byteLength': blob.length,
        'uri': 'data:application/octet-stream;base64,$wholeBuffer',
      },
    ],
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(document)));
}

void main() {
  group('the default, for a document built by hand', () {
    test('is every attribute the mesh layout has', () {
      final surface = ModelSurface(
        mesh: MeshData(
          layout: VertexLayout.positionNormal,
          vertices: Float32List(0),
          indices: Uint32List(0),
        ),
        transform: Matrix4.identity(),
      );
      expect(surface.authoredAttributes, <String>{'position', 'normal'});
    });

    test('an explicit set is kept exactly, not merged with the layout', () {
      final surface = ModelSurface(
        mesh: MeshData(
          layout: VertexLayout.positionNormal,
          vertices: Float32List(0),
          indices: Uint32List(0),
        ),
        transform: Matrix4.identity(),
        authoredAttributes: const <String>{'position'},
      );
      expect(surface.authoredAttributes, <String>{'position'});
    });
  });

  group('glTF: only what the primitive names', () {
    test(
      'POSITION alone authors nothing else, though the layout fills it in',
      () async {
        final document = await decodeModel(
          ModelLoadRequest(
            source: _BytesSource(_triangleGltf(const <String>{})),
          ),
        );
        final surface = document.surfaces.single;
        // Mutation: default to `mesh.layout`'s full set instead of tracking the
        // real accessors. The requested layout is `VertexLayout.standard`, so a
        // mesh built with no NORMAL/TEXCOORD/TANGENT accessor still comes back
        // with all three slots — flat-generated, zero-padded and generated in
        // turn — and a writer trusting the layout would declare all three as if
        // the file had them.
        expect(surface.authoredAttributes, <String>{'position'});
        expect(surface.mesh.layout.has(VertexLayout.normal), isTrue);
      },
    );

    test('NORMAL in the file is authored; TEXCOORD it lacks is not', () async {
      final document = await decodeModel(
        ModelLoadRequest(
          source: _BytesSource(_triangleGltf(const <String>{'NORMAL'})),
        ),
      );
      final surface = document.surfaces.single;
      expect(surface.authoredAttributes, contains('normal'));
      expect(surface.authoredAttributes, isNot(contains('texcoord')));
    });

    test('both NORMAL and TEXCOORD_0 in the file are both authored', () async {
      final document = await decodeModel(
        ModelLoadRequest(
          source: _BytesSource(
            _triangleGltf(const <String>{'NORMAL', 'TEXCOORD_0'}),
          ),
        ),
      );
      final surface = document.surfaces.single;
      expect(
        surface.authoredAttributes,
        containsAll(<String>['position', 'normal', 'texcoord']),
      );
      // TANGENT is never in this fixture, so it is always generated.
      expect(surface.authoredAttributes, isNot(contains('tangent')));
    });
  });

  group('OBJ: normals and texcoords the file has; a tangent it never does', () {
    test(
      'a face with vn and vt authors both; the derived tangent is not',
      () async {
        const obj = '''
v 0 0 0
v 1 0 0
v 0 1 0
vt 0 0
vt 1 0
vt 0 1
vn 0 0 1
vn 0 0 1
vn 0 0 1
f 1/1/1 2/2/2 3/3/3
''';
        final document = await ObjLoader(
          layout: VertexLayout.standard,
        ).load(Uint8List.fromList(utf8.encode(obj)));
        final surface = document.surfaces.single;
        expect(
          surface.authoredAttributes,
          containsAll(<String>['position', 'normal', 'texcoord']),
        );
        // Mutation: leave 'tangent' out of nothing, i.e. include it — OBJ has
        // no tangent record at all, and `withGeneratedTangents` runs whenever
        // the layout wants one, so a writer trusting this set must never see
        // 'tangent' here regardless of what the layout asked for.
        expect(surface.authoredAttributes, isNot(contains('tangent')));
      },
    );

    test(
      'a face with only v generates its normal, which is then unauthored',
      () async {
        const obj = '''
v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
''';
        final document = await ObjLoader(
          layout: VertexLayout.positionNormal,
        ).load(Uint8List.fromList(utf8.encode(obj)));
        final surface = document.surfaces.single;
        expect(surface.authoredAttributes, <String>{'position'});
        // The mesh still has a normal — smoothed/flat-generated — the layout
        // asked for one; it is just not an authored one.
        expect(surface.mesh.layout.has(VertexLayout.normal), isTrue);
      },
    );
  });

  group(
    '.f3d: the set survives a round trip, and an old file reads as all',
    () {
      test('an explicit, partial set comes back exactly', () {
        final surface = ModelSurface(
          mesh: MeshData(
            layout: VertexLayout.positionNormalTexcoord,
            vertices: Float32List(3 * 8),
            indices: Uint32List.fromList(<int>[0, 1, 2]),
          ),
          transform: Matrix4.identity(),
          authoredAttributes: const <String>{'position', 'normal'},
        );
        final document = PlainModelDocument(surfaces: <ModelSurface>[surface]);
        final bytes = F3dWriter(document).write();
        final reread = F3dDocument.parse(bytes);

        expect(reread.surfaces.single.authoredAttributes, <String>{
          'position',
          'normal',
        });
      });

      test('a section-17-less file reads back as every attribute authored', () {
        // Simulates a `.f3d` written before `fmt-03`: the surface's own record
        // is unaffected, and only the new section is missing.
        final surface = ModelSurface(
          mesh: MeshData(
            layout: VertexLayout.positionNormalTexcoord,
            vertices: Float32List(3 * 8),
            indices: Uint32List.fromList(<int>[0, 1, 2]),
          ),
          transform: Matrix4.identity(),
          authoredAttributes: const <String>{'position'},
        );
        final document = PlainModelDocument(surfaces: <ModelSurface>[surface]);
        final bytes = _withoutSurfaceAttributesSection(
          F3dWriter(document).write(),
        );
        final reread = F3dDocument.parse(bytes);

        // Mutation: read the missing section as empty rather than as null and
        // this comes back `{}` instead of the mesh's whole layout — a v1 file
        // opening with every surface unpainted rather than the honest fallback.
        expect(reread.surfaces.single.authoredAttributes, <String>{
          'position',
          'normal',
          'texcoord',
        });
      });
    },
  );
}

/// [bytes] with the `surfaceAttributes` directory entry's kind changed to one
/// nothing reads, so the section is present in the file but invisible to the
/// loader — the same shape as a file a version that never wrote it produced.
Uint8List _withoutSurfaceAttributesSection(Uint8List bytes) {
  final out = Uint8List.fromList(bytes);
  final view = ByteData.view(out.buffer);
  final sectionCount = view.getUint32(8, Endian.little);
  for (var i = 0; i < sectionCount; i++) {
    final entry = 16 + i * 16;
    if (view.getUint32(entry, Endian.little) == 17) {
      view.setUint32(entry, 0xFFFF, Endian.little);
    }
  }
  return out;
}
