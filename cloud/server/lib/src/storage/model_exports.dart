/// `/files/<id>/as/<format>`: a stored model in the format asked for, written
/// once and kept.
///
/// **Cached by what was written.** An export is a blob like any other,
/// recorded in `model_exports` under the source's hash, the format and
/// [exportWriterVersion], so the second request — from anybody, for any
/// model holding the same file — is a read. Rows go with their model, and
/// with the source they were made from when it is replaced; their blobs are
/// freed through `isReferenced` like every other blob here.
///
/// **Who may ask is decided by the caller**, the same `canView` that guards
/// `/files/<id>/source`.
library;

import 'dart:typed_data';

import '../convert/exporter.dart';
import '../db/models_repository.dart';
import 'blob_store.dart';
import 'inspect.dart';

/// How a request for an export ended.
sealed class ExportAnswer {
  const ExportAnswer();
}

/// [file] is the download, named for the asking model.
final class ExportReady extends ExportAnswer {
  const ExportReady(this.file, {this.inline});

  final StoredFile file;

  /// The bytes themselves, when they were written for a source that was
  /// replaced meanwhile and so were not kept: sent once, from memory,
  /// instead of from the blob store.
  final Uint8List? inline;
}

/// Not written, for [because].
final class ExportFailed extends ExportAnswer {
  const ExportFailed(this.because);

  final String because;
}

class ModelExports {
  ModelExports({
    required this.blobs,
    required this.cache,
    ExportRun? run,
    this.writerVersion = exportWriterVersion,
  }) : run = run ?? _exportModel;

  final BlobStore blobs;
  final ExportCache cache;

  /// [exportModel] in the service: an isolate killed at `/convert`'s
  /// deadline.
  final ExportRun run;
  final int writerVersion;

  final ExportRuns<ExportAnswer> _running = ExportRuns<ExportAnswer>();

  static Future<ExportOutcome> _exportModel(
    Uint8List source, {
    required String sourceName,
    required ExportFormat format,
    required String baseName,
  }) => exportModel(
    source,
    sourceName: sourceName,
    format: format,
    baseName: baseName,
  );

  /// [source], the current source of model [modelId] stored as
  /// [sourceFormat], as [format].
  ///
  /// The stored file itself when it already is that format; otherwise the
  /// cached export, or a new one written, stored and recorded. Two requests
  /// for the same source and format at once share one write.
  Future<ExportAnswer> exportOf({
    required int modelId,
    required StoredFile source,
    required SourceFormat? sourceFormat,
    required ExportFormat format,
  }) async {
    if (format.isAlready(sourceFormat)) return ExportReady(source);
    final baseName = exportBaseName(source.filename);
    final answer = await _running.once(
      '${source.blobSha256}/${format.column}/$writerVersion',
      () => _cachedOrWritten(modelId, source, format, baseName),
    );
    return switch (answer) {
      ExportReady(:final file, :final inline) => ExportReady(
        StoredFile(
          blobSha256: file.blobSha256,
          bytes: file.bytes,
          contentType: file.contentType,
          filename: format.fileNameFor(
            baseName,
            zipped: file.contentType == 'application/zip',
          ),
        ),
        inline: inline,
      ),
      ExportFailed() => answer,
    };
  }

  Future<ExportAnswer> _cachedOrWritten(
    int modelId,
    StoredFile source,
    ExportFormat format,
    String baseName,
  ) async {
    final hit = await cache.exportOf(
      sourceSha256: source.blobSha256,
      format: format.column,
      writerVersion: writerVersion,
    );
    // A hit written for another model holding the same file is recorded for
    // this one too, so it stays referenced for as long as either model is.
    if (hit != null && await blobs.sizeOf(hit.blobSha256) != null) {
      await cache.keepExport(
        modelId: modelId,
        sourceSha256: source.blobSha256,
        format: format.column,
        writerVersion: writerVersion,
        file: hit,
      );
      return ExportReady(hit);
    }

    final bytes = await _read(source.blobSha256);
    if (bytes == null) return const ExportFailed('The stored file is missing.');
    switch (await run(
      bytes,
      sourceName: source.filename,
      format: format,
      baseName: baseName,
    )) {
      case ExportRefused(:final because):
        return ExportFailed(because);
      case Exported(:final file):
        final hash = await blobs.put(file.bytes);
        final stored = StoredFile(
          blobSha256: hash,
          bytes: file.bytes.length,
          contentType: file.contentType,
          filename: '',
        );
        final kept = await cache.keepExport(
          modelId: modelId,
          sourceSha256: source.blobSha256,
          format: format.column,
          writerVersion: writerVersion,
          file: stored,
        );
        // The source moved on while this was written: served once, and not
        // left on disk with nothing pointing at it.
        if (!kept && !await cache.isReferenced(hash)) {
          await blobs.delete(hash);
          return ExportReady(stored, inline: file.bytes);
        }
        return ExportReady(stored);
    }
  }

  Future<Uint8List?> _read(String sha256) async {
    final stream = await blobs.open(sha256);
    if (stream == null) return null;
    final builder = BytesBuilder(copy: false);
    await stream.forEach(builder.add);
    return builder.toBytes();
  }
}
