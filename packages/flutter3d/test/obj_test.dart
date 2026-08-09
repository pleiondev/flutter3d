import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter3d/src/engine/assets/obj/obj.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';

Uint8List obj(String text) => Uint8List.fromList(utf8.encode(text));

Vector3 normalAt(MeshData mesh, int index) {
  final offset = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
  final base = index * mesh.layout.floatsPerVertex + offset;
  return Vector3(
    mesh.vertices[base],
    mesh.vertices[base + 1],
    mesh.vertices[base + 2],
  );
}

Vector2 texcoordAt(MeshData mesh, int index) {
  final offset = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
  final base = index * mesh.layout.floatsPerVertex + offset;
  return Vector2(mesh.vertices[base], mesh.vertices[base + 1]);
}

void main() {
  group('faces and indexing', () {
    test('parses a triangle with 1-based indices', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
'''));
      final mesh = document.surfaces.single.mesh;
      expect(mesh.vertexCount, 3);
      expect(mesh.triangleCount, 1);
      expect(document.warnings, isEmpty);
    });

    test('accepts multiple spaces between tokens', () async {
      // The Utah teapot is written this way: "f  457 458 459".
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f  1  2   3
'''));
      expect(document.surfaces.single.mesh.triangleCount, 1);
    });

    test('resolves negative indices relative to the end', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f -3 -2 -1
'''));
      final mesh = document.surfaces.single.mesh;
      expect(mesh.triangleCount, 1);
      expect(mesh.positionAt(0), Vector3(0.0, 0.0, 0.0));
    });

    test('fans a quad into two triangles', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
f 1 2 3 4
'''));
      expect(document.surfaces.single.mesh.triangleCount, 2);
    });

    test('fans an n-gon', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 2 1 0
v 1 2 0
v 0 2 0
f 1 2 3 4 5
'''));
      expect(document.surfaces.single.mesh.triangleCount, 3);
    });

    test('reads all four face vertex forms', () async {
      for (final face in <String>[
        'f 1 2 3',
        'f 1/1 2/2 3/3',
        'f 1//1 2//2 3//3',
        'f 1/1/1 2/2/2 3/3/3',
      ]) {
        final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
vt 0 0
vt 1 0
vt 0 1
vn 0 0 1
vn 0 0 1
vn 0 0 1
$face
'''));
        expect(
          document.surfaces.single.mesh.triangleCount,
          1,
          reason: face,
        );
      }
    });

    test('shares vertices between faces that reference the same triple',
        () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
f 1 2 3
f 1 3 4
'''));
      final mesh = document.surfaces.single.mesh;
      // Four positions, two triangles: the shared edge must not be duplicated.
      expect(mesh.vertexCount, 4);
      expect(mesh.triangleCount, 2);
    });

    test('splits a vertex when its texcoord differs', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
vt 0 0
vt 1 1
f 1/1 2/1 3/1
f 1/2 2/2 3/2
'''));
      // Same positions but different UVs, so the triple is different and the
      // vertices cannot be shared.
      expect(document.surfaces.single.mesh.vertexCount, 6);
    });

    test('reports a malformed face without failing the file', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 nonsense
f 1 2 3
'''));
      expect(document.surfaces.single.mesh.triangleCount, 1);
      expect(document.warnings.any((w) => w.contains('nonsense')), isTrue);
    });

    test('an out-of-range index is refused, not clamped', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 99
'''));
      expect(document.surfaces, isEmpty);
      expect(document.warnings, isNotEmpty);
    });
  });

  group('normals', () {
    test('uses the file normals when present', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
vn 1 0 0
f 1//1 2//1 3//1
'''));
      final mesh = document.surfaces.single.mesh;
      expect(normalAt(mesh, 0), Vector3(1.0, 0.0, 0.0));
    });

    test('generates smooth normals by default', () async {
      // Two triangles meeting at a right angle: the shared vertices must average
      // the two face normals rather than pick one.
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
v 1 0 -1
v 1 1 -1
f 1 2 3
f 1 3 4
f 2 5 6
f 2 6 3
'''));
      final mesh = document.surfaces.single.mesh;
      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(normalAt(mesh, i).length, closeTo(1.0, 1e-4));
      }
      // The vertex shared by both planes points between them.
      final position = Vector3.zero();
      var foundBlended = false;
      for (var i = 0; i < mesh.vertexCount; i++) {
        mesh.positionAt(i, position);
        if ((position - Vector3(1.0, 0.0, 0.0)).length < 1e-6) {
          final n = normalAt(mesh, i);
          if (n.z.abs() > 0.1 && n.x.abs() > 0.1) foundBlended = true;
        }
      }
      expect(foundBlended, isTrue);
    });

    test('flat mode splits vertices and gives one normal per face', () async {
      final document = await ObjLoader(normals: ObjNormals.flat).load(obj('''
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
f 1 2 3
f 1 3 4
'''));
      final mesh = document.surfaces.single.mesh;
      expect(mesh.vertexCount, 6, reason: 'de-indexed for flat shading');
      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(normalAt(mesh, i), Vector3(0.0, 0.0, 1.0));
      }
    });

    test('none mode leaves normals at zero', () async {
      final document = await ObjLoader(normals: ObjNormals.none).load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
'''));
      expect(normalAt(document.surfaces.single.mesh, 0), Vector3.zero());
    });
  });

  group('texcoords', () {
    test('flips V by default, because OBJ origin is bottom-left', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
vt 0.25 0.75
f 1/1 2/1 3/1
'''));
      final uv = texcoordAt(document.surfaces.single.mesh, 0);
      expect(uv.x, closeTo(0.25, 1e-6));
      expect(uv.y, closeTo(0.25, 1e-6), reason: '1 - 0.75');
    });

    test('keeps V when flipping is disabled', () async {
      final document = await ObjLoader(flipTexcoordV: false).load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
vt 0.25 0.75
f 1/1 2/1 3/1
'''));
      expect(texcoordAt(document.surfaces.single.mesh, 0).y, closeTo(0.75, 1e-6));
    });
  });

  group('groups and materials', () {
    test('splits surfaces on g', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
g first
f 1 2 3
g second
f 3 2 1
'''));
      expect(document.surfaces, hasLength(2));
      expect(document.surfaces[0].name, 'first');
      expect(document.surfaces[1].name, 'second');
    });

    test('merges everything when splitting is disabled', () async {
      final document = await ObjLoader(splitByGroup: false).load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
g first
f 1 2 3
g second
f 3 2 1
'''));
      expect(document.surfaces, hasLength(1));
      expect(document.surfaces.single.mesh.triangleCount, 2);
    });

    test('consecutive g and usemtl do not create an empty surface', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
g only
usemtl red
f 1 2 3
'''));
      expect(document.surfaces, hasLength(1));
    });

    test('material libraries reach the shared abstraction', () async {
      const mtl = '''
newmtl red
Kd 0.8 0.1 0.1
Ks 0.2 0.2 0.2
Ns 250
d 0.5
''';
      final document = await ObjLoader().load(
        obj('''
mtllib palette.mtl
v 0 0 0
v 1 0 0
v 0 1 0
usemtl red
f 1 2 3
'''),
        resolveUri: (uri) async {
          expect(uri, 'palette.mtl');
          return Uint8List.fromList(utf8.encode(mtl));
        },
      );

      expect(document.materials, hasLength(1));
      final material = document.materials.single;
      // The same SurfaceMaterial type the glTF decoder produces.
      expect(material.name, 'red');
      expect(material.baseColor.x, closeTo(0.8, 1e-6));
      expect(material.baseColor.w, closeTo(0.5, 1e-6));
      // Ns 250 of 1000 maps to a fairly smooth surface.
      expect(material.roughness, closeTo(0.75, 1e-6));
      expect(material.alphaMode, SurfaceAlphaMode.blend);
      expect(document.surfaces.single.materialIndex, 0);
    });

    test('a missing library is a warning, not a failure', () async {
      final document = await ObjLoader().load(obj('''
mtllib absent.mtl
v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
'''));
      expect(document.surfaces, hasLength(1));
      expect(document.warnings, isNotEmpty);
    });

    test('usemtl naming an undefined material is reported', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
usemtl ghost
f 1 2 3
'''));
      expect(document.surfaces.single.materialIndex, isNull);
      expect(document.warnings.any((w) => w.contains('ghost')), isTrue);
    });
  });

  group('mtl parsing', () {
    test('reads the fields we map', () {
      final materials = parseMtl('''
# a comment
newmtl shiny
Kd 0.1 0.2 0.3
Ks 1 1 1
Ns 900
map_Kd wood.png

newmtl plain
Tr 0.25
''');
      expect(materials, hasLength(2));
      expect(materials['shiny']!.diffuse!.y, closeTo(0.2, 1e-6));
      expect(materials['shiny']!.diffuseTexturePath, 'wood.png');
      // A bright neutral Ks is the only metalness hint OBJ offers.
      expect(materials['shiny']!.approximateMetallic, greaterThan(0.0));
      // Tr is the complement of opacity.
      expect(materials['plain']!.opacity, closeTo(0.75, 1e-6));
    });

    test('a high Phong exponent reads as smooth', () {
      final rough = parseMtl('newmtl a\nNs 0\n')['a']!;
      final smooth = parseMtl('newmtl a\nNs 1000\n')['a']!;
      expect(rough.approximateRoughness, greaterThan(smooth.approximateRoughness));
    });
  });

  group('robustness', () {
    test('ignores comments, blank lines and unknown directives', () async {
      final document = await ObjLoader().load(obj('''
# teapot

v 0 0 0
v 1 0 0
v 0 1 0
s off
weird_directive 1 2 3
f 1 2 3
'''));
      expect(document.surfaces.single.mesh.triangleCount, 1);
      expect(
        document.warnings.any((w) => w.contains('weird_directive')),
        isTrue,
      );
      // `s` is valid OBJ we deliberately ignore, so it must not be reported.
      expect(document.warnings.any((w) => w.contains(' s')), isFalse);
    });

    test('joins backslash continuation lines', () async {
      final document = await ObjLoader().load(obj('''
v 0 0 0
v 1 0 0
v 0 1 0
f 1 \\
2 3
'''));
      expect(document.surfaces.single.mesh.triangleCount, 1);
    });

    test('an empty file reports no triangles instead of throwing', () async {
      final document = await ObjLoader().load(obj('# nothing here\n'));
      expect(document.surfaces, isEmpty);
      expect(document.warnings, isNotEmpty);
    });
  });

  group('the Utah teapot', () {
    late ObjDocument teapot;

    setUpAll(() async {
      final bytes = File('assets/samples/teapot.obj').readAsBytesSync();
      teapot = await ObjLoader().load(bytes);
    });

    test('decodes every face', () {
      // The file declares 1202 vertices and 2256 triangular faces.
      expect(teapot.triangleCount, 2256);
      expect(teapot.surfaces, isNotEmpty);
    });

    test('is split by its g groups', () {
      // Four `g` records, though the first may precede any face.
      expect(teapot.surfaces.length, inInclusiveRange(1, 4));
    });

    test('has unit-length generated normals', () {
      // The file carries no `vn`, so every normal here was computed.
      for (final surface in teapot.surfaces) {
        final mesh = surface.mesh;
        for (var i = 0; i < mesh.vertexCount; i++) {
          expect(normalAt(mesh, i).length, closeTo(1.0, 1e-3));
        }
      }
    });

    test('generated normals agree with the faces that produced them', () {
      // The meaningful property of area-weighted averaging, and one that does not
      // depend on the model's shape: every vertex normal must sit on the same
      // side as each face touching it. A sign error in the accumulation would
      // invert the lot.
      //
      // A radial "points outward" check was tried first and is a poor test here:
      // the spout and handle genuinely face inward relative to the body axis, so
      // it measures the teapot's silhouette rather than the code.
      final a = Vector3.zero();
      final b = Vector3.zero();
      final c = Vector3.zero();
      final faceNormal = Vector3.zero();
      var checked = 0;

      for (final surface in teapot.surfaces) {
        final mesh = surface.mesh;
        for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
          final i0 = mesh.indices[i];
          final i1 = mesh.indices[i + 1];
          final i2 = mesh.indices[i + 2];
          mesh.positionAt(i0, a);
          mesh.positionAt(i1, b);
          mesh.positionAt(i2, c);
          (b - a).crossInto(c - a, faceNormal);
          if (faceNormal.length2 < 1e-16) continue; // degenerate sliver
          faceNormal.normalize();

          for (final index in <int>[i0, i1, i2]) {
            expect(
              normalAt(mesh, index).dot(faceNormal),
              greaterThan(0.0),
              reason: 'vertex $index of triangle ${i ~/ 3}',
            );
            checked++;
          }
        }
      }

      expect(checked, greaterThan(6000));
    });

    test('has sensible bounds', () {
      final bounds = teapot.computeBounds();
      expect(bounds.max.x - bounds.min.x, greaterThan(0.0));
      expect(bounds.max.y - bounds.min.y, greaterThan(0.0));
      expect(bounds.min.y, lessThan(bounds.max.y));
      for (final value in <double>[
        bounds.min.x,
        bounds.min.y,
        bounds.min.z,
        bounds.max.x,
        bounds.max.y,
        bounds.max.z,
      ]) {
        expect(value.isFinite, isTrue);
      }
    });

    test('carries no materials, so surfaces have no material index', () {
      expect(teapot.materials, isEmpty);
      for (final surface in teapot.surfaces) {
        expect(surface.materialIndex, isNull);
      }
    });
  });
}
