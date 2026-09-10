/// The OBJ writer, checked mostly by handing what it writes straight back to
/// the loader beside it.
///
/// **The round trip is the test and the rest are its corners.** An OBJ writer
/// fails in ways that reading the output does not reveal — a face index off by
/// the length of the previous mesh still parses, a `vt` stream that has drifted
/// out of step still parses, an inverted winding still parses — so asserting on
/// the text proves only that the text is well formed. Reading it back with
/// `ObjLoader` and comparing positions, texture coordinates, triangle counts
/// and the sign of the signed volume is what puts the two halves in the same
/// sentence.
///
/// Every mutation named in a comment below was applied to `obj_writer.dart`,
/// run, and watched to fail before being put back.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_formats/src/obj/obj_writer.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A document assembled by hand, which is the only kind this writer needs: it
/// takes a [ModelDocument] and nothing about it cares which decoder built one.
final class _Document extends ModelDocument {
  _Document({
    required this.surfaces,
    this.materials = const <SurfaceMaterial>[],
    this.images = const <EncodedImage>[],
  });

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<SurfaceMaterial> materials;

  @override
  final List<EncodedImage> images;

  @override
  final List<String> warnings = const <String>[];
}

/// A triangle at [origin], with distinct UVs per corner so a texture-coordinate
/// index that has slipped shows up as a wrong number rather than as a
/// coincidence.
MeshData _triangle(
  Vector3 origin, {
  VertexLayout layout = VertexLayout.positionNormalTexcoord,
}) {
  final builder = MeshBuilder(layout, reserveVertices: 3, reserveIndices: 3);
  const uvs = <List<double>>[
    <double>[0.125, 0.25],
    <double>[0.5, 0.75],
    <double>[0.875, 0.375],
  ];
  const offsets = <List<double>>[
    <double>[0.0, 0.0, 0.0],
    <double>[1.0, 0.0, 0.0],
    <double>[0.0, 1.0, 0.0],
  ];

  for (var i = 0; i < 3; i++) {
    builder.addVertex(
      position: Vector3(
        origin.x + offsets[i][0],
        origin.y + offsets[i][1],
        origin.z + offsets[i][2],
      ),
      normal: Vector3(0.0, 0.0, 1.0),
      texcoord: Vector2(uvs[i][0], uvs[i][1]),
    );
  }
  builder.addTriangle(0, 1, 2);
  return builder.build();
}

/// Reads back what a writer produced, resolving the `.mtl` from memory so no
/// file system is involved.
Future<ObjDocument> _roundTrip(ObjWriter writer) {
  final mtl = writer.writeMaterialLibrary();
  return ObjLoader().load(
    writer.write(),
    resolveUri: (request) async {
      if (request.uri == writer.materialLibraryName && mtl != null) return mtl;
      throw StateError('nothing to resolve "${request.uri}" against');
    },
  );
}

String _text(ObjWriter writer) => utf8.decode(writer.write());

/// Every position in a document, in the order its surfaces and vertices give
/// them. Comparing these rather than raw floats keeps the assertions readable
/// when one is wrong.
List<Vector3> _positions(ModelDocument document) => <Vector3>[
  for (final surface in document.surfaces)
    for (var v = 0; v < surface.mesh.vertexCount; v++)
      surface.mesh.positionAt(v),
];

Matcher _near(Vector3 expected) => predicate<Vector3>(
  (actual) => (actual - expected).length < 1e-4,
  'within 1e-4 of $expected',
);

void main() {
  group('running indices across several meshes', () {
    // The headline case, and the reason the fixture has three surfaces rather
    // than one: OBJ numbers vertices per file, not per object, so a writer that
    // restarts at 1 for each `o` produces a file that opens as one mesh with
    // the faces of the first. A single-mesh test cannot see it, because for one
    // mesh the two behaviours are identical.
    test('three meshes come back as three meshes in the right places', () async {
      final origins = <Vector3>[
        Vector3(0.0, 0.0, 0.0),
        Vector3(10.0, 0.0, 0.0),
        Vector3(0.0, 20.0, -5.0),
      ];
      final document = _Document(
        surfaces: <ModelSurface>[
          for (var i = 0; i < origins.length; i++)
            ModelSurface(mesh: _triangle(origins[i]), name: 'part_$i'),
        ],
      );

      final writer = ObjWriter(document);
      final reread = await _roundTrip(writer);

      expect(reread.surfaces, hasLength(3));
      expect(reread.triangleCount, 3);
      expect(reread.surfaces.map((s) => s.name), <String>[
        'part_0',
        'part_1',
        'part_2',
      ]);

      // Mutation: dropping `positionBase += mesh.vertexCount` makes every face
      // in the file address the first triangle. The loader then reads three
      // surfaces whose positions are all the first one's, and this failed at
      // `position 3`, expecting `within 1e-4 of [10.0,0.0,0.0]` and finding
      // `Vector3:<[0.0,0.0,0.0]>`.
      final expected = <Vector3>[
        for (final origin in origins) ...<Vector3>[
          origin,
          origin + Vector3(1.0, 0.0, 0.0),
          origin + Vector3(0.0, 1.0, 0.0),
        ],
      ];
      final actual = _positions(reread);
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i], _near(expected[i]), reason: 'position $i');
      }
    });

    test('a mesh without texture coordinates does not desync the vt run', () async {
      // Positions survive a shared counter; texture coordinates are what a
      // shared counter destroys, and only from the surface *after* the one that
      // skipped an attribute. Hence the middle surface having no UVs and the
      // assertion falling on the last.
      final document = _Document(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: _triangle(Vector3.zero()), name: 'mapped'),
          ModelSurface(
            mesh: _triangle(
              Vector3(5.0, 0.0, 0.0),
              layout: VertexLayout.positionNormal,
            ),
            name: 'bare',
          ),
          ModelSurface(
            mesh: _triangle(Vector3(0.0, 5.0, 0.0)),
            name: 'mapped2',
          ),
        ],
      );

      final reread = await _roundTrip(ObjWriter(document));
      expect(reread.surfaces, hasLength(3));

      // This is also where the V flip is pinned: writing `t` instead of
      // `1 - t` failed here on `within <0.00001> of <0.25>` finding `<0.75>`,
      // which is what an upside-down texture looks like as a number.
      //
      // Mutation: advancing one shared counter by `vertexCount` per surface
      // instead of three separate ones sends the last surface's `vt` indices to
      // 7, 8 and 9 when only six exist. `_resolveIndex` returns null for those,
      // the loader falls back to a zero UV, and the first expectation below
      // failed on `a numeric value within <0.00001> of <0.125>` finding `<0.0>`.
      final last = reread.surfaces.last.mesh;
      final uvOffset = last.layout.floatOffsetOf(VertexLayout.texcoord.name);
      final stride = last.layout.floatsPerVertex;
      // Written flipped and read flipped, so the values come back as authored.
      const authored = <List<double>>[
        <double>[0.125, 0.25],
        <double>[0.5, 0.75],
        <double>[0.875, 0.375],
      ];
      for (var v = 0; v < 3; v++) {
        final o = v * stride + uvOffset;
        expect(last.vertices[o], closeTo(authored[v][0], 1e-5));
        expect(last.vertices[o + 1], closeTo(authored[v][1], 1e-5));
      }
    });
  });

  group('optional attributes', () {
    test('a mesh with no normals writes no vn and no empty field', () {
      final document = _Document(
        surfaces: <ModelSurface>[
          ModelSurface(
            mesh: _triangle(Vector3.zero(), layout: VertexLayout.positionOnly),
          ),
        ],
      );

      final text = _text(ObjWriter(document));

      expect(text, isNot(contains('vn ')));
      expect(text, isNot(contains('vt ')));
      // Two mutations, one each. Returning `'$position/vt/vn'` from `corner`
      // unconditionally wrote `1/1/1` and failed on `not contains '/'`;
      // returning `'$position//vn'` wrote `1//1` and failed on
      // `not contains '//'`. Neither assertion covers the other.
      expect(text, isNot(contains('//')));
      expect(text, isNot(contains('/')));
      expect(
        text.split('\n').where((line) => line.startsWith('f ')).single,
        'f 1 2 3',
      );
    });

    test('normals that are zero throughout count as absent', () {
      // `ObjLoader` writes a zero normal exactly where the file had no `vn`, so
      // a mesh whose normals are all zero has none. Writing `vn 0 0 0` out
      // would make the reader believe in them and skip the smoothing pass that
      // would otherwise give the model normals back.
      final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
      for (final corner in <Vector3>[
        Vector3(0.0, 0.0, 0.0),
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
      ]) {
        builder.addVertex(
          position: corner,
          normal: Vector3.zero(),
          texcoord: Vector2.zero(),
        );
      }
      builder.addTriangle(0, 1, 2);

      final writer = ObjWriter(
        _Document(
          surfaces: <ModelSurface>[ModelSurface(mesh: builder.build())],
        ),
      );

      // Mutation: returning `offset` from `_usedOffset` without the all-zero
      // scan writes three `vn 0 0 0` and three `vt 0 0`; the first expectation
      // below then failed on `not contains 'vn '`.
      expect(_text(writer), isNot(contains('vn ')));
      expect(_text(writer), isNot(contains('vt ')));
    });
  });

  group('winding and handedness', () {
    test('a closed box keeps the sign of its signed volume', () async {
      final box = CuboidShape(
        size: Vector3(2.0, 1.0, 3.0),
      ).build(layout: VertexLayout.positionNormalTexcoord);
      expect(box.signedVolume(), greaterThan(0.0));

      final reread = await _roundTrip(
        ObjWriter(_Document(surfaces: <ModelSurface>[ModelSurface(mesh: box)])),
      );

      expect(reread.triangleCount, box.triangleCount);
      // Mutation: writing the corners as `c b a` unconditionally turns the
      // volume negative here, i.e. a model that culls inside out. It printed
      // -6.0 against the 6.0 below.
      expect(reread.surfaces.single.mesh.signedVolume(), closeTo(6.0, 1e-3));
    });

    test('a mirroring transform is baked and the faces reversed with it', () async {
      final box = CuboidShape(
        size: Vector3(2.0, 1.0, 3.0),
      ).build(layout: VertexLayout.positionNormalTexcoord);
      final mirror = Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0);
      expect(mirror.determinant(), lessThan(0.0));

      final reread = await _roundTrip(
        ObjWriter(
          _Document(
            surfaces: <ModelSurface>[
              ModelSurface(mesh: box, transform: mirror, flipWinding: true),
            ],
          ),
        ),
      );

      // Mirroring the positions without reversing the index order leaves a box
      // wound inside out, which is the bug `flipWinding` exists to describe and
      // which cannot survive being written to a format that has no transform to
      // hang it on.
      //
      // Two mutations, both printing `<-6.0>` against the 6.0 below: hard-coding
      // `reversed = false`, and having `_bake` return `surface.mesh` untouched
      // so the mirror is never applied and the box keeps the winding it had for
      // geometry it no longer has.
      expect(reread.surfaces.single.mesh.signedVolume(), closeTo(6.0, 1e-3));
      // The mirror really was applied, so this is not passing by doing nothing.
      expect(
        reread.surfaces.single.mesh.computeBounds().min.x,
        closeTo(-1.0, 1e-4),
      );
    });
  });

  group('materials', () {
    SurfaceMaterial material(String? name, {double roughness = 0.25}) =>
        SurfaceMaterial(
          name: name,
          baseColor: Vector4(0.25, 0.5, 0.75, 1.0),
          roughness: roughness,
        );

    test('two materials sharing a name stay two materials', () async {
      // Ordinary in an exported scene, and fatal without the uniquing pass: a
      // `.mtl` library is a map keyed by `newmtl`, so the second entry would
      // replace the first and every surface using the first would draw with the
      // second's parameters.
      final document = _Document(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: _triangle(Vector3.zero()), materialIndex: 0),
          ModelSurface(
            mesh: _triangle(Vector3(4.0, 0.0, 0.0)),
            materialIndex: 1,
          ),
        ],
        materials: <SurfaceMaterial>[
          material('Material', roughness: 0.25),
          material('Material', roughness: 0.75),
        ],
      );

      final reread = await _roundTrip(ObjWriter(document));

      // Mutation: dropping the uniquing loop from `_buildMaterialNames` writes
      // `newmtl Material` twice; the library keeps whichever came last, and the
      // length below failed as `an object with length of <2>` against a single
      // `SurfaceMaterial(Material, metallic: 0.0, roughness: 0.75)` — the first
      // material's 0.25 gone and both surfaces pointing at the second.
      expect(reread.materials, hasLength(2));
      final byIndex = reread.surfaces
          .map((s) => reread.materials[s.materialIndex!])
          .toList();
      expect(byIndex[0].roughness, closeTo(0.25, 1e-3));
      expect(byIndex[1].roughness, closeTo(0.75, 1e-3));
      expect(byIndex[0].baseColor.r, closeTo(0.25, 1e-5));
      expect(byIndex[1].baseColor.b, closeTo(0.75, 1e-5));
    });

    test('a surface with no material does not inherit the previous one', () async {
      // `usemtl` is sticky and `ObjLoader` honours that, so writing nothing for
      // an unmaterialled surface hands it whatever the surface above used.
      final document = _Document(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: _triangle(Vector3.zero()), materialIndex: 0),
          ModelSurface(mesh: _triangle(Vector3(4.0, 0.0, 0.0))),
        ],
        materials: <SurfaceMaterial>[material('painted')],
      );

      final reread = await _roundTrip(ObjWriter(document));

      expect(reread.surfaces, hasLength(2));
      expect(reread.surfaces[0].materialIndex, 0);
      // Mutation: removing the bare `usemtl` branch left this expecting `null`
      // and finding `<0>` — the second surface wearing the first one's paint.
      expect(reread.surfaces[1].materialIndex, isNull);
    });

    test('no materials means no library and no mtllib line', () {
      final writer = ObjWriter(
        _Document(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: _triangle(Vector3.zero())),
          ],
        ),
      );

      expect(writer.writeMaterialLibrary(), isNull);
      expect(_text(writer), isNot(contains('mtllib')));
      expect(_text(writer), isNot(contains('usemtl')));
    });

    test('a texture is named only when the image remembers a name', () {
      final withName = ObjWriter(
        _Document(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: _triangle(Vector3.zero()), materialIndex: 0),
          ],
          materials: <SurfaceMaterial>[
            SurfaceMaterial(
              name: 'skin',
              baseColorTexture: const TextureBinding(imageIndex: 0),
            ),
          ],
          images: <EncodedImage>[
            EncodedImage(bytes: Uint8List(0), name: 'skin.png'),
          ],
        ),
      );
      expect(
        utf8.decode(withName.writeMaterialLibrary()!),
        contains('map_Kd skin.png'),
      );

      final anonymous = ObjWriter(
        _Document(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: _triangle(Vector3.zero()), materialIndex: 0),
          ],
          materials: <SurfaceMaterial>[
            SurfaceMaterial(
              name: 'skin',
              baseColorTexture: const TextureBinding(imageIndex: 0),
            ),
          ],
          images: <EncodedImage>[EncodedImage(bytes: Uint8List(0))],
        ),
      );
      expect(
        utf8.decode(anonymous.writeMaterialLibrary()!),
        isNot(contains('map_Kd')),
      );
    });
  });

  group('numbers and the empty document', () {
    test('six decimal places, and trailing zeros trimmed', () {
      final builder = MeshBuilder(VertexLayout.positionOnly);
      builder
        ..addVertex(position: Vector3(0.1234567, 1.0, -0.0))
        ..addVertex(position: Vector3(2.0, 0.0, 0.0))
        ..addVertex(position: Vector3(0.0, 2.0, 0.0));
      builder.addTriangle(0, 1, 2);

      final text = _text(
        ObjWriter(
          _Document(
            surfaces: <ModelSurface>[ModelSurface(mesh: builder.build())],
          ),
        ),
      );

      // float32 rounds 0.1234567 to 0.12345670163631439, so six places gives
      // 0.123457 — the last digit the source could justify.
      expect(text, contains('v 0.123457 1 0\n'));
      expect(text, contains('v 2 0 0\n'));
      // Two mutations. `toStringAsFixed(16)` writes `0.1234567016363144` and
      // `1.0000000000000000`; dropping the trailing-zero trim writes
      // `0.123457 1.000000 0.000000`. Both failed on the first expectation,
      // `contains 'v 0.123457 1 0\n'`.
      expect(text, isNot(contains('0.1234567016')));
    });

    test(
      'a document with no geometry writes an empty file rather than refusing',
      () async {
        // The decision, stated in `ObjWriter`'s doc comment: OBJ can say "no
        // geometry" exactly, so the writer says it instead of inventing a result
        // type. What comes back is the loader's own sentence about it.
        final writer = ObjWriter(_Document(surfaces: <ModelSurface>[]));
        final text = _text(writer);

        expect(
          text.split('\n').where((line) => line.startsWith('v ')),
          isEmpty,
        );
        expect(
          text.split('\n').where((line) => line.startsWith('f ')),
          isEmpty,
        );

        final reread = await _roundTrip(writer);
        expect(reread.surfaces, isEmpty);
        expect(reread.warnings, contains('The file contained no triangles.'));
      },
    );

    test('a surface with no triangles is skipped whole', () async {
      // Otherwise it writes `v` records no face addresses, comes back as
      // nothing, and the surface count fails to round-trip while the file has
      // grown.
      final empty = MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]),
        indices: Uint32List(0),
      );
      final document = _Document(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: empty, name: 'nothing'),
          ModelSurface(mesh: _triangle(Vector3.zero()), name: 'something'),
        ],
      );

      final text = _text(ObjWriter(document));
      final vertexLines = text
          .split('\n')
          .where((line) => line.startsWith('v '));

      // Mutation: neutering the `triangleCount == 0` skip failed both of these
      // — `not contains 'nothing'`, and six `v` records where three belong.
      //
      // What it does *not* break is where the second surface's faces point:
      // `positionBase` advances by the orphan's vertex count too, so the
      // indices stay consistent and the geometry reads back correctly. The cost
      // is the file, and the `o` record for an object that draws nothing. That
      // is the whole claim here; the round trip below is what says the skip
      // costs nothing.
      expect(vertexLines, hasLength(3));
      expect(text, isNot(contains('nothing')));

      final reread = await _roundTrip(ObjWriter(document));
      expect(reread.surfaces, hasLength(1));
      expect(reread.surfaces.single.name, 'something');
      expect(reread.surfaces.single.mesh.positionAt(0), _near(Vector3.zero()));
    });
  });
}
