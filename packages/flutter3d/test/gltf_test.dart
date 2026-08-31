import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/gltf_resolvers.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String kSamples = 'assets/samples';

Uint8List readSample(String name) =>
    File('$kSamples/$name').readAsBytesSync();

/// Builds a GLB from a JSON document and an optional binary chunk.
///
/// Hand-assembling the container is the only way to test chunk padding, unknown
/// chunk types and truncation, none of which a well-formed sample file exercises.
Uint8List buildGlb(Map<String, Object?> json, {Uint8List? binary}) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadding = (4 - (jsonBytes.length % 4)) % 4;
  final binPadding = binary == null ? 0 : (4 - (binary.length % 4)) % 4;

  final total = 12 +
      8 +
      jsonBytes.length +
      jsonPadding +
      (binary == null ? 0 : 8 + binary.length + binPadding);

  final out = BytesBuilder();
  final header = ByteData(12);
  header.setUint32(0, 0x46546C67, Endian.little); // 'glTF'
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, total, Endian.little);
  out.add(header.buffer.asUint8List());

  final jsonHeader = ByteData(8);
  jsonHeader.setUint32(0, jsonBytes.length + jsonPadding, Endian.little);
  jsonHeader.setUint32(4, 0x4E4F534A, Endian.little); // 'JSON'
  out.add(jsonHeader.buffer.asUint8List());
  out.add(jsonBytes);
  // JSON chunks pad with spaces, binary chunks with zeros.
  out.add(List<int>.filled(jsonPadding, 0x20));

  if (binary != null) {
    final binHeader = ByteData(8);
    binHeader.setUint32(0, binary.length + binPadding, Endian.little);
    binHeader.setUint32(4, 0x004E4942, Endian.little); // 'BIN\0'
    out.add(binHeader.buffer.asUint8List());
    out.add(binary);
    out.add(List<int>.filled(binPadding, 0));
  }

  return out.toBytes();
}

Vector3 normalAt(MeshData mesh, int index) {
  final offset = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
  final base = index * mesh.layout.floatsPerVertex + offset;
  return Vector3(
    mesh.vertices[base],
    mesh.vertices[base + 1],
    mesh.vertices[base + 2],
  );
}

void main() {
  group('GLB container', () {
    test('parses the Khronos Box sample', () {
      final container = GlbContainer.parse(readSample('Box.glb'));
      expect(container.json['asset'], isA<Map>());
      expect(container.binaryChunk, isNotNull);
      expect(container.json['meshes'], isA<List>());
    });

    test('detects plain .gltf JSON by absence of the magic', () {
      final container = GlbContainer.parse(readSample('Triangle.gltf'));
      expect(container.binaryChunk, isNull);
      expect(container.json['meshes'], isA<List>());
    });

    test('ignores unknown chunk types', () {
      // Forward compatibility: a chunk we do not recognise must be skipped, not
      // treated as an error.
      final base = buildGlb({'asset': {'version': '2.0'}});
      final extra = BytesBuilder();
      final unknownHeader = ByteData(8);
      unknownHeader.setUint32(0, 4, Endian.little);
      unknownHeader.setUint32(4, 0x12345678, Endian.little);
      extra.add(base);
      extra.add(unknownHeader.buffer.asUint8List());
      extra.add(<int>[1, 2, 3, 4]);

      final bytes = extra.toBytes();
      // Patch the declared total length to cover the appended chunk.
      ByteData.sublistView(bytes).setUint32(8, bytes.length, Endian.little);

      final container = GlbContainer.parse(bytes);
      expect((container.json['asset']! as Map)['version'], '2.0');
    });

    test('rejects an unsupported version', () {
      final bytes = buildGlb({'asset': {'version': '2.0'}});
      ByteData.sublistView(bytes).setUint32(4, 1, Endian.little);
      expect(() => GlbContainer.parse(bytes), throwsFormatException);
    });

    test('rejects a chunk that overruns the file', () {
      final bytes = buildGlb({'asset': {'version': '2.0'}});
      // Claim a JSON chunk far larger than the file.
      ByteData.sublistView(bytes).setUint32(12, 0xFFFF, Endian.little);
      expect(() => GlbContainer.parse(bytes), throwsFormatException);
    });

    test('a truncated header is an error, not a crash', () {
      final bytes = Uint8List.fromList(<int>[0x67, 0x6C, 0x54, 0x46, 0, 0]);
      expect(() => GlbContainer.parse(bytes), throwsFormatException);
    });
  });

  group('data URIs', () {
    test('decodes base64 regardless of media type', () {
      final octet = decodeDataUri(
        'data:application/octet-stream;base64,AQIDBA==',
      );
      final gltfBuffer = decodeDataUri(
        'data:application/gltf-buffer;base64,AQIDBA==',
      );
      expect(octet, <int>[1, 2, 3, 4]);
      expect(gltfBuffer, <int>[1, 2, 3, 4]);
    });

    test('rejects a URI with no comma', () {
      expect(() => decodeDataUri('data:application/octet-stream'),
          throwsFormatException);
    });
  });

  group('accessors', () {
    test('respects byteStride for interleaved data', () async {
      // Two vec3 positions interleaved with a padding float, i.e. stride 16.
      final raw = Float32List.fromList(<double>[
        1, 2, 3, 999, //
        4, 5, 6, 999, //
      ]);
      final reader = GltfAccessorReader(
        json: <String, Object?>{
          'accessors': <Object?>[
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 2,
              'type': 'VEC3',
            },
          ],
          'bufferViews': <Object?>[
            {'buffer': 0, 'byteLength': raw.lengthInBytes, 'byteStride': 16},
          ],
        },
        buffers: <Uint8List>[raw.buffer.asUint8List()],
      );

      expect(reader.readAsFloats(0), <double>[1, 2, 3, 4, 5, 6]);
    });

    test('normalizes signed components with a symmetric clamp', () {
      final raw = Int8List.fromList(<int>[127, -127, -128, 0]);
      final reader = GltfAccessorReader(
        json: <String, Object?>{
          'accessors': <Object?>[
            {
              'bufferView': 0,
              'componentType': 5120,
              'count': 4,
              'type': 'SCALAR',
              'normalized': true,
            },
          ],
          'bufferViews': <Object?>[
            {'buffer': 0, 'byteLength': raw.lengthInBytes},
          ],
        },
        buffers: <Uint8List>[raw.buffer.asUint8List()],
      );

      final values = reader.readAsFloats(0);
      expect(values[0], closeTo(1.0, 1e-6));
      expect(values[1], closeTo(-1.0, 1e-6));
      // -128 would map below -1 without the clamp the spec requires.
      expect(values[2], closeTo(-1.0, 1e-6));
      expect(values[3], closeTo(0.0, 1e-6));
    });

    test('an accessor without a bufferView reads as zeros', () {
      final reader = GltfAccessorReader(
        json: <String, Object?>{
          'accessors': <Object?>[
            {'componentType': 5126, 'count': 2, 'type': 'VEC3'},
          ],
        },
        buffers: const <Uint8List>[],
      );
      expect(reader.readAsFloats(0), List<double>.filled(6, 0.0));
    });

    test('sparse accessors patch selected elements', () {
      final base = Float32List.fromList(<double>[0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final values = Float32List.fromList(<double>[7, 8, 9]);
      final indices = Uint16List.fromList(<int>[2]);

      final buffer = BytesBuilder()
        ..add(base.buffer.asUint8List())
        ..add(values.buffer.asUint8List())
        ..add(indices.buffer.asUint8List());
      final bytes = buffer.toBytes();

      final reader = GltfAccessorReader(
        json: <String, Object?>{
          'accessors': <Object?>[
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 3,
              'type': 'VEC3',
              'sparse': {
                'count': 1,
                'indices': {'bufferView': 2, 'componentType': 5123},
                'values': {'bufferView': 1},
              },
            },
          ],
          'bufferViews': <Object?>[
            {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
            {'buffer': 0, 'byteOffset': 36, 'byteLength': 12},
            {'buffer': 0, 'byteOffset': 48, 'byteLength': 2},
          ],
        },
        buffers: <Uint8List>[bytes],
      );

      expect(reader.readAsFloats(0), <double>[0, 0, 0, 0, 0, 0, 7, 8, 9]);
    });

    test('an out-of-range bufferView is reported', () {
      final reader = GltfAccessorReader(
        json: <String, Object?>{
          'accessors': <Object?>[
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 100,
              'type': 'VEC3',
            },
          ],
          'bufferViews': <Object?>[
            {'buffer': 0, 'byteLength': 12},
          ],
        },
        buffers: <Uint8List>[Uint8List(12)],
      );
      expect(() => reader.readAsFloats(0), throwsFormatException);
    });
  });

  group('loading real Khronos samples', () {
    test('Box.glb decodes to a closed cube', () async {
      final asset = await GltfLoader().load(readSample('Box.glb'));

      expect(asset.surfaces, hasLength(1));
      expect(asset.warnings, isEmpty);

      final mesh = asset.surfaces.single.mesh;
      expect(mesh.triangleCount, 12);
      // Winding must match our renderer's counter-clockwise front faces.
      expect(mesh.signedVolume(), greaterThan(0.0));

      // Every normal is axis aligned on a box.
      for (var i = 0; i < mesh.vertexCount; i++) {
        final n = normalAt(mesh, i);
        expect(n.length, closeTo(1.0, 1e-4));
      }
    });

    test('BoxTextured.glb carries a material and an embedded image', () async {
      final asset = await GltfLoader().load(readSample('BoxTextured.glb'));

      expect(asset.materials, isNotEmpty);
      expect(asset.images, isNotEmpty);
      expect(asset.images.first.bytes, isNotEmpty);

      final material = asset.materials.first;
      expect(material.baseColorTexture, isNotNull);
      expect(material.baseColorTexture!.imageIndex, 0);

      // The PNG magic proves the image bytes came out of the right bufferView.
      final bytes = asset.images.first.bytes;
      expect(bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);

      // UVs must be present, otherwise the texture has nothing to map to.
      final mesh = asset.surfaces.single.mesh;
      final uvOffset = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
      var nonZero = 0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final base = i * mesh.layout.floatsPerVertex + uvOffset;
        if (mesh.vertices[base] != 0.0 || mesh.vertices[base + 1] != 0.0) {
          nonZero++;
        }
      }
      expect(nonZero, greaterThan(0));
    });

    test('BoxVertexColors.glb decodes COLOR_0 when the layout wants it',
        () async {
      final loader = GltfLoader(
        layout: const VertexLayout(<VertexAttribute>[
          VertexLayout.position,
          VertexLayout.normal,
          VertexLayout.texcoord,
          VertexLayout.color,
        ]),
      );
      final asset = await loader.load(readSample('BoxVertexColors.glb'));
      final mesh = asset.surfaces.single.mesh;

      final colorOffset = mesh.layout.floatOffsetOf(VertexLayout.color.name);
      expect(colorOffset, greaterThanOrEqualTo(0));

      var saturated = 0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final base = i * mesh.layout.floatsPerVertex + colorOffset;
        final r = mesh.vertices[base];
        final g = mesh.vertices[base + 1];
        final b = mesh.vertices[base + 2];
        final a = mesh.vertices[base + 3];
        expect(a, closeTo(1.0, 1e-3));
        // Normalized integer colours must land in [0, 1], not in 0..255.
        expect(r, inInclusiveRange(0.0, 1.0));
        if (r > 0.9 || g > 0.9 || b > 0.9) saturated++;
      }
      expect(saturated, greaterThan(0));
    });

    test('Triangle.gltf loads from an embedded base64 buffer', () async {
      final asset = await GltfLoader().load(readSample('Triangle.gltf'));
      final mesh = asset.surfaces.single.mesh;
      expect(mesh.triangleCount, 1);
      expect(mesh.vertexCount, 3);
    });

    test('Cube.gltf loads external .bin through a resolver', () async {
      final asset = await GltfLoader().load(
        readSample('cube/Cube.gltf'),
        resolveUri: fileUriResolver('$kSamples/cube'),
      );
      expect(asset.surfaces, isNotEmpty);
      expect(asset.surfaces.single.mesh.triangleCount, greaterThan(0));
    });

    test('a .gltf with external buffers fails clearly without a resolver',
        () async {
      await expectLater(
        GltfLoader().load(readSample('cube/Cube.gltf')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no URI resolver'),
          ),
        ),
      );
    });
  });

  group('node hierarchy', () {
    Map<String, Object?> triangleDoc({
      List<Object?>? nodes,
      List<Object?>? sceneNodes,
    }) {
      final positions = Float32List.fromList(<double>[
        0, 0, 0, //
        1, 0, 0, //
        0, 1, 0, //
      ]);
      return <String, Object?>{
        'asset': {'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          {'nodes': sceneNodes ?? <Object?>[0]},
        ],
        'nodes': nodes ?? <Object?>[{'mesh': 0}],
        'meshes': <Object?>[
          {
            'primitives': <Object?>[
              {'attributes': {'POSITION': 0}},
            ],
          },
        ],
        'accessors': <Object?>[
          {
            'bufferView': 0,
            'componentType': 5126,
            'count': 3,
            'type': 'VEC3',
          },
        ],
        'bufferViews': <Object?>[
          {'buffer': 0, 'byteLength': positions.lengthInBytes},
        ],
        'buffers': <Object?>[
          {'byteLength': positions.lengthInBytes},
        ],
        '_positions': null,
      }..remove('_positions');
    }

    Uint8List triangleGlb({
      List<Object?>? nodes,
      List<Object?>? sceneNodes,
    }) {
      final positions = Float32List.fromList(<double>[
        0, 0, 0, //
        1, 0, 0, //
        0, 1, 0, //
      ]);
      return buildGlb(
        triangleDoc(nodes: nodes, sceneNodes: sceneNodes),
        binary: positions.buffer.asUint8List(),
      );
    }

    test('composes TRS into a world transform', () async {
      final asset = await GltfLoader().load(
        triangleGlb(
          nodes: <Object?>[
            {
              'mesh': 0,
              'translation': <Object?>[5, 0, 0],
              'scale': <Object?>[2, 2, 2],
            },
          ],
        ),
      );

      final transform = asset.surfaces.single.transform;
      final point = Vector3(1.0, 0.0, 0.0);
      transform.transform3(point);
      expect(point.x, closeTo(7.0, 1e-6));
    });

    test('accumulates parent transforms down the tree', () async {
      final asset = await GltfLoader().load(
        triangleGlb(
          nodes: <Object?>[
            {'translation': <Object?>[10, 0, 0], 'children': <Object?>[1]},
            {'mesh': 0, 'translation': <Object?>[1, 0, 0]},
          ],
        ),
      );

      final origin = Vector3.zero();
      asset.surfaces.single.transform.transform3(origin);
      expect(origin.x, closeTo(11.0, 1e-6));
    });

    test('reads a column-major matrix directly', () async {
      final asset = await GltfLoader().load(
        triangleGlb(
          nodes: <Object?>[
            {
              'mesh': 0,
              // Translation lives in the last column for column-major storage.
              'matrix': <Object?>[
                1, 0, 0, 0, //
                0, 1, 0, 0, //
                0, 0, 1, 0, //
                3, 4, 5, 1, //
              ],
            },
          ],
        ),
      );

      final origin = Vector3.zero();
      asset.surfaces.single.transform.transform3(origin);
      expect(origin, Vector3(3.0, 4.0, 5.0));
    });

    test('flags mirroring transforms so winding can be flipped', () async {
      final asset = await GltfLoader().load(
        triangleGlb(
          nodes: <Object?>[
            {'mesh': 0, 'scale': <Object?>[-1, 1, 1]},
          ],
        ),
      );
      expect(asset.surfaces.single.flipWinding, isTrue);
    });

    test('does not flag an ordinary transform', () async {
      final asset = await GltfLoader().load(triangleGlb());
      expect(asset.surfaces.single.flipWinding, isFalse);
    });

    test('survives a cyclic hierarchy', () async {
      final asset = await GltfLoader().load(
        triangleGlb(
          nodes: <Object?>[
            {'children': <Object?>[1]},
            {'mesh': 0, 'children': <Object?>[0]},
          ],
        ),
      );
      expect(asset.surfaces, hasLength(1));
      expect(asset.warnings.any((w) => w.contains('cycle')), isTrue);
    });

    test('reuses one node twice as two instances', () async {
      final asset = await GltfLoader().load(
        triangleGlb(
          sceneNodes: <Object?>[0, 1],
          nodes: <Object?>[
            {'mesh': 0, 'translation': <Object?>[-1, 0, 0]},
            {'mesh': 0, 'translation': <Object?>[1, 0, 0]},
          ],
        ),
      );
      expect(asset.surfaces, hasLength(2));
      // Same geometry, different placement.
      expect(
        asset.surfaces[0].mesh.vertexCount,
        asset.surfaces[1].mesh.vertexCount,
      );
    });
  });

  group('primitive modes and missing attributes', () {
    Uint8List quadGlb({int? mode, List<int>? indices}) {
      final positions = Float32List.fromList(<double>[
        0, 0, 0, //
        1, 0, 0, //
        0, 1, 0, //
        1, 1, 0, //
      ]);
      final indexData = Uint16List.fromList(indices ?? <int>[0, 1, 2, 3]);
      final binary = BytesBuilder()
        ..add(positions.buffer.asUint8List())
        ..add(indexData.buffer.asUint8List());

      return buildGlb(
        <String, Object?>{
          'asset': {'version': '2.0'},
          'scene': 0,
          'scenes': <Object?>[{'nodes': <Object?>[0]}],
          'nodes': <Object?>[{'mesh': 0}],
          'meshes': <Object?>[
            {
              'primitives': <Object?>[
                {
                  'attributes': {'POSITION': 0},
                  'indices': 1,
                  'mode': ?mode,
                },
              ],
            },
          ],
          'accessors': <Object?>[
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 4,
              'type': 'VEC3',
            },
            {
              'bufferView': 1,
              'componentType': 5123,
              'count': indexData.length,
              'type': 'SCALAR',
            },
          ],
          'bufferViews': <Object?>[
            {'buffer': 0, 'byteOffset': 0, 'byteLength': 48},
            {'buffer': 0, 'byteOffset': 48, 'byteLength': indexData.lengthInBytes},
          ],
          'buffers': <Object?>[{'byteLength': 48 + indexData.lengthInBytes}],
        },
        binary: binary.toBytes(),
      );
    }

    test('converts a triangle strip to a triangle list', () async {
      final asset = await GltfLoader().load(quadGlb(mode: 5));
      // Four strip indices describe two triangles.
      expect(asset.surfaces.single.mesh.triangleCount, 2);
    });

    test('converts a triangle fan to a triangle list', () async {
      final asset = await GltfLoader().load(quadGlb(mode: 6));
      expect(asset.surfaces.single.mesh.triangleCount, 2);
    });

    test('skips line and point topologies with a warning', () async {
      for (final mode in <int>[0, 1, 2, 3]) {
        final asset = await GltfLoader().load(quadGlb(mode: mode));
        expect(asset.surfaces, isEmpty, reason: 'mode $mode');
        expect(asset.warnings, isNotEmpty, reason: 'mode $mode');
      }
    });

    test('generates flat normals when NORMAL is absent', () async {
      final asset = await GltfLoader().load(
        quadGlb(indices: <int>[0, 1, 2]),
      );
      final mesh = asset.surfaces.single.mesh;

      // Flat shading requires per-face normals, so the triangle is de-indexed.
      expect(mesh.vertexCount, 3);
      for (var i = 0; i < mesh.vertexCount; i++) {
        // The quad lies in the XY plane, so its face normal is +Z.
        expect(normalAt(mesh, i), Vector3(0.0, 0.0, 1.0));
      }
    });

    test('leaves normals at zero when flat generation is disabled', () async {
      final loader = GltfLoader(generateFlatNormalsWhenMissing: false);
      final asset = await loader.load(quadGlb(indices: <int>[0, 1, 2]));
      final mesh = asset.surfaces.single.mesh;

      expect(normalAt(mesh, 0), Vector3.zero());
      expect(asset.warnings.any((w) => w.contains('no NORMAL')), isTrue);
    });

    test('an out-of-range index is reported, not rendered', () async {
      final asset = await GltfLoader().load(
        quadGlb(indices: <int>[0, 1, 99]),
      );
      expect(asset.surfaces, isEmpty);
      expect(asset.warnings.single, contains('exceeds'));
    });
  });

  group('materials', () {
    test('applies glTF defaults when fields are absent', () async {
      final asset = await GltfLoader().load(
        buildGlb(<String, Object?>{
          'asset': {'version': '2.0'},
          'materials': <Object?>[<String, Object?>{}],
        }),
      );

      final material = asset.materials.single;
      expect(material.baseColor, Vector4(1.0, 1.0, 1.0, 1.0));
      expect(material.metallic, 1.0);
      expect(material.roughness, 1.0);
      expect(material.alphaMode, SurfaceAlphaMode.opaque);
      expect(material.doubleSided, isFalse);
      expect(material.emissive, Vector3.zero());
    });

    test('reads factors, alpha mode and extensions', () async {
      final asset = await GltfLoader().load(
        buildGlb(<String, Object?>{
          'asset': {'version': '2.0'},
          'materials': <Object?>[
            {
              'name': 'Glass',
              'pbrMetallicRoughness': {
                'baseColorFactor': <Object?>[0.1, 0.2, 0.3, 0.4],
                'metallicFactor': 0.25,
                'roughnessFactor': 0.75,
              },
              'emissiveFactor': <Object?>[1, 0.5, 0],
              'alphaMode': 'BLEND',
              'doubleSided': true,
              'extensions': {
                'KHR_materials_unlit': <String, Object?>{},
                'KHR_materials_emissive_strength': {'emissiveStrength': 3.0},
              },
            },
          ],
        }),
      );

      final material = asset.materials.single;
      expect(material.name, 'Glass');
      expect(material.baseColor.w, closeTo(0.4, 1e-6));
      expect(material.metallic, closeTo(0.25, 1e-6));
      expect(material.alphaMode, SurfaceAlphaMode.blend);
      expect(material.doubleSided, isTrue);
      expect(material.unlit, isTrue);
      expect(material.emissiveStrength, closeTo(3.0, 1e-6));
    });

    test('decodes sampler wrap modes', () async {
      final asset = await GltfLoader().load(
        buildGlb(<String, Object?>{
          'asset': {'version': '2.0'},
          'materials': <Object?>[
            {
              'pbrMetallicRoughness': {
                'baseColorTexture': {'index': 0},
              },
            },
          ],
          'textures': <Object?>[{'source': 0, 'sampler': 0}],
          'samplers': <Object?>[
            {'wrapS': 33071, 'wrapT': 33648, 'magFilter': 9728},
          ],
          'images': <Object?>[
            {'uri': 'data:image/png;base64,iVBORw0KGgo='},
          ],
        }),
      );

      final sampler = asset.materials.single.baseColorTexture!.sampling;
      expect(sampler.wrapS, TextureWrap.clampToEdge);
      expect(sampler.wrapT, TextureWrap.mirroredRepeat);
      expect(sampler.magLinear, isFalse);
    });
  });

  group('extension handling', () {
    test('a required unimplemented extension fails loudly', () async {
      await expectLater(
        GltfLoader().load(
          buildGlb(<String, Object?>{
            'asset': {'version': '2.0'},
            'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('KHR_draco_mesh_compression'),
          ),
        ),
      );
    });

    test('a merely used extension does not block loading', () async {
      final asset = await GltfLoader().load(
        buildGlb(<String, Object?>{
          'asset': {'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_materials_clearcoat'],
          'materials': <Object?>[<String, Object?>{}],
        }),
      );
      expect(asset.materials, hasLength(1));
    });
  });

  group('bounds', () {
    test('cover instances in world space', () async {
      final asset = await GltfLoader().load(readSample('Box.glb'));
      final bounds = asset.computeBounds();
      expect(bounds.max.x, greaterThan(bounds.min.x));
      expect(bounds.max.y, greaterThan(bounds.min.y));
      expect(bounds.max.z, greaterThan(bounds.min.z));
    });

    test('an empty asset has degenerate bounds rather than infinities', () {
      const asset = GltfAsset(
        surfaces: <ModelSurface>[],
        materials: <SurfaceMaterial>[],
        images: <EncodedImage>[],
        warnings: <String>[],
        nodes: <ModelNode>[],
        roots: <int>[],
      );
      final bounds = asset.computeBounds();
      expect(bounds.min.x.isFinite, isTrue);
      expect(bounds.max.x.isFinite, isTrue);
    });
  });

  group('resolver safety', () {
    test('refuses to escape the base directory', () async {
      final resolve = fileUriResolver(kSamples);
      await expectLater(
        resolve('../../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(resolve('/etc/passwd'), throwsA(isA<ArgumentError>()));
    });

    test('percent-decodes ordinary relative paths', () async {
      final resolve = fileUriResolver('$kSamples/cube');
      final bytes = await resolve('Cube.bin');
      expect(bytes, isNotEmpty);
    });
  });
}
