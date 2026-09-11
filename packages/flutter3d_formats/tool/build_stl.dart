/// Writes the five fixtures `test/fixtures/stl/` holds, so how they were made
/// is on the record rather than only their bytes.
///
///     dart run tool/build_stl.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

typedef _Triangle = (Vector3 a, Vector3 b, Vector3 c);

Vector3 _faceNormal(_Triangle t) =>
    (t.$2 - t.$1).cross(t.$3 - t.$1).normalized();

/// Four faces, sharing no vertices — a real STL soup, however small.
List<_Triangle> _tetrahedron() {
  final v0 = Vector3(0, 0, 0);
  final v1 = Vector3(1, 0, 0);
  final v2 = Vector3(0, 1, 0);
  final v3 = Vector3(0, 0, 1);
  return <_Triangle>[(v0, v2, v1), (v0, v1, v3), (v0, v3, v2), (v1, v2, v3)];
}

/// Twelve faces, two a side.
List<_Triangle> _cube() {
  Vector3 p(double x, double y, double z) => Vector3(x, y, z);
  final corners = <String, Vector3>{
    'lbb': p(0, 0, 0),
    'rbb': p(1, 0, 0),
    'ltb': p(0, 1, 0),
    'rtb': p(1, 1, 0),
    'lbf': p(0, 0, 1),
    'rbf': p(1, 0, 1),
    'ltf': p(0, 1, 1),
    'rtf': p(1, 1, 1),
  };
  Vector3 c(String name) => corners[name]!;
  List<_Triangle> quad(String a, String b, String cc, String d) => <_Triangle>[
    (c(a), c(b), c(cc)),
    (c(a), c(cc), c(d)),
  ];
  return <_Triangle>[
    ...quad('lbb', 'rbb', 'rtb', 'ltb'), // back
    ...quad('lbf', 'ltf', 'rtf', 'rbf'), // front
    ...quad('lbb', 'ltb', 'ltf', 'lbf'), // left
    ...quad('rbb', 'rbf', 'rtf', 'rtb'), // right
    ...quad('ltb', 'rtb', 'rtf', 'ltf'), // top
    ...quad('lbb', 'lbf', 'rbf', 'rbb'), // bottom
  ];
}

Uint8List _binary(
  List<_Triangle> triangles, {
  Set<int> zeroNormalAt = const {},
}) {
  final bytes = Uint8List(84 + 50 * triangles.length);
  final view = ByteData.sublistView(bytes);
  // The 80-byte header is free text; naming the generator is the convention.
  bytes.setRange(0, 22, 'flutter3d build_stl.dart'.codeUnits);
  view.setUint32(80, triangles.length, Endian.little);

  var offset = 84;
  for (var i = 0; i < triangles.length; i++) {
    final t = triangles[i];
    final normal = zeroNormalAt.contains(i) ? Vector3.zero() : _faceNormal(t);
    void putVec3(Vector3 v) {
      view.setFloat32(offset, v.x, Endian.little);
      view.setFloat32(offset + 4, v.y, Endian.little);
      view.setFloat32(offset + 8, v.z, Endian.little);
      offset += 12;
    }

    putVec3(normal);
    putVec3(t.$1);
    putVec3(t.$2);
    putVec3(t.$3);
    view.setUint16(offset, 0, Endian.little); // attribute byte count
    offset += 2;
  }
  return bytes;
}

String _ascii(List<_Triangle> triangles, {String name = 'model'}) {
  final buffer = StringBuffer('solid $name\n');
  for (final t in triangles) {
    final n = _faceNormal(t);
    buffer.writeln('  facet normal ${n.x} ${n.y} ${n.z}');
    buffer.writeln('    outer loop');
    for (final v in <Vector3>[t.$1, t.$2, t.$3]) {
      buffer.writeln('      vertex ${v.x} ${v.y} ${v.z}');
    }
    buffer.writeln('    endloop');
    buffer.writeln('  endfacet');
  }
  buffer.writeln('endsolid $name');
  return buffer.toString();
}

void main() {
  const dir = 'test/fixtures/stl';
  Directory(dir).createSync(recursive: true);

  void write(String name, Object bytes) {
    final file = File('$dir/$name');
    if (bytes is String) {
      file.writeAsStringSync(bytes);
    } else {
      file.writeAsBytesSync(bytes as Uint8List);
    }
    stderr.writeln('wrote $dir/$name');
  }

  write('tetrahedron.stl', _binary(_tetrahedron()));
  write('tetrahedron_ascii.stl', _ascii(_tetrahedron(), name: 'tetrahedron'));
  write('cube.stl', _binary(_cube()));
  write(
    'degenerate_normals.stl',
    _binary(_tetrahedron(), zeroNormalAt: <int>{0, 2}),
  );
  // Uppercase keywords and no name after `solid`/`endsolid`, both legal —
  // exercising the parts of the grammar a lenient reader has to accept even
  // though every generator here happens to write the tidy form.
  write('single_triangle_shouting.stl', '''
SOLID
  FACET NORMAL 0 0 1
    OUTER LOOP
      VERTEX 0 0 0
      VERTEX 1 0 0
      VERTEX 0 1 0
    ENDLOOP
  ENDFACET
ENDSOLID
''');
}
