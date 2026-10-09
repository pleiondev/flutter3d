/// `/convert`'s one door into `flutter3d_build`'s converters.
///
/// **The only file that knows how the converters are called**:
/// `package:flutter3d_build/convert.dart`'s `convertFiles`, bytes in and
/// bytes out. This file unpacks the upload, runs that call somewhere it can
/// be stopped, and turns its reports into what the pages show.
///
/// **Input safety, not rate limiting.** Anybody with a confirmed address may
/// convert as often as they like. What is guarded is the process: each
/// conversion runs in an isolate of its own that is killed when its time is
/// up, an archive is unpacked under a budget it cannot talk its way past
/// (`zip_guard.dart`), and the converters cannot read outside the upload
/// (`confinement.dart`). FBX, `.blend` and binary USD are read through
/// external programs on a desktop; none is run here, and those inputs are
/// reported as not available online.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_build/convert.dart' as build;
import 'package:flutter3d_core/formats.dart';
import 'package:path/path.dart' as p;

import '../storage/inspect.dart';
import 'confinement.dart';
import 'killable.dart';
import 'zip_guard.dart';

/// How long one conversion may run before its isolate is killed.
const Duration conversionDeadline = Duration(minutes: 2);

/// The most an uploaded archive may unpack to, every entry and every
/// `.usdz` inside it together.
const int conversionExpansionBudget = 512 * 1024 * 1024;

/// What a person asked to get out of a conversion.
///
/// The converters decide what an input becomes — a Unity prefab is a level
/// with its models and materials, a `.mtlx` is a material — so a target is
/// which of those outputs are offered, not an instruction to the reader.
enum ConversionTarget {
  /// `.f3d` models (and `.f3dsplat` captures), one per input: the bundle,
  /// with the model's materials, its `.f3dmat` programs, a scene's prefabs
  /// and the files a scene names inside it. The only kind that can be
  /// saved to the cabinet, because a cabinet entry is a model.
  model('model', 'Model (.f3d)'),

  /// `.fmat` and `.f3dmat` materials, with the textures they name.
  material('material', 'Material (.fmat, .f3dmat)'),

  /// A level document with the prefabs, models, materials and textures it
  /// refers to: everything the conversion wrote.
  level('level', 'Prefab or level (.level.json and what it uses)');

  const ConversionTarget(this.column, this.label);

  /// What the form sends and the result page's address carries.
  final String column;
  final String label;

  static ConversionTarget? of(String? column) =>
      values.where((t) => t.column == column).firstOrNull;

  /// Whether the conversion is asked for one `.f3d` bundle per input
  /// (`convertFiles`' default), rather than the sidecar layout of
  /// `convertFiles(bundle: false)`.
  ///
  /// Only [model] bundles: a bundle carries its materials and level
  /// documents inside the `.f3d`, so [material] and [level], which offer
  /// those as files, would come back with nothing to offer.
  bool get bundles => this == model;

  /// Whether an output at [path] is one this target offers.
  bool offers(String path) {
    final lower = path.toLowerCase();
    return switch (this) {
      model => lower.endsWith('.f3d') || lower.endsWith('.f3dsplat'),
      material =>
        lower.endsWith('.fmat') ||
            lower.endsWith('.f3dmat') ||
            lower.startsWith('textures/'),
      level => true,
    };
  }
}

/// One file a conversion produced, by its path relative to the output.
final class ConvertedFile {
  const ConvertedFile(this.path, this.bytes);

  /// `/`-separated, as the converter laid it out: `chair.f3d`,
  /// `materials/oak.fmat`, `textures/oak_albedo.png`.
  final String path;
  final Uint8List bytes;

  /// Whether this is a model the cabinet can keep.
  bool get isModel => path.toLowerCase().endsWith('.f3d');
}

/// What one input became: the converter's own report, with the paths the
/// server wrote it under taken out.
final class InputReport {
  const InputReport({
    required this.input,
    required this.format,
    required this.outcome,
    required this.error,
    required this.written,
    required this.mapped,
    required this.dropped,
    required this.warnings,
  });

  /// The input's path inside the upload.
  final String input;

  /// What it was read as: `gltf`, `unity-prefab`, `godot-scene`, …
  final String format;

  /// `converted`, `failed` or `missing-tool`.
  final String outcome;
  final String? error;
  final List<String> written;
  final List<String> mapped;

  /// What the source said that did not arrive, with the reason.
  final List<String> dropped;

  /// What arrived, but approximated.
  final List<String> warnings;

  bool get converted => outcome == build.ConvertOutcome.converted.name;

  /// Needed a program this server does not run (FBX2glTF, Blender, usdcat).
  bool get neededExternalTool =>
      outcome == build.ConvertOutcome.missingTool.name;
}

/// How a conversion ended.
sealed class ConversionOutcome {
  const ConversionOutcome();
}

/// The converter ran. [files] may still be empty — every input failed, or
/// none gave the kind of output asked for — and [reports] say why.
final class ConversionDone extends ConversionOutcome {
  const ConversionDone({
    required this.files,
    required this.reports,
    required this.notOffered,
    this.original,
  });

  /// What the chosen target offers, in path order.
  final List<ConvertedFile> files;
  final List<InputReport> reports;

  /// Outputs the conversion produced that the chosen target does not offer,
  /// so the page can say "this gave a level; ask for that".
  final List<String> notOffered;

  /// What "Save to my models" keeps instead of the `.f3d`, when the upload
  /// was already a format the service stores. Null otherwise.
  final KeepableOriginal? original;
}

/// The upload itself, as the service would store it: kept by "Save to my
/// models" in place of the converted `.f3d`, so nothing the `.f3d` cannot
/// carry — a glTF extension the engine does not read — is lost by keeping
/// it.
final class KeepableOriginal {
  const KeepableOriginal({
    required this.fileName,
    required this.bytes,
    this.writtenFrom,
  });

  /// What it is kept as: `chair.glb`.
  final String fileName;
  final Uint8List bytes;

  /// Set when these are not the uploaded bytes but a GLB written from the
  /// `.gltf` or `.obj` at this path in the archive — one that refers to
  /// files beside it, which cannot be kept as one file.
  final String? writtenFrom;

  /// Whether the bytes are the upload's own.
  bool get asUploaded => writtenFrom == null;
}

/// The suffixes of what `models.source_format` can hold — `SourceFormat`.
const _storableSuffixes = <String>{'.glb', '.gltf', '.obj', '.f3d', '.f3dproj'};

bool _storable(String path) {
  final lower = path.toLowerCase();
  return _storableSuffixes.any(lower.endsWith);
}

/// Nothing was converted, and [because] says why in a sentence for the
/// person who sent the file: an archive refused, a deadline passed.
final class ConversionRefused extends ConversionOutcome {
  const ConversionRefused(this.because);

  final String because;
}

/// Converts [bytes] — one source file, or a `.zip` of a folder — and returns
/// what [target] offers of the result.
///
/// [fileName] is what the person called the file; its extension is how most
/// inputs are recognised, so it is kept (without any directory part).
Future<ConversionOutcome> convertUpload(
  Uint8List bytes, {
  required String fileName,
  required ConversionTarget target,
  Duration deadline = conversionDeadline,
  int expansionBudget = conversionExpansionBudget,
}) async {
  final name = safeUploadName(fileName);
  if (bytes.isEmpty) return ConversionRefused('$name is empty.');

  final work = await Directory.systemTemp.createTemp('flutter3d-convert-');
  try {
    // Killed at the deadline, not abandoned — see `killable.dart`.
    final answer = await runKillable<_Job>(
      _convertInIsolate,
      (reply) => _Job(
        reply: reply,
        work: p.normalize(work.absolute.path),
        bytes: bytes,
        name: name,
        target: target,
        budget: expansionBudget,
      ),
      deadline: deadline,
      debugName: 'convert $name',
    );
    return switch (answer) {
      Answered(message: final ConversionOutcome outcome) => outcome,
      TimedOut() => ConversionRefused(
        'Converting $name took longer than ${describeDuration(deadline)}, so '
        'it was stopped and nothing was kept. A smaller part of the scene, or '
        'a folder with fewer files in it, may convert in time.',
      ),
      _ => ConversionRefused(
        'The converter stopped before it finished $name. Nothing was kept.',
      ),
    };
  } finally {
    try {
      await work.delete(recursive: true);
    } on FileSystemException {
      // Under systemd this is a private /tmp, emptied when the unit stops.
    }
  }
}

/// [fileName] without a directory, quotes or control characters, and never
/// empty.
String safeUploadName(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last.trim();
  final clean = base.replaceAll(RegExp(r'[\x00-\x1f"]'), '');
  return clean.isEmpty || clean == '.' || clean == '..' ? 'upload' : clean;
}

final class _Job {
  const _Job({
    required this.reply,
    required this.work,
    required this.bytes,
    required this.name,
    required this.target,
    required this.budget,
  });

  final SendPort reply;
  final String work;
  final Uint8List bytes;
  final String name;
  final ConversionTarget target;
  final int budget;
}

Future<void> _convertInIsolate(_Job job) async {
  final outcome = await _convertHere(job);
  Isolate.exit(job.reply, outcome);
}

Future<ConversionOutcome> _convertHere(_Job job) async {
  try {
    final isArchive =
        looksLikeZip(job.bytes) && !job.name.toLowerCase().endsWith('.usdz');
    final Map<String, Uint8List> files;
    if (isArchive) {
      files = unzipGuarded(job.bytes, budget: job.budget);
      if (files.isEmpty) {
        return const ConversionRefused('The archive has no files in it.');
      }
      final unpacked = files.values.fold(0, (sum, b) => sum + b.length);
      // A `.usdz` inside the folder is a ZIP the converter will inflate
      // with no cap of its own, so it is measured against what is left.
      files.values
          .where(looksLikeZip)
          .fold(
            unpacked,
            (spent, nested) =>
                spent + measureZip(nested, budget: job.budget - spent),
          );
    } else {
      if (looksLikeZip(job.bytes)) measureZip(job.bytes, budget: job.budget);
      files = <String, Uint8List>{job.name: job.bytes};
    }
    // `convertFiles` lays the bundle out under the system's temporary
    // directory, which the confinement answers with [job.work] — so the
    // readers see the upload and nothing else, and what they leave behind
    // is deleted with [job.work] even when this isolate is killed.
    final result = await confinedTo(
      job.work,
      () => build.convertFiles(
        files,
        // Every output, filtered here by [ConversionTarget.offers], so the
        // page can also say what the conversion made that was not asked for.
        to: build.ConversionTarget.everything,
        // A model is one `.f3d` per input, the bundle: its materials,
        // programs, the scene's prefabs and every file a scene names travel
        // inside it. A material or a level is asked for as files of their
        // own, so those two take the sidecar layout, where `.fmat`,
        // `.f3dmat`, `textures/` and `.level.json` are outputs to offer.
        bundle: job.target.bundles,
      ),
    );
    if (result.reports.isEmpty) {
      return ConversionRefused(
        'Nothing in ${job.name} is a format this converts. See the list '
        'below the form.',
      );
    }
    final offered = <ConvertedFile>[
      for (final MapEntry(:key, :value) in result.files.entries)
        if (job.target.offers(key)) ConvertedFile(key, value),
    ];
    return ConversionDone(
      files: offered,
      reports: <InputReport>[
        for (final report in result.reports) _reportOf(report, job.work),
      ],
      notOffered: <String>[
        for (final key in result.files.keys)
          if (!job.target.offers(key)) key,
      ],
      original: job.target == ConversionTarget.model
          ? await _keepableOriginal(files, offered, result.reports)
          : null,
    );
  } on ZipRefused catch (refused) {
    return ConversionRefused(refused.message);
  } on Object catch (error) {
    return ConversionRefused(
      '${job.name} could not be converted: ${_scrub('$error', job.work)}',
    );
  }
}

/// The upload as the service would keep it, when it is one model in a format
/// the service stores and that model is what the one `.f3d` came from;
/// otherwise null, and "Save to my models" keeps the `.f3d`.
///
/// A file that reads on its own (a `.glb`, a self-contained `.gltf`, an
/// `.obj` with nothing beside it) is kept byte for byte. A `.gltf` or `.obj`
/// in an archive that refers to its `.bin`, `.mtl` or textures cannot be
/// stored as one file, so it is read with the archive around it and kept as
/// a GLB the engine's writer makes of it.
Future<KeepableOriginal?> _keepableOriginal(
  Map<String, Uint8List> files,
  List<ConvertedFile> offered,
  List<build.ConvertReport> reports,
) async {
  final models = offered.where((file) => file.isModel).toList();
  final candidates = files.keys.where(_storable).toList();
  if (models.length != 1 || candidates.length != 1) return null;
  final path = candidates.single;
  // Only when the `.f3d` is this file's: an archive with a Unity prefab and
  // one `.obj` beside it may have made its model out of something else.
  final madeIt = reports.any(
    (report) =>
        report.input == path && report.written.contains(models.single.path),
  );
  if (!madeIt) return null;

  final bytes = files[path]!;
  final fileName = safeUploadName(path);
  if (await inspectInPlace(bytes, fileName) is Accepted) {
    return KeepableOriginal(fileName: fileName, bytes: bytes);
  }
  final lower = path.toLowerCase();
  if (!lower.endsWith('.gltf') && !lower.endsWith('.obj')) return null;
  try {
    final document = await decodeModelBytes(
      ModelLoadRequest(
        source: _ArchiveEntry(path, files),
        format: lower.endsWith('.obj') ? ModelFormat.obj : ModelFormat.gltf,
      ),
      bytes,
      _ArchiveEntry(path, files).resolveUri,
    );
    final stem = fileName.substring(0, fileName.lastIndexOf('.'));
    final glbName = '${stem.isEmpty ? 'model' : stem}.glb';
    final glb = const GlbModelWriter()
        .write(document, baseName: stem.isEmpty ? 'model' : stem)
        .files
        .first
        .bytes;
    if (await inspectInPlace(glb, glbName) is! Accepted) return null;
    return KeepableOriginal(fileName: glbName, bytes: glb, writtenFrom: path);
  } on Object {
    // Whatever stops this read, the `.f3d` the converter made is still there
    // to keep.
    return null;
  }
}

/// A file inside an unpacked archive, whose references are looked up among
/// the archive's other files — relative to its own folder, never outside
/// the archive.
final class _ArchiveEntry extends AssetSource {
  const _ArchiveEntry(this._path, this._files);

  final String _path;
  final Map<String, Uint8List> _files;

  @override
  String get key => 'archive:$_path';

  @override
  Future<Uint8List> read() async => _files[_path]!;

  @override
  AssetUriResolver get resolveUri => _resolve;

  Future<Uint8List> _resolve(AssetRequest request) async {
    if (request.uri.startsWith('data:')) return decodeDataUri(request.uri);
    final relative = safeRelativeAssetPath(request.uri).replaceAll(r'\', '/');
    final folder = p.posix.dirname(_path);
    final wanted = p.posix.normalize(
      folder == '.' ? relative : '$folder/$relative',
    );
    final found = _files[wanted];
    if (found == null) {
      throw StateError('"${request.uri}" is not in the archive.');
    }
    return found;
  }
}

InputReport _reportOf(build.ConvertReport report, String work) {
  String scrub(String line) => _scrub(line, work);
  return InputReport(
    input: scrub(report.input),
    format: report.format,
    outcome: report.outcome.name,
    error: switch (report.error) {
      final String error => scrub(error),
      null => null,
    },
    written: <String>[...report.written]..sort(),
    mapped: report.mapped.map(scrub).toList(),
    dropped: report.dropped.map(scrub).toList(),
    warnings: report.warnings.map(scrub).toList(),
  );
}

/// [line] with the server's own directories taken out, so a report names
/// files the way the person's archive named them.
/// `convertFiles` already takes its own directory out; this catches what is
/// left, such as an exception's message.
String _scrub(String line, String work) => line.replaceAll(work, '…');
