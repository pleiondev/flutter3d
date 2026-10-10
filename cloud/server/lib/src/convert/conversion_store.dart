/// Where a conversion's result waits to be downloaded or saved.
///
/// **Short-lived, owned, and outside the blob store.** A result is kept for
/// [ConversionStore.keepFor] under a random id, and only the account that
/// made it gets anything back for that id — anybody else gets the same 404
/// an id that never existed gets. The files are written under a temporary
/// directory (under systemd, the unit's private `/tmp`) rather than into the
/// content-addressed blobs, because nothing in the database refers to them
/// and a blob nothing refers to is one nobody would ever delete. "Save to my
/// models" copies a model out of here through the ordinary upload path.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'converter.dart';
import 'zip_writer.dart';

/// One file of a held result.
final class HeldFile {
  const HeldFile({
    required this.path,
    required this.sizeBytes,
    required this.diskName,
  });

  /// As the converter laid it out: `chair.f3d`, `materials/oak.fmat`.
  final String path;
  final int sizeBytes;

  /// Its name on disk — a number, never [path], so nothing a converted file
  /// is called decides where it is written.
  final String diskName;

  /// The name a download is offered under.
  String get fileName => path.split('/').last;

  bool get isModel => path.toLowerCase().endsWith('.f3d');
}

/// The upload, kept beside a result because "Save to my models" keeps it
/// instead of the `.f3d` — see `KeepableOriginal`.
final class HeldOriginal {
  const HeldOriginal({
    required this.fileName,
    required this.sizeBytes,
    required this.writtenFrom,
  });

  /// What it is kept as: `chair.glb`.
  final String fileName;
  final int sizeBytes;

  /// The `.gltf` or `.obj` in the archive a GLB was written from, or null
  /// when these are the uploaded bytes.
  final String? writtenFrom;

  bool get asUploaded => writtenFrom == null;
}

/// A conversion waiting to be fetched.
final class HeldConversion {
  const HeldConversion({
    required this.id,
    required this.ownerId,
    required this.sourceName,
    required this.target,
    required this.createdAt,
    required this.expiresAt,
    required this.files,
    required this.reports,
    required this.notOffered,
    this.original,
  });

  final String id;
  final int ownerId;

  /// What the person called the file they sent.
  final String sourceName;
  final ConversionTarget target;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<HeldFile> files;
  final List<InputReport> reports;
  final List<String> notOffered;

  /// What "Save to my models" keeps in place of the model file, when the
  /// upload was already a format the service stores.
  final HeldOriginal? original;

  String get path => '/convert/$id';

  /// The one model file the original stands for, or null. The original is
  /// only kept in place of a `.f3d` when the result has exactly one.
  HeldFile? get modelFile {
    final models = files.where((f) => f.isModel).toList();
    return models.length == 1 ? models.single : null;
  }

  /// What saving [file] keeps: the original when it stands for [file],
  /// otherwise the file itself.
  bool savesOriginalFor(HeldFile file) =>
      original != null && modelFile?.path == file.path;

  /// Whether "download all" is offered: more than one file.
  bool get hasArchive => files.length > 1;

  /// The name "download all" is offered under.
  String get archiveName {
    final dot = sourceName.lastIndexOf('.');
    final stem = dot > 0 ? sourceName.substring(0, dot) : sourceName;
    return '$stem-${target.column}.zip';
  }
}

class ConversionStore {
  ConversionStore({
    required this.root,
    this.keepFor = const Duration(hours: 1),
    DateTime Function()? clock,
    Duration? sweepEvery = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now {
    if (sweepEvery != null) {
      _sweeper = Timer.periodic(sweepEvery, (_) => unawaited(sweep()));
    }
  }

  /// A store under a fresh directory in the system's temporary directory.
  factory ConversionStore.inSystemTemp() => ConversionStore(
    root: Directory.systemTemp.createTempSync('flutter3d-conversions-'),
  );

  final Directory root;

  /// How long a result is kept after it is made.
  final Duration keepFor;

  final DateTime Function() _clock;
  Timer? _sweeper;
  final Map<String, HeldConversion> _held = <String, HeldConversion>{};
  final Random _random = Random.secure();

  static final RegExp _idShape = RegExp(r'^[0-9a-f]{32}$');

  /// Keeps [done]'s files for [ownerId] and returns what was kept.
  Future<HeldConversion> keep({
    required int ownerId,
    required String sourceName,
    required ConversionTarget target,
    required ConversionDone done,
  }) async {
    await sweep();
    final id = List<String>.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final directory = Directory('${root.path}/$id');
    await directory.create(recursive: true);
    final files = <HeldFile>[
      for (final (index, file) in done.files.indexed)
        HeldFile(
          path: file.path,
          sizeBytes: file.bytes.length,
          diskName: '$index',
        ),
    ];
    for (final (index, file) in done.files.indexed) {
      await File('${directory.path}/$index').writeAsBytes(file.bytes);
    }
    if (done.files.length > 1) {
      await File('${directory.path}/all.zip').writeAsBytes(
        storedZip(<(String, Uint8List)>[
          for (final file in done.files) (file.path, file.bytes),
        ]),
      );
    }
    final kept = done.original;
    if (kept != null) {
      await File('${directory.path}/original').writeAsBytes(kept.bytes);
    }
    final now = _clock();
    final held = HeldConversion(
      id: id,
      ownerId: ownerId,
      sourceName: sourceName,
      target: target,
      createdAt: now,
      expiresAt: now.add(keepFor),
      files: files,
      reports: done.reports,
      notOffered: done.notOffered,
      original: kept == null
          ? null
          : HeldOriginal(
              fileName: kept.fileName,
              sizeBytes: kept.bytes.length,
              writtenFrom: kept.writtenFrom,
            ),
    );
    _held[id] = held;
    return held;
  }

  /// The original [held] keeps in place of its model, or null.
  File? originalOf(HeldConversion held) =>
      held.original == null ? null : File('${root.path}/${held.id}/original');

  /// Where an export of [file] as [format] is cached beside the result,
  /// with whether it is a `.zip`; null until one has been written.
  ({File disk, bool zipped})? exportOf(
    HeldConversion held,
    HeldFile file,
    String format,
  ) => _exports['${held.id}/${file.diskName}/$format'];

  /// Writes an export of [file] as [format] beside the result, where
  /// [exportOf] finds it, and returns it. Deleted with the result.
  Future<({File disk, bool zipped})> keepExport(
    HeldConversion held,
    HeldFile file,
    String format, {
    required Uint8List bytes,
    required bool zipped,
  }) async {
    final disk = File('${root.path}/${held.id}/${file.diskName}.$format');
    await disk.writeAsBytes(bytes);
    final kept = (disk: disk, zipped: zipped);
    _exports['${held.id}/${file.diskName}/$format'] = kept;
    return kept;
  }

  final Map<String, ({File disk, bool zipped})> _exports =
      <String, ({File disk, bool zipped})>{};

  /// The result [id], if it exists, has not expired and belongs to
  /// [ownerId]; otherwise null, the same null for each of the three.
  HeldConversion? find(String id, int ownerId) {
    if (!_idShape.hasMatch(id)) return null;
    final held = _held[id];
    if (held == null || held.ownerId != ownerId) return null;
    if (!_clock().isBefore(held.expiresAt)) return null;
    return held;
  }

  /// The file of [held] at [path], or null when [held] has no such file.
  /// [path] is looked up among the result's own files, never joined onto a
  /// directory.
  ({HeldFile file, File disk})? fileOf(HeldConversion held, String path) {
    final file = held.files.where((f) => f.path == path).firstOrNull;
    if (file == null) return null;
    return (file: file, disk: File('${root.path}/${held.id}/${file.diskName}'));
  }

  /// "Download all", or null when [held] has one file or none.
  File? archiveOf(HeldConversion held) =>
      held.hasArchive ? File('${root.path}/${held.id}/all.zip') : null;

  /// Forgets and deletes every result past its time.
  Future<void> sweep() async {
    final now = _clock();
    final expired = <String>[
      for (final held in _held.values)
        if (!now.isBefore(held.expiresAt)) held.id,
    ];
    for (final id in expired) {
      _held.remove(id);
      _exports.removeWhere((key, _) => key.startsWith('$id/'));
      final directory = Directory('${root.path}/$id');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  /// Stops the periodic sweep. The files stay until [sweep] or the
  /// temporary directory itself goes.
  void close() => _sweeper?.cancel();
}
