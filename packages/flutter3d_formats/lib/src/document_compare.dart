/// Whether a document survived being written and read again.
///
/// **The question every writer in this repository has to answer, asked in one
/// place.** A format promises that what comes back is what went in, and the
/// only honest way to check that is to write a document, read it with the
/// matching loader, and compare the two — not the file against a stored copy of
/// itself, which passes whenever both halves are wrong together.
///
/// **The vertex and index bytes are compared, not the counts.** A count
/// comparison passes a file whose floats were mangled by an endianness slip:
/// the same number of vertices arrives, each of them somewhere else. This is
/// the check that costs a pass over the buffers and catches that.
///
/// It lived in `dart run flutter3d_build:convert` and had one caller, which is a poor
/// place for the one thing that says whether a writer works. Every writer wants
/// it, and a writer shipped without it is a writer nobody has checked.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';

import 'model_document.dart';

/// One thing a round trip did not preserve.
final class DocumentDifference {
  const DocumentDifference(this.said);

  /// A sentence naming what changed and both values, so that whoever reads it
  /// can tell a truncation from a reordering without opening the file.
  final String said;

  @override
  String toString() => said;
}

/// What [readBack] lost or changed against [source]. Empty means the round trip
/// held.
///
/// [tolerance] is how far a vertex float may move and still count as the same
/// number. Zero — the default, and what a binary format is held to — means the
/// bytes have to match. A format that writes decimal text cannot promise that:
/// OBJ rounds to the digits it was asked for, so an export checked against zero
/// would report every vertex in the file. Passing the writer's own precision is
/// what makes the check mean "nothing was lost" rather than "nothing was
/// rounded".
///
/// **What this does not compare yet, said plainly rather than left to be
/// discovered:** the node hierarchy, the transforms on it, and the fields
/// inside a material. It counts nodes, materials, images and animations, and
/// compares geometry in full. Those are the checks the tool it came from had,
/// and widening them is worth doing against a format that would fail them —
/// adding a check nothing exercises is a check nobody has seen work.
///
/// [allowVertexReorder] is `fmt-30n`'s own accommodation for
/// `GltfWriter(compressGeometry: true)`'s vertex-cache reordering pass: a
/// mesh whose triangles and vertices were moved for GPU cache reuse fails the
/// default position-by-position check even though it draws identically,
/// since reordering's entire point is to move which byte offset a vertex or
/// index lands at. When true, a surface whose vertex/index *counts* still
/// match is instead compared as the multiset of triangles it draws — each
/// found in the other side allowing any of its three cyclic rotations (same
/// winding, different starting corner) and [tolerance] per float — rather
/// than by position. Off by default: every other writer in this repository
/// is held to the stricter check, and turning this on for a writer that
/// never reorders would let a real positional bug through as a "reorder".
List<DocumentDifference> compareModelDocuments(
  ModelDocument source,
  ModelDocument readBack, {
  double tolerance = 0.0,
  bool allowVertexReorder = false,
}) {
  final problems = <DocumentDifference>[];

  void check(bool condition, String message) {
    if (!condition) problems.add(DocumentDifference(message));
  }

  check(
    source.surfaces.length == readBack.surfaces.length,
    'surfaces: ${source.surfaces.length} in, ${readBack.surfaces.length} out',
  );
  check(
    source.materials.length == readBack.materials.length,
    'materials: ${source.materials.length} in, ${readBack.materials.length} out',
  );
  check(
    source.images.length == readBack.images.length,
    'images: ${source.images.length} in, ${readBack.images.length} out',
  );
  check(
    source.nodes.length == readBack.nodes.length,
    'nodes: ${source.nodes.length} in, ${readBack.nodes.length} out',
  );
  check(
    source.animations.length == readBack.animations.length,
    'animations: ${source.animations.length} in, '
    '${readBack.animations.length} out',
  );
  // Nothing below can be said about documents that disagree about how many of
  // anything they hold: `surfaces[7]` on one side is a different surface from
  // `surfaces[7]` on the other, and pairing them by index would report every
  // one of them as changed.
  if (problems.isNotEmpty) return problems;

  for (var i = 0; i < source.surfaces.length; i++) {
    final a = source.surfaces[i].mesh;
    final b = readBack.surfaces[i].mesh;

    if (a.layout.toString() != b.layout.toString()) {
      problems.add(
        DocumentDifference(
          'surfaces[$i]: layout ${a.layout} became ${b.layout}',
        ),
      );
      continue;
    }
    if (a.vertices.length != b.vertices.length ||
        a.indices.length != b.indices.length) {
      problems.add(
        DocumentDifference(
          'surfaces[$i]: ${a.vertexCount} vertices / ${a.indexCount} indices '
          'became ${b.vertexCount} / ${b.indexCount}',
        ),
      );
      continue;
    }
    if (allowVertexReorder) {
      final mismatch = _findUnmatchedTriangle(a, b, tolerance);
      if (mismatch != null) {
        problems.add(DocumentDifference('surfaces[$i]: $mismatch'));
      }
    } else {
      // The first difference in each buffer and then on to the next surface:
      // a surface whose floats are all shifted has every one of them wrong,
      // and a list of forty thousand identical complaints hides the second
      // surface that is wrong for another reason.
      for (var v = 0; v < a.vertices.length; v++) {
        // Negated rather than `> tolerance`, so a NaN — which loses every
        // comparison it is in — is reported as a difference instead of
        // passing.
        if (!((a.vertices[v] - b.vertices[v]).abs() <= tolerance)) {
          problems.add(
            DocumentDifference(
              'surfaces[$i]: vertex float $v is ${a.vertices[v]} in, '
              '${b.vertices[v]} out',
            ),
          );
          break;
        }
      }
      for (var v = 0; v < a.indices.length; v++) {
        if (a.indices[v] != b.indices[v]) {
          problems.add(
            DocumentDifference(
              'surfaces[$i]: index $v is ${a.indices[v]} in, '
              '${b.indices[v]} out',
            ),
          );
          break;
        }
      }
    }

    // A reordered mesh's morph target deltas moved with their base vertex
    // exactly the way its positions did, but this function has no vertex
    // correspondence to check them against once triangle order is allowed to
    // differ — the triangle match above only proves the *base* geometry
    // survived. Nothing in this repository compresses a mesh with morph
    // targets yet, so this is a documented gap rather than a silent one.
    if (!allowVertexReorder) {
      _compareMorphTargets(
        problems,
        i,
        a.morphTargets,
        b.morphTargets,
        tolerance,
      );
    }
  }

  return problems;
}

/// [source]'s own morph targets against [readBack]'s, for surface [i] —
/// `anim-27`'s own "имя формы в F3dRecord.morphTarget": a target's own
/// [MorphTarget.name] is a value nothing upstream of this reconstructs from
/// anything else, so a writer that dropped it or a loader that misread it
/// would otherwise go unnoticed by every caller that already trusts this
/// function for "the round trip held".
void _compareMorphTargets(
  List<DocumentDifference> problems,
  int i,
  List<MorphTarget> source,
  List<MorphTarget> readBack,
  double tolerance,
) {
  if (source.length != readBack.length) {
    problems.add(
      DocumentDifference(
        'surfaces[$i]: ${source.length} morph targets in, '
        '${readBack.length} out',
      ),
    );
    return;
  }
  for (var t = 0; t < source.length; t++) {
    final a = source[t];
    final b = readBack[t];
    if (a.name != b.name) {
      problems.add(
        DocumentDifference(
          'surfaces[$i]: morph target $t is named '
          '${a.name == null ? 'nothing' : '"${a.name}"'} in, '
          '${b.name == null ? 'nothing' : '"${b.name}"'} out',
        ),
      );
    }
    if (a.positions.length != b.positions.length) {
      problems.add(
        DocumentDifference(
          'surfaces[$i]: morph target $t has ${a.positions.length} '
          'position floats in, ${b.positions.length} out',
        ),
      );
      continue;
    }
    for (var v = 0; v < a.positions.length; v++) {
      if (!((a.positions[v] - b.positions[v]).abs() <= tolerance)) {
        problems.add(
          DocumentDifference(
            'surfaces[$i]: morph target $t position float $v is '
            '${a.positions[v]} in, ${b.positions[v]} out',
          ),
        );
        break;
      }
    }
  }
}

/// One triangle of a mesh, as its three vertices' full attribute rows in
/// winding order — the unit [_findUnmatchedTriangle] matches on, since a
/// reordered mesh keeps every float of a vertex together but not at any
/// particular index.
List<Float32List> _triangleAt(MeshData mesh, int triangle) {
  final stride = mesh.layout.floatsPerVertex;
  Float32List vertexAt(int v) =>
      Float32List.sublistView(mesh.vertices, v * stride, v * stride + stride);
  return <Float32List>[
    for (var corner = 0; corner < 3; corner++)
      vertexAt(mesh.indices[triangle * 3 + corner]),
  ];
}

bool _sameVertex(Float32List a, Float32List b, double tolerance) {
  for (var c = 0; c < a.length; c++) {
    if (!((a[c] - b[c]).abs() <= tolerance)) return false;
  }
  return true;
}

/// Whether [a] and [b] draw the same triangle: the same three vertices in
/// the same winding, allowing the three to start at a different corner —
/// `(v0,v1,v2)` and `(v1,v2,v0)` are the same triangle, `(v0,v2,v1)` faces
/// the other way and is not.
bool _sameTriangle(List<Float32List> a, List<Float32List> b, double tolerance) {
  for (var rotation = 0; rotation < 3; rotation++) {
    if (_sameVertex(a[0], b[rotation], tolerance) &&
        _sameVertex(a[1], b[(rotation + 1) % 3], tolerance) &&
        _sameVertex(a[2], b[(rotation + 2) % 3], tolerance)) {
      return true;
    }
  }
  return false;
}

/// A one-line description of the first triangle [source] draws that
/// [readBack] does not, checked as an unordered multiset with [tolerance] per
/// float — or null when every one of [source]'s triangles has a match. Vertex
/// and index *counts* are assumed already equal; a mismatch there is caught
/// before this runs.
///
/// `O(triangleCount²)`, the same trade this row's own vertex-cache optimizer
/// makes: correctness over asymptotic speed, on the thousands of triangles a
/// real test model has rather than a production-sized one.
String? _findUnmatchedTriangle(
  MeshData source,
  MeshData readBack,
  double tolerance,
) {
  final triangleCount = source.triangleCount;
  if (triangleCount != readBack.triangleCount) {
    return '${source.triangleCount} triangles in, ${readBack.triangleCount} '
        'out';
  }
  final candidates = <List<Float32List>>[
    for (var t = 0; t < triangleCount; t++) _triangleAt(readBack, t),
  ];
  final matched = List<bool>.filled(triangleCount, false);
  for (var t = 0; t < triangleCount; t++) {
    final triangle = _triangleAt(source, t);
    final found = _firstUnmatched(candidates, matched, triangle, tolerance);
    if (found == null) {
      return 'triangle $t has no match — reordered, but not the same '
          'geometry — in the read-back mesh';
    }
    matched[found] = true;
  }
  return null;
}

int? _firstUnmatched(
  List<List<Float32List>> candidates,
  List<bool> matched,
  List<Float32List> triangle,
  double tolerance,
) {
  for (var i = 0; i < candidates.length; i++) {
    if (matched[i]) continue;
    if (_sameTriangle(triangle, candidates[i], tolerance)) return i;
  }
  return null;
}
