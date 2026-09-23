import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';

import '../model_document.dart';
import 'usdz_zip.dart';

/// Encodes a [ModelDocument] as `.usdz` — `fmt-27`'s own row, and a spike
/// rather than the feature-complete writer every other format here has:
/// geometry only, no materials, no hierarchy past one `Mesh` prim per
/// surface. What decides whether it grows past that is stated in the plan
/// as a question — is there demand — and a spike is exactly the size of
/// thing that can answer it without committing to the rest up front.
///
/// **One `Mesh` prim per surface, each with its own transform baked in.**
/// USD has real hierarchy and this writer does not use any of it, for the
/// same reason [StlWriter] (`../stl/stl_writer.dart`) does not: every
/// surface's placement is its own affair here, and a document with more
/// than one surface reads as a flat set of siblings under one root rather
/// than the tree it may have had on the way in.
///
/// **Every string is ASCII and every number a fixed six decimal places.**
/// A `.usda` file is text a person can open, but nothing here is meant to
/// be hand-edited — the fixed formatting is what makes two writes of the
/// same document byte-identical, the same determinism [GltfWriter] holds
/// itself to and for the same reason: a diff that is all whitespace noise
/// hides the diff that matters.
final class UsdzWriter {
  UsdzWriter(this.document, {this.name = 'model'});

  final ModelDocument document;

  /// The `.usda` entry's own name inside the archive, and the root `Xform`
  /// prim's name once sanitized to a legal USD identifier.
  final String name;

  MeshData _bake(ModelSurface surface) => surface.transform.isIdentity()
      ? surface.mesh
      : surface.mesh.transformed(surface.transform);

  /// Builds the archive: one `.usda` layer, first — the entry a `.usdz`
  /// reader treats as the default is whichever comes first, which is why
  /// nothing else is ever stored ahead of it.
  Uint8List write() {
    final usda = _buildUsda();
    // The entry name through the same sanitizer as the prim: `UsdzZip` writes
    // a name's code units as single bytes, so a non-ASCII [name] would reach
    // the archive truncated to garbage rather than as the name given.
    final zip = UsdzZip()
      ..store(
        '${_identifier(name, fallback: 'model')}.usda',
        Uint8List.fromList(utf8.encode(usda)),
      );
    return zip.build();
  }

  String _buildUsda() {
    final root = _identifier(name, fallback: 'Model');
    final out = StringBuffer()
      ..writeln('#usda 1.0')
      ..writeln('(')
      ..writeln('    defaultPrim = "$root"')
      ..writeln('    upAxis = "Y"')
      ..writeln('    metersPerUnit = 1')
      ..writeln(')')
      ..writeln()
      ..writeln('def Xform "$root"')
      ..writeln('{');

    for (var i = 0; i < document.surfaces.length; i++) {
      _writeMesh(out, document.surfaces[i], i);
    }

    out.writeln('}');
    return out.toString();
  }

  void _writeMesh(StringBuffer out, ModelSurface surface, int index) {
    final mesh = _bake(surface);
    final prim = _identifier(
      surface.name ?? 'Mesh$index',
      fallback: 'Mesh$index',
    );
    final layout = mesh.layout;
    final stride = layout.floatsPerVertex;
    final positionAt = layout.floatOffsetOf(VertexLayout.position.name);
    final normalAt = layout.floatOffsetOf(VertexLayout.normal.name);

    out
      ..writeln('    def Mesh "$prim"')
      ..writeln('    {')
      ..writeln('        uniform bool doubleSided = true')
      ..writeln('        uniform token subdivisionScheme = "none"');

    out.write('        int[] faceVertexCounts = [');
    out.write(List<String>.filled(mesh.triangleCount, '3').join(', '));
    out.writeln(']');

    // A mirroring transform, once baked into the points, turns every triangle
    // inside out; the corners are written in the opposite order to undo it —
    // the same `determinant() < 0.0` check `StlWriter` and `ObjWriter` make.
    final reversed = surface.transform.determinant() < 0.0;
    out.write('        int[] faceVertexIndices = [');
    out.write(
      <int>[
        for (var t = 0; t + 2 < mesh.indices.length; t += 3) ...[
          mesh.indices[reversed ? t + 2 : t],
          mesh.indices[t + 1],
          mesh.indices[reversed ? t : t + 2],
        ],
      ].join(', '),
    );
    out.writeln(']');

    if (normalAt >= 0) {
      out.write('        normal3f[] normals = [');
      out.write(
        <String>[
          for (var v = 0; v < mesh.vertexCount; v++)
            _vec3(mesh.vertices, v * stride + normalAt),
        ].join(', '),
      );
      out.writeln(']');
    }

    out.write('        point3f[] points = [');
    out.write(
      <String>[
        for (var v = 0; v < mesh.vertexCount; v++)
          _vec3(mesh.vertices, v * stride + positionAt),
      ].join(', '),
    );
    out.writeln(']');

    out.writeln('    }');
  }

  static String _n(double v) => v.toStringAsFixed(6);

  static String _vec3(Float32List data, int at) =>
      '(${_n(data[at])}, ${_n(data[at + 1])}, ${_n(data[at + 2])})';

  /// A name as a legal USD prim identifier: letters, digits and
  /// underscores, never starting with a digit — glTF and OBJ both allow
  /// names USD's own grammar refuses (a leading digit, a space, a dot), and
  /// a writer that passed one through verbatim would produce a `.usda`
  /// no `.usdz` reader can parse rather than one with a slightly wrong name.
  static String _identifier(String source, {required String fallback}) {
    final buffer = StringBuffer();
    for (final unit in source.codeUnits) {
      final char = String.fromCharCode(unit);
      final isLetter =
          (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
      final isDigit = unit >= 48 && unit <= 57;
      if (isLetter || isDigit || unit == 0x5F) {
        buffer.write(char);
      } else {
        buffer.write('_');
      }
    }
    // A leading digit is legal everywhere else in the name but not as its
    // first character — prefixed rather than replaced, so the digit itself
    // still reads in the result instead of vanishing into another
    // underscore.
    var result = buffer.toString();
    if (result.isNotEmpty &&
        result.codeUnitAt(0) >= 48 &&
        result.codeUnitAt(0) <= 57) {
      result = '_$result';
    }
    return result.isEmpty ? fallback : result;
  }
}
