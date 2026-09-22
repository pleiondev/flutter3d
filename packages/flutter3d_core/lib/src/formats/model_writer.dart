/// Writing a document out, as one interface an application can add to.
///
/// **The write-side twin of `ModelDecoder`, and the reason there is one.**
/// Choosing a writer used to be a `switch` written three times — the engine's
/// `encodeModel`, the modeller's export and the MCP server's `export` — each
/// with its own list of formats, and the three lists had already drifted: the
/// engine could write STL and neither of the other two could. A writer is now
/// a value that knows its name, its suffix and how to turn a document into
/// files, and the list is [builtInModelWriters] plus whatever an application
/// appends to it.
library;

import 'dart:typed_data';

import 'f3d/f3d_loader.dart';
import 'f3d/f3d_writer.dart';
import 'gltf/gltf_loader.dart';
import 'gltf/gltf_writer.dart';
import 'model_document.dart';
import 'obj/obj_loader.dart';
import 'obj/obj_writer.dart';
import 'stl/stl_loader.dart';
import 'stl/stl_writer.dart';
import 'usdz/usdz_writer.dart';

/// One file a write produced.
final class WrittenFile {
  const WrittenFile(this.name, this.bytes);

  /// The name to give it, suffix and all — `table.obj`, `table.mtl`.
  final String name;

  final Uint8List bytes;

  @override
  String toString() => 'WrittenFile($name, ${bytes.length} bytes)';
}

/// What one write produced.
final class ModelWrite {
  const ModelWrite(this.files, {this.warnings = const <String>[]});

  /// In the order they should be written: the file that names the others
  /// first. One for most formats, two for OBJ with a material.
  final List<WrittenFile> files;

  /// What the writer knew it could not carry while it wrote — a skin OBJ has
  /// no record for, a second surface STL has no boundary for.
  final List<String> warnings;
}

/// A format a [ModelDocument] can be written as.
///
/// **An interface, and a small one**: a name to be asked for by, a suffix, a
/// sentence for a menu and the write itself. Everything a format needs beyond
/// that — OBJ's material library, a GLB's geometry compression — belongs to
/// the implementation, which is what lets one caller write any of them.
abstract interface class ModelWriter {
  /// What an agent, a command line or a request asks for: `glb`, `obj`,
  /// `stlAscii`. Stable, because it is typed by people and stored in scripts.
  String get name;

  /// The suffix of the first file, dot included.
  String get suffix;

  /// One line for a menu, in the words a person recognises.
  String get says;

  /// [document] as files, named from [baseName].
  ModelWrite write(ModelDocument document, {String baseName = 'model'});
}

/// A writer whose files this package can also read, so a write can be checked
/// by reading it back — what `exportChecked` does.
///
/// **A second interface rather than a method every writer owes.** USDZ has no
/// reader here, and a `readBack` that threw for it would be a writer breaking
/// the contract it was typed as; a writer that can be checked says so by what
/// it implements.
abstract interface class CheckedModelWriter implements ModelWriter {
  /// The document [written] reads back as.
  Future<ModelDocument> readBack(ModelWrite written);

  /// How far a number may move on the way through: `0.0` for a binary format,
  /// the printed precision for a text one.
  double get tolerance;
}

/// `.f3d`, the engine's own container.
final class F3dModelWriter implements CheckedModelWriter {
  const F3dModelWriter();

  @override
  String get name => 'f3d';

  @override
  String get suffix => '.f3d';

  @override
  String get says => 'the engine container';

  @override
  ModelWrite write(ModelDocument document, {String baseName = 'model'}) {
    final writer = F3dWriter(document);
    final bytes = writer.write();
    return ModelWrite(<WrittenFile>[
      WrittenFile('$baseName$suffix', bytes),
    ], warnings: writer.warnings);
  }

  @override
  Future<ModelDocument> readBack(ModelWrite written) async =>
      F3dDocument.parse(written.files.first.bytes);

  @override
  double get tolerance => 0.0;
}

/// A self-contained glTF binary.
final class GlbModelWriter implements CheckedModelWriter {
  const GlbModelWriter({this.compressGeometry = false});

  /// See [GltfWriter.compressGeometry].
  final bool compressGeometry;

  @override
  String get name => 'glb';

  @override
  String get suffix => '.glb';

  @override
  String get says => 'a glTF binary most other tools open';

  @override
  ModelWrite write(ModelDocument document, {String baseName = 'model'}) {
    final writer = GltfWriter(document, compressGeometry: compressGeometry);
    final bytes = writer.writeGlb();
    return ModelWrite(<WrittenFile>[
      WrittenFile('$baseName$suffix', bytes),
    ], warnings: writer.warnings);
  }

  @override
  Future<ModelDocument> readBack(ModelWrite written) =>
      GltfLoader().load(written.files.first.bytes);

  @override
  double get tolerance => 0.0;
}

/// Wavefront OBJ, with its `.mtl` beside it when the document names a
/// material.
final class ObjModelWriter implements CheckedModelWriter {
  const ObjModelWriter();

  @override
  String get name => 'obj';

  @override
  String get suffix => '.obj';

  @override
  String get says => 'triangles that every tool reads';

  @override
  ModelWrite write(ModelDocument document, {String baseName = 'model'}) {
    final writer = ObjWriter(document, name: baseName);
    final obj = writer.write();
    final mtl = writer.writeMaterialLibrary();
    return ModelWrite(<WrittenFile>[
      WrittenFile('$baseName$suffix', obj),
      if (mtl != null) WrittenFile(writer.materialLibraryName, mtl),
    ], warnings: writer.warnings);
  }

  @override
  Future<ModelDocument> readBack(ModelWrite written) {
    final WrittenFile obj = written.files.first;
    final WrittenFile? mtl = written.files.length > 1 ? written.files[1] : null;
    return ObjLoader().load(
      obj.bytes,
      resolveUri: mtl == null
          ? null
          : (request) async {
              if (request.uri == mtl.name) return mtl.bytes;
              throw ArgumentError('unresolved OBJ asset: ${request.uri}');
            },
    );
  }

  /// [ObjWriter.decimals]' own precision: a decimal text format rounds on the
  /// way out by design.
  @override
  double get tolerance => 5e-6;
}

/// STL, binary or ASCII.
final class StlModelWriter implements CheckedModelWriter {
  const StlModelWriter({this.ascii = false});

  /// Whether to write `solid … endsolid` text rather than the binary form.
  final bool ascii;

  @override
  String get name => ascii ? 'stlAscii' : 'stl';

  @override
  String get suffix => '.stl';

  @override
  String get says => ascii
      ? 'triangles as text, one facet at a time'
      : 'a triangle soup a slicer reads';

  @override
  ModelWrite write(ModelDocument document, {String baseName = 'model'}) {
    final writer = StlWriter(document, name: baseName);
    final bytes = ascii ? writer.writeAscii() : writer.write();
    return ModelWrite(<WrittenFile>[
      WrittenFile('$baseName$suffix', bytes),
    ], warnings: writer.warnings);
  }

  @override
  Future<ModelDocument> readBack(ModelWrite written) =>
      StlLoader().load(written.files.first.bytes);

  /// Zero either way: the ASCII form prints each number at the shortest
  /// length that reads back to the same float.
  @override
  double get tolerance => 0.0;
}

/// `.usdz` — geometry only, the spike [UsdzWriter] describes. Not a
/// [CheckedModelWriter]: nothing here reads a `.usdz`.
final class UsdzModelWriter implements ModelWriter {
  const UsdzModelWriter();

  @override
  String get name => 'usdz';

  @override
  String get suffix => '.usdz';

  @override
  String get says => 'geometry for Quick Look, no materials yet';

  @override
  ModelWrite write(ModelDocument document, {String baseName = 'model'}) =>
      ModelWrite(<WrittenFile>[
        WrittenFile(
          '$baseName$suffix',
          UsdzWriter(document, name: baseName).write(),
        ),
      ]);
}

/// Every writer this package ships, in the order a menu would offer them.
///
/// Two share `.stl`; asked for by that suffix, [modelWriterNamed] answers with
/// the binary one, which comes first.
const List<ModelWriter> builtInModelWriters = <ModelWriter>[
  F3dModelWriter(),
  GlbModelWriter(),
  ObjModelWriter(),
  StlModelWriter(),
  StlModelWriter(ascii: true),
  UsdzModelWriter(),
];

/// The writer in [writers] that [asked] names — by [ModelWriter.name] first,
/// then by [ModelWriter.suffix], with or without its dot, ignoring case — or
/// null when none does.
///
/// A caller that offers more than this package ships passes its own list,
/// [builtInModelWriters] and its own writers together.
ModelWriter? modelWriterNamed(
  String asked, {
  List<ModelWriter> writers = builtInModelWriters,
}) {
  final key = asked.toLowerCase();
  for (final ModelWriter writer in writers) {
    if (writer.name.toLowerCase() == key) return writer;
  }
  final suffix = key.startsWith('.') ? key : '.$key';
  for (final ModelWriter writer in writers) {
    if (writer.suffix == suffix) return writer;
  }
  return null;
}
