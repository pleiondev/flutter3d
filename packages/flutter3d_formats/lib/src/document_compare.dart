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
/// It lived in `tool/convert_asset.dart` and had one caller, which is a poor
/// place for the one thing that says whether a writer works. Every writer wants
/// it, and a writer shipped without it is a writer nobody has checked.
library;

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
List<DocumentDifference> compareModelDocuments(
  ModelDocument source,
  ModelDocument readBack, {
  double tolerance = 0.0,
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
        DocumentDifference('surfaces[$i]: layout ${a.layout} became ${b.layout}'),
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
    // The first difference in each buffer and then on to the next surface: a
    // surface whose floats are all shifted has every one of them wrong, and a
    // list of forty thousand identical complaints hides the second surface
    // that is wrong for another reason.
    for (var v = 0; v < a.vertices.length; v++) {
      // Negated rather than `> tolerance`, so a NaN — which loses every
      // comparison it is in — is reported as a difference instead of passing.
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
            'surfaces[$i]: index $v is ${a.indices[v]} in, ${b.indices[v]} out',
          ),
        );
        break;
      }
    }
  }

  return problems;
}
