/// "Download as…": a model the service holds, written out in another format.
///
/// **The engine's own writers, run where they can be stopped.** The stored
/// file is decoded by the same readers that accepted it
/// (`decodeStoredModel`), written by `flutter3d_core`'s [ModelWriter]s, and
/// packed into one download — in an isolate killed at [conversionDeadline],
/// the same deadline and the same machinery as `/convert`. No outside
/// program runs, so there is no `.blend`: Blender opens the `.glb`.
///
/// **One conversion per key at a time.** Two people pressing the same link
/// at once wait on one isolate, not two ([ExportRuns]).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

import '../storage/inspect.dart';
import 'converter.dart' show conversionDeadline;
import 'gltf_files.dart';
import 'killable.dart';
import 'zip_writer.dart';

/// Which writers wrote a cached export. Raise it when a writer in
/// `flutter3d_core` changes what it writes (or this file changes how it
/// packs it), and every cached export is written again on its next request;
/// the old rows are dropped when their model's source changes or the model
/// is deleted.
const int exportWriterVersion = 1;

/// What a model can be downloaded as.
enum ExportFormat {
  /// The stored file itself, byte for byte.
  original('original', 'Original file', null),

  /// The engine's container.
  f3d('f3d', '.f3d — flutter3d', 'f3d'),

  /// One self-contained glTF binary. What Blender imports best.
  glb('glb', '.glb — glTF binary', 'glb'),

  /// glTF as JSON, with its `.bin` and textures beside it, in a `.zip`.
  gltf('gltf', '.gltf — with .bin and textures, as .zip', 'glb'),

  /// OBJ, with its `.mtl` and textures in a `.zip` when there are any.
  obj('obj', '.obj — with .mtl and textures', 'obj'),

  /// Binary STL: triangles only, for a slicer.
  stl('stl', '.stl — triangles for printing', 'stl'),

  /// USDZ, geometry only, for Quick Look.
  usdz('usdz', '.usdz — geometry only', 'usdz');

  const ExportFormat(this.column, this.label, this.writerName);

  /// The address's last segment, `/files/<id>/as/<column>`, and the key the
  /// cache stores.
  final String column;

  /// What the menu says.
  final String label;

  /// The core writer it goes through: `modelWriterNamed(writerName)`. `.gltf`
  /// is the GLB, taken apart ([splitGlb]).
  final String? writerName;

  static ExportFormat? of(String? column) =>
      values.where((f) => f.column == column).firstOrNull;

  /// Whether a model stored as [source] is already this format, so asking
  /// for it serves the stored file — and loses nothing a rewrite would, such
  /// as a glTF extension the engine does not read.
  bool isAlready(SourceFormat? source) => switch (this) {
    original => true,
    f3d => source == SourceFormat.f3d,
    glb => source == SourceFormat.glb,
    // A `.gltf` kept here is self-contained (`inspectUpload` refuses one
    // that is not), so it is served as the one file it is.
    gltf => source == SourceFormat.gltf,
    obj => source == SourceFormat.obj,
    stl || usdz => false,
  };

  /// What a stored [source] offers in its menu: every format, less the ones
  /// that would only be the original again under another name.
  static List<ExportFormat> offeredFor(SourceFormat? source) => <ExportFormat>[
    original,
    for (final format in values)
      if (format != original && !format.isAlready(source)) format,
  ];

  /// The download's name for a model called [baseName]: `chair.stl`, or
  /// `chair-gltf.zip` when the write is several files.
  String fileNameFor(String baseName, {required bool zipped}) =>
      zipped ? '$baseName-$column.zip' : '$baseName${_suffix()}';

  String _suffix() => switch (this) {
    original => '',
    f3d => '.f3d',
    glb => '.glb',
    gltf => '.gltf',
    obj => '.obj',
    stl => '.stl',
    usdz => '.usdz',
  };

  /// The content type of a single-file download in this format.
  String get contentType => switch (this) {
    original || f3d => 'application/octet-stream',
    glb => 'model/gltf-binary',
    gltf => 'model/gltf+json',
    obj => 'model/obj',
    stl => 'model/stl',
    usdz => 'model/vnd.usdz+zip',
  };
}

/// One download, ready to store or send.
final class ExportedFile {
  const ExportedFile({
    required this.bytes,
    required this.contentType,
    required this.zipped,
  });

  final Uint8List bytes;
  final String contentType;

  /// Whether this is a `.zip` of several files rather than the format's one
  /// file.
  final bool zipped;
}

/// How an export ended.
sealed class ExportOutcome {
  const ExportOutcome();
}

final class Exported extends ExportOutcome {
  const Exported(this.file);

  final ExportedFile file;
}

/// Not written, for [because]: what the reader or the writer said, or the
/// deadline.
final class ExportRefused extends ExportOutcome {
  const ExportRefused(this.because);

  final String because;
}

/// Writes a model in a format. [exportModel] in the service; a test hands in
/// one that counts its calls.
typedef ExportRun =
    Future<ExportOutcome> Function(
      Uint8List source, {
      required String sourceName,
      required ExportFormat format,
      required String baseName,
    });

/// Writes [source] — a stored model, or a converted `.f3d` — as [format],
/// in an isolate of its own that is killed at [deadline].
///
/// [sourceName] is the stored file's name (its suffix helps the reader);
/// [baseName] is what the files inside are called.
Future<ExportOutcome> exportModel(
  Uint8List source, {
  required String sourceName,
  required ExportFormat format,
  required String baseName,
  Duration deadline = conversionDeadline,
}) async {
  if (format == ExportFormat.original) {
    return Exported(
      ExportedFile(
        bytes: source,
        contentType: format.contentType,
        zipped: false,
      ),
    );
  }
  final answer = await runKillable<_Job>(
    _exportInIsolate,
    (reply) => _Job(
      reply: reply,
      bytes: source,
      name: sourceName,
      format: format,
      baseName: baseName,
    ),
    deadline: deadline,
    debugName: 'export $sourceName as ${format.column}',
  );
  return switch (answer) {
    Answered(message: final ExportOutcome outcome) => outcome,
    TimedOut() => ExportRefused(
      'Writing $baseName as ${format.column} took longer than '
      '${describeDuration(deadline)}, so it was stopped.',
    ),
    _ => ExportRefused(
      'The writer stopped before it finished $baseName as ${format.column}.',
    ),
  };
}

/// [name] reduced to what a file inside an archive, and a download, may be
/// called: no directory, no suffix, nothing but letters, digits, `-`, `_`
/// and `.`. Never empty.
String exportBaseName(String name) {
  final base = name.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  final stem = (dot > 0 ? base.substring(0, dot) : base)
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  if (stem.isEmpty) return 'model';
  return stem.length > 80 ? stem.substring(0, 80) : stem;
}

/// The exports running now, by key, so a second request for the same one
/// waits on the first instead of starting its own.
///
/// In-process only: one server, one map. A key is forgotten the moment its
/// work ends, success or not, so a refusal is not remembered either.
class ExportRuns<T> {
  final Map<String, Future<T>> _running = <String, Future<T>>{};

  /// [work]'s answer, or the answer of the run already going for [key].
  Future<T> once(String key, Future<T> Function() work) {
    final running = _running[key];
    if (running != null) return running;
    final started = work().whenComplete(() => _running.remove(key));
    _running[key] = started;
    return started;
  }

  /// How many keys are running — for a test.
  int get length => _running.length;
}

final class _Job {
  const _Job({
    required this.reply,
    required this.bytes,
    required this.name,
    required this.format,
    required this.baseName,
  });

  final SendPort reply;
  final Uint8List bytes;
  final String name;
  final ExportFormat format;
  final String baseName;
}

Future<void> _exportInIsolate(_Job job) async {
  final outcome = await _exportHere(job);
  Isolate.exit(job.reply, outcome);
}

Future<ExportOutcome> _exportHere(_Job job) async {
  final ModelDocument document;
  try {
    document = await decodeStoredModel(job.bytes, job.name);
  } on Object catch (error) {
    return ExportRefused('${job.name} could not be read: ${_reason(error)}');
  }
  // What `inspectUpload` refuses to store, refused here too: a writer handed
  // an empty document writes an empty file without complaint.
  if (document.surfaces.isEmpty && document.nodes.isEmpty) {
    return ExportRefused(
      'There is nothing in ${job.name} to write: no meshes and no nodes.',
    );
  }
  final writer = modelWriterNamed(job.format.writerName ?? '');
  if (writer == null) {
    return ExportRefused('There is no writer for ${job.format.column} here.');
  }
  try {
    final written = writer.write(document, baseName: job.baseName);
    if (written.files.isEmpty || written.files.first.bytes.isEmpty) {
      return ExportRefused(
        'The ${job.format.column} writer wrote nothing for ${job.baseName}.',
      );
    }
    return Exported(_pack(job, document, written));
  } on Object catch (error) {
    return ExportRefused(
      '${job.baseName} cannot be written as ${job.format.column}: '
      '${_reason(error)}',
    );
  }
}

ExportedFile _pack(_Job job, ModelDocument document, ModelWrite written) {
  final List<(String, Uint8List)> files = switch (job.format) {
    ExportFormat.gltf => splitGlb(
      written.files.first.bytes,
      baseName: job.baseName,
    ),
    ExportFormat.obj => <(String, Uint8List)>[
      for (final file in written.files) (file.name, file.bytes),
      ..._objTextures(document, written),
    ],
    _ => <(String, Uint8List)>[
      for (final file in written.files) (file.name, file.bytes),
    ],
  };
  if (files.length == 1) {
    return ExportedFile(
      bytes: files.single.$2,
      contentType: job.format.contentType,
      zipped: false,
    );
  }
  return ExportedFile(
    bytes: storedZip(files),
    contentType: 'application/zip',
    zipped: true,
  );
}

/// The images an OBJ's `.mtl` names with `map_Kd`, under the names it gives
/// them — so the archive opens with its textures. A name that would leave
/// the archive's folder is skipped, and so is the texture.
List<(String, Uint8List)> _objTextures(
  ModelDocument document,
  ModelWrite written,
) {
  if (written.files.length < 2) return const <(String, Uint8List)>[];
  final mtl = String.fromCharCodes(written.files[1].bytes);
  final named = <String>{
    for (final line in mtl.split('\n'))
      if (line.trimLeft().startsWith('map_Kd '))
        line.trimLeft().substring('map_Kd '.length).trim(),
  };
  final seen = <String>{};
  return <(String, Uint8List)>[
    for (final image in document.images)
      if (image.name case final name?
          when named.contains(_collapsed(name)) &&
              _insideArchive(_collapsed(name)) &&
              seen.add(_collapsed(name)))
        (_collapsed(name), image.bytes),
  ];
}

/// The OBJ writer's own reduction of a name to one record's worth.
String _collapsed(String name) => name.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _insideArchive(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.startsWith(r'\') &&
    !path.contains(':') &&
    !path.split(RegExp(r'[/\\]')).contains('..');

/// An error as a clause: a `StateError`'s message without its type.
String _reason(Object error) => switch (error) {
  StateError(:final message) => message,
  ArgumentError(:final message) when message != null => '$message',
  _ => '$error',
};
