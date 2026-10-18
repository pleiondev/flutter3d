/// `/convert` and what hangs off it: the form, the upload a script sends, the
/// result, its downloads, and "Save to my models".
///
/// **Who is asking, and the store, are handed in.** Every other page reads
/// the session through [Services]; these take a function instead, so their
/// test can run every rule — signed out, unconfirmed, a forged form, another
/// account's result — with no database, the way `dart test -x db` runs.
///
/// **No rate limit, by decision.** Converting is open to every account with a
/// confirmed address as often as it likes. What protects the process is in
/// `convert/converter.dart`: the upload limit every upload has, an isolate
/// killed at its deadline, and an archive unpacked under a budget.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../convert/conversion_store.dart';
import '../convert/converter.dart';
import '../convert/exporter.dart';
import '../domain/access.dart';
import '../domain/model.dart' show formatBytes;
import '../domain/user.dart';
import '../pages/convert_page.dart';
import '../pages/plain_pages.dart';
import 'cookies.dart';
import 'render.dart';
import 'request.dart';

/// How a converted model went into the cabinet.
sealed class SaveOutcome {
  const SaveOutcome();
}

/// Kept; [path] is the new model's page.
final class SavedModel extends SaveOutcome {
  const SavedModel(this.id, this.path);

  final int id;
  final String path;
}

/// Not kept, for [because] — what `inspectUpload` said about the file.
final class SaveRefused extends SaveOutcome {
  const SaveRefused(this.because);

  final String because;
}

/// Stores [bytes] as a new model of [user]'s, through the same reading and
/// storing an upload goes through.
typedef SaveModel =
    Future<SaveOutcome> Function(User user, String fileName, Uint8List bytes);

/// Runs a conversion. [convertUpload] in the service; a test hands in one
/// that answers at once.
typedef Convert =
    Future<ConversionOutcome> Function(
      Uint8List bytes, {
      required String fileName,
      required ConversionTarget target,
    });

class ConversionRoutes {
  ConversionRoutes({
    required this.whoIs,
    required this.policy,
    required this.store,
    required this.uploadLimitBytes,
    required this.saveModel,
    Convert? convert,
    ExportRun? export,
  }) : convert = convert ?? _convertUpload,
       export = export ?? _exportModel;

  final Future<User?> Function(Request request) whoIs;
  final CookiePolicy policy;
  final ConversionStore store;

  /// `MODELS_UPLOAD_LIMIT`, the same for a file to convert as for a model.
  final int uploadLimitBytes;
  final SaveModel saveModel;
  final Convert convert;

  /// "Download as…" on a model in the result: [exportModel] in the service.
  final ExportRun export;

  /// One export of one held file in one format at a time.
  final ExportRuns<ExportOutcome> _exporting = ExportRuns<ExportOutcome>();

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

  static Future<ConversionOutcome> _convertUpload(
    Uint8List bytes, {
    required String fileName,
    required ConversionTarget target,
  }) => convertUpload(bytes, fileName: fileName, target: target);

  /// Adds every route to [router].
  void addTo(Router router) {
    router
      ..get('/convert', _form)
      ..post('/api/v1/conversions', _upload)
      ..get('/convert/<id|[0-9a-f]{32}>', _result)
      ..get('/convert/<id|[0-9a-f]{32}>/file', _file)
      ..get('/convert/<id|[0-9a-f]{32}>/all.zip', _archive)
      ..get('/convert/<id|[0-9a-f]{32}>/as/<format|[a-z0-9]+>', _exportAs)
      ..post('/convert/<id|[0-9a-f]{32}>/save', _save);
  }

  /// The routes on their own, for a test.
  Handler get handler {
    final router = Router(notFoundHandler: (Request request) => _notFound());
    addTo(router);
    return router.call;
  }

  String _csrf(Request request) => cookiesOf(request)[policy.csrfName] ?? '';

  Future<Response> _form(Request request) async => htmlPage(
    ConvertPage(
      signedIn: await whoIs(request),
      csrf: _csrf(request),
      uploadLimitBytes: uploadLimitBytes,
    ),
  );

  /// The file, as the body; what it is called and what to make of it, as
  /// headers — the shape `/api/v1/models` takes, so `convert.js` can show
  /// progress the way `upload.js` does.
  Future<Response> _upload(Request request) async {
    if (!formIsOurs(request, {'csrf': ?request.headers['x-csrf']}, policy)) {
      return json(403, {'error': 'This page is out of date. Reload it.'});
    }
    final user = await whoIs(request);
    if (user == null) return json(401, {'error': 'Sign in again.'});
    if (!canUpload(user)) {
      return json(403, {'error': 'Confirm your address before converting.'});
    }
    final target = ConversionTarget.of(request.headers['x-target']);
    if (target == null) {
      return json(422, {'error': 'Choose what to convert the file to.'});
    }
    final fileName = safeUploadName(_decoded(request.headers['x-filename']));
    final bytes = await readBody(request, limit: uploadLimitBytes);
    if (bytes == null) {
      return json(413, {
        'error': '$fileName is larger than ${formatBytes(uploadLimitBytes)}.',
      });
    }
    switch (await convert(bytes, fileName: fileName, target: target)) {
      case ConversionRefused(:final because):
        return json(422, {'error': because});
      case final ConversionDone done:
        final held = await store.keep(
          ownerId: user.id,
          sourceName: fileName,
          target: target,
          done: done,
        );
        return json(201, {'id': held.id, 'path': held.path});
    }
  }

  Future<Response> _result(Request request, String id) async {
    final user = await whoIs(request);
    if (user == null) return seeOther('/login?next=/convert/$id');
    final held = store.find(id, user.id);
    if (held == null) return _gone(user, _csrf(request));
    return htmlPage(
      ConversionResultPage(
        user: user,
        csrf: _csrf(request),
        held: held,
        uploadLimitBytes: uploadLimitBytes,
      ),
    );
  }

  Future<Response> _file(Request request, String id) async {
    final user = await whoIs(request);
    final held = user == null ? null : store.find(id, user.id);
    final path = request.url.queryParameters['path'];
    final found = held == null || path == null
        ? null
        : store.fileOf(held, path);
    if (found == null) return _notFound(user);
    return _download(found.disk, found.file.fileName);
  }

  Future<Response> _archive(Request request, String id) async {
    final user = await whoIs(request);
    final held = user == null ? null : store.find(id, user.id);
    final archive = held == null ? null : store.archiveOf(held);
    if (held == null || archive == null) return _notFound(user);
    return _download(archive, held.archiveName);
  }

  /// "Download as…" for a model in a held result: `?path=` names the `.f3d`,
  /// the address names the format. Written on the first request, kept beside
  /// the result for as long as the result is, and nobody else's to fetch.
  Future<Response> _exportAs(Request request, String id, String name) async {
    final user = await whoIs(request);
    final held = user == null ? null : store.find(id, user.id);
    final path = request.url.queryParameters['path'];
    final found = held == null || path == null
        ? null
        : store.fileOf(held, path);
    final format = ExportFormat.of(name);
    if (held == null ||
        found == null ||
        !found.file.isModel ||
        format == null ||
        format == ExportFormat.original) {
      return _notFound(user);
    }
    final baseName = exportBaseName(found.file.fileName);
    if (format == ExportFormat.f3d) {
      return _download(found.disk, found.file.fileName);
    }
    final cached = store.exportOf(held, found.file, format.column);
    if (cached != null) {
      return _download(
        cached.disk,
        format.fileNameFor(baseName, zipped: cached.zipped),
        contentType: cached.zipped ? 'application/zip' : format.contentType,
      );
    }
    final outcome = await _exporting.once(
      '${held.id}/${found.file.diskName}/${format.column}',
      () async {
        final again = store.exportOf(held, found.file, format.column);
        if (again != null) {
          return Exported(
            ExportedFile(
              bytes: await again.disk.readAsBytes(),
              contentType: again.zipped
                  ? 'application/zip'
                  : format.contentType,
              zipped: again.zipped,
            ),
          );
        }
        final written = await export(
          await found.disk.readAsBytes(),
          sourceName: found.file.fileName,
          format: format,
          baseName: baseName,
        );
        if (written case Exported(:final file)) {
          await store.keepExport(
            held,
            found.file,
            format.column,
            bytes: file.bytes,
            zipped: file.zipped,
          );
        }
        return written;
      },
    );
    return switch (outcome) {
      Exported() => _download(
        store.exportOf(held, found.file, format.column)!.disk,
        format.fileNameFor(baseName, zipped: outcome.file.zipped),
        contentType: outcome.file.contentType,
      ),
      ExportRefused(:final because) => htmlPage(
        MessagePage(
          title: 'Not written as ${format.column}',
          body: because,
          signedIn: user,
          action: ('Back to the result', held.path),
        ),
        status: 422,
      ),
    };
  }

  /// "Save to my models": a model out of a held result, stored the way an
  /// upload is — read again by `inspectUpload`, so only what the service can
  /// open is kept, and under the same upload limit.
  Future<Response> _save(Request request, String id) async {
    final form = await readForm(request);
    if (!formIsOurs(request, form, policy)) {
      return htmlPage(
        MessagePage(
          title: 'This page was out of date',
          body:
              'The form was sent from a page opened before something changed '
              '— a sign-out, or cookies being cleared. Go back, reload, and '
              'send it again.',
          signedIn: await whoIs(request),
        ),
        status: 403,
      );
    }
    final user = await whoIs(request);
    if (user == null) return seeOther('/login?next=/convert/$id');
    if (!canUpload(user)) {
      return htmlPage(
        MessagePage(
          title: 'Confirm your address first',
          body: 'Models are kept for accounts with a confirmed address.',
          signedIn: user,
          action: ('Go to my models', '/me'),
        ),
        status: 403,
      );
    }
    final held = store.find(id, user.id);
    if (held == null) return _gone(user, _csrf(request));
    final found = store.fileOf(held, form['file'] ?? '');
    if (found == null || !found.file.isModel) return _notFound(user);
    // The upload itself when it was already a format the service stores —
    // a `.glb` keeps the glTF extensions its `.f3d` could not carry — and
    // the converted `.f3d` for everything else.
    final original = held.savesOriginalFor(found.file)
        ? (held.original!, store.originalOf(held)!)
        : null;
    final keptName = original?.$1.fileName ?? found.file.fileName;
    final keptSize = original?.$1.sizeBytes ?? found.file.sizeBytes;
    if (keptSize > uploadLimitBytes) {
      return htmlPage(
        MessagePage(
          title: 'Too large to keep',
          body:
              '$keptName is larger than '
              '${formatBytes(uploadLimitBytes)}, the most a model kept here '
              'may be. It can still be downloaded.',
          signedIn: user,
          action: ('Back to the result', held.path),
        ),
        status: 413,
      );
    }
    final bytes = await (original?.$2 ?? found.disk).readAsBytes();
    return switch (await saveModel(user, keptName, bytes)) {
      SavedModel(:final path) => seeOther('$path?said=converted'),
      SaveRefused(:final because) => htmlPage(
        MessagePage(
          title: 'Not kept',
          body: because,
          signedIn: user,
          action: ('Back to the result', held.path),
        ),
        status: 422,
      ),
    };
  }

  /// A result that is not this account's, never was, or has expired: one
  /// answer for the three, so an id says nothing about anybody else.
  Future<Response> _gone(User user, String csrf) => htmlPage(
    ConvertPage(
      signedIn: user,
      csrf: csrf,
      uploadLimitBytes: uploadLimitBytes,
      error:
          'That conversion is not here. Results are kept for an hour, and '
          'only for the account that made them.',
    ),
    status: 404,
  );

  Future<Response> _notFound([User? viewer]) =>
      htmlPage(NotFoundPage(signedIn: viewer), status: 404);
}

Future<Response> _download(
  File disk,
  String name, {
  String? contentType,
}) async {
  if (!await disk.exists()) {
    return Response.internalServerError(body: 'The file is missing.');
  }
  final clean = name.replaceAll(RegExp(r'[\x00-\x1f"\\]'), '');
  return Response.ok(
    disk.openRead(),
    headers: {
      'content-type': contentType ?? _contentType(name),
      'content-length': '${await disk.length()}',
      'cache-control': 'private, no-store',
      'content-disposition':
          'attachment; filename="$clean"; '
          "filename*=UTF-8''${Uri.encodeComponent(name)}",
    },
  );
}

String _contentType(String name) => switch (name.toLowerCase()) {
  final n when n.endsWith('.json') => 'application/json',
  final n when n.endsWith('.png') => 'image/png',
  final n when n.endsWith('.jpg') || n.endsWith('.jpeg') => 'image/jpeg',
  final n when n.endsWith('.zip') => 'application/zip',
  _ => 'application/octet-stream',
};

/// A header a script percent-encoded, or the raw value when it is not.
String _decoded(String? header) {
  if (header == null || header.isEmpty) return 'upload';
  try {
    return Uri.decodeComponent(header);
  } on ArgumentError {
    return header;
  }
}
