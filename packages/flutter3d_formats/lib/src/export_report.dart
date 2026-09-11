/// What one write actually produced — `fmt-12`'s own row: `ExportReport
/// {files, writerWarnings, differences}` = write → read back → compare.
///
/// **Two different questions, kept apart rather than folded into one
/// pass/fail.** [writerWarnings] is what the writer already knew it was
/// dropping while it wrote — a skin OBJ has no record for, a second
/// surface STL has no boundary for. [differences] is what
/// [compareModelDocuments] finds by actually reading the file back, which
/// catches what nobody predicted: a rounding bug, an index off by one, an
/// attribute that silently stopped writing. A clean [differences] list
/// with warnings in it is a writer working as documented; warnings with
/// *more* differences than they explain is a writer with a real bug.
library;

import 'dart:typed_data';

import 'document_compare.dart';
import 'f3d/f3d_loader.dart';
import 'f3d/f3d_writer.dart';
import 'gltf/gltf_loader.dart';
import 'gltf/gltf_writer.dart';
import 'model_document.dart';
import 'obj/obj_loader.dart';
import 'obj/obj_writer.dart';
import 'stl/stl_loader.dart';
import 'stl/stl_writer.dart';

/// One write, read back and checked against what went in.
final class ExportReport {
  const ExportReport({
    required this.files,
    required this.writerWarnings,
    required this.differences,
  });

  /// Every file the write produced, keyed by name — one entry for a binary
  /// format, two for OBJ (`.obj` and its `.mtl`, when the document names a
  /// material).
  final Map<String, Uint8List> files;

  /// What the writer itself knew it could not carry — see each writer's
  /// own `warnings` getter for what it checks.
  final List<String> writerWarnings;

  /// What [compareModelDocuments] found reading the write back — see that
  /// function's own doc comment for what it does and does not check.
  final List<DocumentDifference> differences;

  /// Whether the round trip held with nothing to explain it — no
  /// warnings, no differences. A format that drops data honestly reports
  /// `writerWarnings.isNotEmpty` here even on a mesh it wrote perfectly
  /// correctly.
  bool get isClean => writerWarnings.isEmpty && differences.isEmpty;

  @override
  String toString() =>
      'ExportReport(${files.keys.join(', ')}: '
      '${writerWarnings.length} warning(s), ${differences.length} '
      'difference(s))';
}

/// Writes [document] as glTF, reads the result back and compares — a
/// binary format, so the round trip is held to a tolerance of `0.0`.
Future<ExportReport> exportToGlb(ModelDocument document, {String name = 'model'}) async {
  final writer = GltfWriter(document);
  final bytes = writer.writeGlb();
  final readBack = await GltfLoader().load(bytes);
  return ExportReport(
    files: <String, Uint8List>{'$name.glb': bytes},
    writerWarnings: writer.warnings,
    differences: compareModelDocuments(document, readBack),
  );
}

/// Writes [document] as OBJ (with its `.mtl` beside it, when the document
/// names a material), reads the result back and compares — held to
/// [ObjWriter.decimals]' own precision rather than `0.0`, since a decimal
/// text format rounds on the way out by design.
Future<ExportReport> exportToObj(ModelDocument document, {String name = 'model'}) async {
  final writer = ObjWriter(document, name: name);
  final objBytes = writer.write();
  final mtlBytes = writer.writeMaterialLibrary();
  final files = <String, Uint8List>{
    '$name.obj': objBytes,
    writer.materialLibraryName: ?mtlBytes,
  };
  final readBack = await ObjLoader().load(
    objBytes,
    resolveUri: mtlBytes == null
        ? null
        : (request) async {
            if (request.uri == writer.materialLibraryName) return mtlBytes;
            throw ArgumentError('unresolved OBJ asset: ${request.uri}');
          },
  );
  return ExportReport(
    files: files,
    writerWarnings: writer.warnings,
    differences: compareModelDocuments(document, readBack, tolerance: 5e-6),
  );
}

/// Writes [document] as binary STL, reads the result back and compares.
///
/// **A surface-count difference is expected, not a bug**, the moment
/// [document] holds more than one: STL has no boundary between surfaces,
/// so [StlWriter.warnings] already says so, and [ExportReport.differences]
/// will report the merge as well — the two are meant to be read together,
/// not as a pass/fail on their own.
Future<ExportReport> exportToStl(ModelDocument document, {String name = 'model'}) async {
  final writer = StlWriter(document, name: name);
  final bytes = writer.write();
  final readBack = await StlLoader().load(bytes);
  return ExportReport(
    files: <String, Uint8List>{'$name.stl': bytes},
    writerWarnings: writer.warnings,
    differences: compareModelDocuments(document, readBack),
  );
}

/// Writes [document] to this engine's own `.f3d` container, reads the
/// result back and compares. Synchronous, unlike the other three: `.f3d`
/// is read as a view over its own bytes rather than decoded, and nothing
/// in that path is asynchronous either.
ExportReport exportToF3d(ModelDocument document, {String name = 'model'}) {
  final writer = F3dWriter(document);
  final bytes = writer.write();
  final readBack = F3dDocument.parse(bytes);
  return ExportReport(
    files: <String, Uint8List>{'$name.f3d': bytes},
    writerWarnings: writer.warnings,
    differences: compareModelDocuments(document, readBack),
  );
}
