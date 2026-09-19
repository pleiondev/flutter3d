/// A glTF compressed with `KHR_draco_mesh_compression` opens as the model it
/// was made from — `gfx-82n`.
///
///     dart test test/formats/gltf_draco_test.dart
///
/// **Every compressed file here was written by Draco's own encoder**, through
/// `@gltf-transform/cli` 4.5.0, and is compared with the uncompressed file it
/// was made from:
///
///     gltf-transform draco building.glb building_draco_default.glb
///     gltf-transform draco building.glb building_draco_speed0.glb \
///         --encode-speed 0 --decode-speed 0
///     gltf-transform draco RiggedSimple.glb rigged_simple_draco.glb
///
/// `building.glb` is `apps/flutter3d_demo_racing`'s `building-k.glb` with its
/// texture and material dropped — 1024 faces, UV seams, tangents, holes and
/// handles, which is to say a mesh somebody modelled rather than one a test
/// generated. `RiggedSimple.glb` is the Khronos sample in `flutter3d_samples`.
///
/// **Two speeds, because they are two decoders.** At its default speed the
/// encoder writes the standard edgebreaker traversal, the parallelogram
/// predictor, and plain differences for normals. At speed zero it writes none
/// of those: the valence traversal, the prediction-degree attribute walk, the
/// constrained multi-parallelogram, the portable texture-coordinate predictor
/// and the geometric normal one. A decoder checked against the default file
/// alone is checked on half of itself, and the other half is what Blender's
/// exporter reaches for.
///
/// **Triangles, not vertices** — see `helpers/triangle_match.dart`. The
/// encoder reorders both and welds what it can, so the comparison is of what
/// the two files *draw*: every triangle of the original, with every attribute
/// at each of its corners, has one partner in the decoded mesh to within the
/// quantisation the encoder was asked for.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';

import 'helpers/triangle_match.dart';

Uint8List _fixture(String name) =>
    File('test/formats/fixtures/draco/$name').readAsBytesSync();

Uint8List _sample(String name) =>
    File('../flutter3d_samples/assets/$name').readAsBytesSync();

/// Every triangle corner of [mesh], as the floats of [attributes] in order.
Float32List _corners(MeshData mesh, List<VertexAttribute> attributes) {
  final stride = mesh.layout.floatsPerVertex;
  return Float32List.fromList(<double>[
    for (final index in mesh.indices)
      for (final attribute in attributes)
        for (var c = 0; c < attribute.componentCount; c++)
          mesh.vertices[index * stride +
              mesh.layout.floatOffsetOf(attribute.name) +
              c],
  ]);
}

/// One tolerance per float of a corner, in the order [_corners] writes them.
List<double> _tolerances(Map<VertexAttribute, double> perAttribute) => <double>[
  for (final MapEntry(key: attribute, value: tolerance) in perAttribute.entries)
    for (var c = 0; c < attribute.componentCount; c++) tolerance,
];

/// The encoder's defaults: 14 bits for positions, 10 for normals, 12 for
/// texture coordinates and for anything generic. Each tolerance is *one
/// quantisation step* of that attribute over [extent], the longest side of the
/// box it was fitted in — twice the rounding error, so a correct decoder has
/// room and a decoder that is off by one step on anything does not.
Map<VertexAttribute, double> _defaultQuantisation({
  required double extent,
  required double uvExtent,
}) => <VertexAttribute, double>{
  VertexLayout.position: extent / 16383,
  // Octahedral, so not a box: ten bits a side is a worst case of about a
  // quarter of a degree, which is 0.005 in a component of a unit vector.
  VertexLayout.normal: 0.005,
  VertexLayout.texcoord: uvExtent / 4095,
  VertexLayout.tangent: 2.0 / 4095,
};

void main() {
  group('a static mesh with UV seams and tangents', () {
    late GltfAsset original;

    setUpAll(() async {
      original = await GltfLoader().load(_fixture('building.glb'));
    });

    for (final (name, what) in <(String, String)>[
      (
        'building_draco_default.glb',
        'standard edgebreaker and the parallelogram predictor',
      ),
      (
        'building_draco_speed0.glb',
        'valence edgebreaker, the prediction-degree walk and the '
            'position-driven predictors',
      ),
    ]) {
      test('$name — $what', () async {
        final decoded = await GltfLoader().load(_fixture(name));
        expect(decoded.warnings, isEmpty);
        expect(decoded.surfaces, hasLength(original.surfaces.length));

        final expected = original.surfaces.single.mesh;
        final actual = decoded.surfaces.single.mesh;

        // `gfx-82n`'s own acceptance line. The index count is the mesh's; the
        // vertex count is the encoder's, which welds — so it is bounded by
        // the original's rather than equal to it.
        expect(actual.indexCount, expected.indexCount);
        expect(actual.vertexCount, lessThanOrEqualTo(expected.vertexCount));
        expect(actual.vertexCount, greaterThan(expected.vertexCount ~/ 2));

        final bounds = expected.computeBounds();
        final size = bounds.max - bounds.min;
        final tolerances = _defaultQuantisation(
          extent: <double>[
            size.x,
            size.y,
            size.z,
          ].reduce((a, b) => a > b ? a : b),
          // The atlas this model was unwrapped onto spans more than the unit
          // square, and the step is a fraction of what it spans.
          uvExtent: 4.0,
        );
        final attributes = tolerances.keys.toList();

        expect(
          unmatchedTriangles(
            _corners(expected, attributes),
            _corners(actual, attributes),
            _tolerances(tolerances),
          ),
          isEmpty,
          reason:
              'triangles of the original with no partner in the decoded '
              'mesh, by index',
        );
      });
    }
  });

  test('a skinned mesh keeps its joints as the integers they are', () async {
    // **Joints go through Draco as integers, not as quantised floats**, and
    // come out as the accessor's unsigned shorts. Read through the float path
    // they would still be numbers — joint 1 of 2 quantised to twelve bits is
    // 0.9998 — and the mesh would skin to the wrong bone without a warning
    // anywhere. So they are compared exactly.
    final original = await GltfLoader().load(_sample('RiggedSimple.glb'));
    final decoded = await GltfLoader().load(
      _fixture('rigged_simple_draco.glb'),
    );
    expect(decoded.warnings, isEmpty);

    final expected = original.surfaces.single.mesh;
    final actual = decoded.surfaces.single.mesh;
    expect(actual.layout.isSkinned, isTrue);
    expect(actual.indexCount, expected.indexCount);

    final bounds = expected.computeBounds();
    final size = bounds.max - bounds.min;
    final tolerances = <VertexAttribute, double>{
      VertexLayout.position:
          <double>[size.x, size.y, size.z].reduce((a, b) => a > b ? a : b) /
          16383,
      VertexLayout.normal: 0.005,
      VertexLayout.joints: 0.0,
      VertexLayout.weights: 1.0 / 4095,
    };
    final attributes = tolerances.keys.toList();
    expect(
      unmatchedTriangles(
        _corners(expected, attributes),
        _corners(actual, attributes),
        _tolerances(tolerances),
      ),
      isEmpty,
    );
  });

  group('a payload that does not decode', () {
    test('costs the primitive, and the warning says why', () async {
      // The same file with its Draco payload cut short. Every Draco glTF names
      // the extension as required and gives its accessors no buffer views, so
      // there is nothing to fall back on: the surface is dropped, the file
      // still opens, and the warning carries the decoder's own reason rather
      // than "skipped".
      final whole = _fixture('building_draco_default.glb');
      final container = GlbContainer.parse(whole);
      final views = container.json['bufferViews']! as List<Object?>;
      final payload = views.cast<Map<String, Object?>>().firstWhere(
        (view) => (view['byteLength']! as int) > 1000,
      );
      payload['byteLength'] = 400;

      final document = await GltfLoader().load(
        GlbContainer.encode(container.json, binary: container.binaryChunk),
      );
      expect(document.surfaces, isEmpty);
      expect(
        document.warnings.join('\n'),
        allOf(
          contains('KHR_draco_mesh_compression'),
          contains('did not decode: '),
          // Which of the decoder's checks fires depends on where the cut
          // falls; that it names running out of stream does not.
          contains('past the end'),
        ),
      );
    });
  });
}
