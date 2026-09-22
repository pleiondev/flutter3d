import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import '../model_document.dart';

/// Encodes any [ModelDocument] as STL, binary or ASCII — `fmt-20`'s own row.
///
/// **One solid, always.** STL has no hierarchy, no materials and no shared
/// vertices between facets, so every surface's own transform is baked into
/// its positions — the same bake [ObjWriter] (`../obj/obj_writer.dart`)
/// already does, since STL has no per-object transform to carry it in
/// either — and the whole document becomes one flat facet list. A model of
/// several surfaces loses the boundary between them on the way out; that is
/// the format's own limit, not this writer's.
///
/// **The facet normal is always the triangle's own cross product**, never a
/// value copied from a source mesh's per-vertex normal — STL has no notion
/// of one to preserve, only a facet's, and computing it fresh from the
/// winding is what [StlLoader]'s own `StlNormals.recomputed` already
/// treats as the trustworthy half of a file it reads.
final class StlWriter {
  StlWriter(this.document, {this.name = 'model'});

  final ModelDocument document;

  /// Written into the binary header's free text and the ASCII `solid` line.
  /// Not read back by anything — [StlLoader] never looks at either.
  final String name;

  /// [surface]'s own mesh, in world space.
  MeshData _bake(ModelSurface surface) => surface.transform.isIdentity()
      ? surface.mesh
      : surface.mesh.transformed(surface.transform);

  /// What [write]/[writeAscii] could not carry — `fmt-12`'s own row. STL
  /// has no material, no colour, no skin, no animation and no boundary
  /// between one surface and the next; this says which of those the
  /// document actually had, rather than a fixed list a caller has to
  /// already know to distrust.
  late final List<String> warnings = _buildWarnings();

  List<String> _buildWarnings() {
    final found = <String>[];
    if (document.surfaces.length > 1) {
      found.add(
        '${document.surfaces.length} surfaces were merged into one solid; '
        'STL has no boundary between them',
      );
    }
    if (document.materials.isNotEmpty) {
      found.add(
        '${document.materials.length} material(s) were not written; STL '
        'has no material record',
      );
    }
    if (document.skins.isNotEmpty) {
      found.add(
        '${document.skins.length} skin(s) were not written; STL has no '
        'skinning',
      );
    }
    if (document.animations.isNotEmpty) {
      found.add(
        '${document.animations.length} animation(s) were not written; '
        'STL has no animation',
      );
    }
    return found;
  }

  /// Every triangle of every surface, corners already in winding order —
  /// mirrored where [ModelSurface.transform] flips handedness, the same
  /// `determinant() < 0.0` check [ObjWriter] reads off the baked matrix
  /// rather than off a flag, since the transform is what actually moved.
  List<(Vector3, Vector3, Vector3)> get _facets {
    final facets = <(Vector3, Vector3, Vector3)>[];
    for (final ModelSurface surface in document.surfaces) {
      final MeshData mesh = _bake(surface);
      final int stride = mesh.layout.floatsPerVertex;
      Vector3 at(int vertex) {
        final int o = vertex * stride;
        return Vector3(
          mesh.vertices[o],
          mesh.vertices[o + 1],
          mesh.vertices[o + 2],
        );
      }

      final bool reversed = surface.transform.determinant() < 0.0;
      for (var t = 0; t + 2 < mesh.indices.length; t += 3) {
        final int ia = mesh.indices[t];
        final int ib = mesh.indices[t + 1];
        final int ic = mesh.indices[t + 2];
        facets.add((at(reversed ? ic : ia), at(ib), at(reversed ? ia : ic)));
      }
    }
    return facets;
  }

  Vector3 _normalOf(Vector3 a, Vector3 b, Vector3 c) {
    final Vector3 cross = (b - a).cross(c - a);
    return cross.length2 > 0.0 ? cross.normalized() : Vector3.zero();
  }

  /// Binary STL: an 80-byte header, a `uint32` facet count, then 50 bytes a
  /// facet — `fmt-20`'s own size formula, `84 + 50 * count`.
  Uint8List write() {
    final List<(Vector3, Vector3, Vector3)> facets = _facets;

    final Uint8List header = Uint8List(80);
    final List<int> headerText = utf8.encode('flutter3d $name');
    header.setRange(0, headerText.length.clamp(0, 80), headerText);

    final out = BytesBuilder()..add(header);
    out.add(
      (ByteData(
        4,
      )..setUint32(0, facets.length, Endian.little)).buffer.asUint8List(),
    );

    // Reused across facets rather than allocated fresh each time:
    // `BytesBuilder.add` copies on the way in, so mutating this same
    // `ByteData` for the next facet never disturbs bytes already written.
    final ByteData facet = ByteData(50);
    void putVec3(int offset, Vector3 v) {
      facet
        ..setFloat32(offset, v.x, Endian.little)
        ..setFloat32(offset + 4, v.y, Endian.little)
        ..setFloat32(offset + 8, v.z, Endian.little);
    }

    for (final (Vector3 a, Vector3 b, Vector3 c) in facets) {
      putVec3(0, _normalOf(a, b, c));
      putVec3(12, a);
      putVec3(24, b);
      putVec3(36, c);
      facet.setUint16(48, 0, Endian.little);
      out.add(facet.buffer.asUint8List());
    }
    return out.toBytes();
  }

  /// ASCII STL: `solid`/`endsolid` bracketing one `facet` per triangle, the
  /// dialect [StlLoader] reads through `looksLikeAsciiStl`.
  Uint8List writeAscii() {
    final out = StringBuffer()..writeln('solid $name');
    for (final (Vector3 a, Vector3 b, Vector3 c) in _facets) {
      final Vector3 n = _normalOf(a, b, c);
      out
        ..writeln('  facet normal ${_n(n.x)} ${_n(n.y)} ${_n(n.z)}')
        ..writeln('    outer loop')
        ..writeln('      vertex ${_n(a.x)} ${_n(a.y)} ${_n(a.z)}')
        ..writeln('      vertex ${_n(b.x)} ${_n(b.y)} ${_n(b.z)}')
        ..writeln('      vertex ${_n(c.x)} ${_n(c.y)} ${_n(c.z)}')
        ..writeln('    endloop')
        ..writeln('  endfacet');
    }
    out.writeln('endsolid $name');
    return utf8.encode(out.toString());
  }

  // `Vector3`'s own storage is already the `double` a `Float32List` element
  // promotes to, so `toString()` here already carries exactly the digits
  // `double.parse` (`StlLoader`'s own reader) needs to land back on the
  // same value — no rounding chosen, none needed.
  String _n(double v) => v.toString();
}
