import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import '../asset_resolver.dart';
import '../model_document.dart';
import '../model_loader.dart';
import '../plain_model_document.dart';

/// How a facet's normal is chosen.
enum StlNormals {
  /// The facet's own normal record — unless it is the zero vector, which a
  /// surprising number of exporters write instead of computing one, in which
  /// case this falls back to the triangle's own cross product for that facet
  /// alone rather than leaving a NaN in the mesh.
  fromFile,

  /// Always the cross product of the triangle's own edges, ignoring whatever
  /// the file recorded. STL has no shared vertices to smooth across, so this
  /// is never a worse answer than the file's own normal and is sometimes a
  /// better one — a mesh assembled by hand or converted through a lossy tool
  /// can have facets whose recorded normal simply disagrees with its winding.
  recomputed,
}

/// True when [bytes] is a binary STL file.
///
/// **The one check that actually distinguishes the two dialects.** An ASCII
/// file always starts with `solid`, and so — misleadingly — does a binary
/// one: the format's 80-byte header is free text, and most binary exporters
/// write `solid <name>` into it out of habit. Reading a binary file as text
/// on the strength of that prefix is a real, repeated bug in other STL
/// readers. The only fact that cannot lie is the size: a binary file is
/// exactly its header plus 50 bytes a facet, and an ASCII file — being text
/// with a facet spelled out in words — never lands on that number by
/// accident at any real triangle count.
bool isBinaryStl(Uint8List bytes) {
  if (bytes.length < 84) return false;
  final count = ByteData.sublistView(bytes, 80, 84).getUint32(0, Endian.little);
  return bytes.length == 84 + 50 * count;
}

/// True when [bytes] looks like the text dialect: `solid` (any case), once
/// leading whitespace is skipped.
///
/// Checked only after [isBinaryStl] says no — see that function's doc comment
/// for why the order matters.
bool looksLikeAsciiStl(Uint8List bytes) {
  var i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) break;
    i++;
  }
  if (i + 5 > bytes.length) return false;
  return String.fromCharCodes(bytes, i, i + 5).toLowerCase() == 'solid';
}

/// Decodes STL, binary or ASCII.
///
/// **A triangle soup, and the decoded mesh stays one.** STL vertices are not
/// shared between facets — each of a file's triangles is thirty-six bytes (or
/// three `vertex` lines) with no index into anything — so there is nothing to
/// deduplicate and no smooth-normal question the way OBJ has one: a facet's
/// normal is exactly the one number the format gives it. [layout]'s
/// `texcoord`/`tangent`/`color` slots, when requested, get [MeshBuilder]'s own
/// neutral values, since the format carries none of the three.
final class StlLoader implements ModelDecoder {
  StlLoader({
    this.layout = VertexLayout.standard,
    this.normals = StlNormals.fromFile,
  });

  final VertexLayout layout;
  final StlNormals normals;

  @override
  bool handles(String fileName, Uint8List bytes) =>
      fileName.toLowerCase().endsWith('.stl') ||
      isBinaryStl(bytes) ||
      looksLikeAsciiStl(bytes);

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) => load(bytes);

  /// Reads [bytes], choosing the dialect the same way [isBinaryStl] does.
  ///
  /// No `resolveUri` parameter: a `.stl` file is always one self-contained
  /// blob, unlike glTF's buffers or OBJ's material library.
  Future<ModelDocument> load(Uint8List bytes) async =>
      isBinaryStl(bytes) ? _decodeBinary(bytes) : _decodeAscii(bytes);

  ModelDocument _finish(MeshBuilder builder, int degenerateNormals) {
    final degenerateWarning =
        '$degenerateNormals facet(s) had a zero-length normal; recomputed '
        'from the triangle instead.';
    final warnings = <String>[if (degenerateNormals > 0) degenerateWarning];
    return PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: builder.build(),
          transform: Matrix4.identity(),
          // The format structurally carries a normal for every facet — never
          // absent the way OBJ's `vn` can be — so it counts as authored even
          // on the facets this loader had to recompute one for.
          authoredAttributes: const <String>{'position', 'normal'},
        ),
      ],
      warnings: warnings,
    );
  }

  Vector3 _normalFor(Vector3 fileNormal, Vector3 a, Vector3 b, Vector3 c) {
    if (normals == StlNormals.fromFile && fileNormal.length2 > 0.0) {
      return fileNormal.normalized();
    }
    final cross = (b - a).cross(c - a);
    return cross.length2 > 0.0 ? cross.normalized() : Vector3(0.0, 0.0, 1.0);
  }

  ModelDocument _decodeBinary(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final count = view.getUint32(80, Endian.little);
    final builder = MeshBuilder(
      layout,
      reserveVertices: count * 3,
      reserveIndices: count * 3,
    );

    Vector3 vec3At(int offset) => Vector3(
      view.getFloat32(offset, Endian.little),
      view.getFloat32(offset + 4, Endian.little),
      view.getFloat32(offset + 8, Endian.little),
    );

    var degenerateNormals = 0;
    var offset = 84;
    for (var i = 0; i < count; i++) {
      final fileNormal = vec3At(offset);
      final a = vec3At(offset + 12);
      final b = vec3At(offset + 24);
      final c = vec3At(offset + 36);
      offset += 50;

      if (normals == StlNormals.fromFile && fileNormal.length2 == 0.0) {
        degenerateNormals++;
      }
      final normal = _normalFor(fileNormal, a, b, c);
      final texcoord = Vector2.zero();
      final i0 = builder.addVertex(
        position: a,
        normal: normal,
        texcoord: texcoord,
      );
      final i1 = builder.addVertex(
        position: b,
        normal: normal,
        texcoord: texcoord,
      );
      final i2 = builder.addVertex(
        position: c,
        normal: normal,
        texcoord: texcoord,
      );
      builder.addTriangle(i0, i1, i2);
    }

    return _finish(builder, degenerateNormals);
  }

  ModelDocument _decodeAscii(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final tokens = text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final builder = MeshBuilder(layout);

    var degenerateNormals = 0;
    var i = 0;
    double number() => double.parse(tokens[i++]);

    while (i < tokens.length) {
      if (tokens[i].toLowerCase() != 'facet') {
        i++;
        continue;
      }
      i++; // 'facet'
      i++; // 'normal'
      final fileNormal = Vector3(number(), number(), number());
      i++; // 'outer'
      i++; // 'loop'

      final vertices = <Vector3>[];
      for (var v = 0; v < 3; v++) {
        i++; // 'vertex'
        vertices.add(Vector3(number(), number(), number()));
      }
      i++; // 'endloop'
      i++; // 'endfacet'

      if (normals == StlNormals.fromFile && fileNormal.length2 == 0.0) {
        degenerateNormals++;
      }
      final normal = _normalFor(
        fileNormal,
        vertices[0],
        vertices[1],
        vertices[2],
      );
      final texcoord = Vector2.zero();
      final indices = <int>[
        for (final vertex in vertices)
          builder.addVertex(
            position: vertex,
            normal: normal,
            texcoord: texcoord,
          ),
      ];
      builder.addTriangle(indices[0], indices[1], indices[2]);
    }

    return _finish(builder, degenerateNormals);
  }
}
