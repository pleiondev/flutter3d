/// The whole first release, walked through the real handler and a real database.
///
/// **No network and no browser, but nothing mocked in between.** Requests go
/// straight into the shelf handler the server runs, against Postgres, with the
/// letters caught by a quiet mailer and the files kept in memory. What this
/// proves is that the rules hold end to end: that a link works once, that a
/// private model is invisible to somebody else, that a reset signs out the
/// browser that was signed in.
@Tags(['db'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_models/main.server.options.dart';
import 'package:flutter3d_models/src/config.dart';
import 'package:flutter3d_models/src/db/database.dart';
import 'package:flutter3d_models/src/db/models_repository.dart';
import 'package:flutter3d_models/src/domain/model.dart';
import 'package:flutter3d_models/src/http/app.dart';
import 'package:flutter3d_models/src/mail/mailer.dart';
import 'package:flutter3d_models/src/services.dart';
import 'package:flutter3d_models/src/storage/blob_store.dart';
import 'package:jaspr/server.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:test/test.dart';

const _base = 'http://localhost:8793';
final _triangle = Uint8List.fromList(
  utf8.encode('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'),
);

/// A second, distinct, still-valid OBJ — a two-triangle quad — used to save
/// over a model that already exists.
final _quad = Uint8List.fromList(
  utf8.encode('v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3\nf 1 3 4\n'),
);

/// A third, distinct, still-valid OBJ — a three-triangle fan — for a second
/// save over the same model.
final _fan = Uint8List.fromList(
  utf8.encode(
    'v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0.5 1.5 0\nv 0 1 0\n'
    'f 1 2 3\nf 1 3 4\nf 1 4 5\n',
  ),
);

/// A minimal but well-formed PNG: the signature, then an `IHDR` chunk naming
/// [width] and [height]. No `IDAT` and no CRC — `inspectPreviewPng` never
/// reads past `IHDR`'s own 13 data bytes, so none of that is needed to be
/// accepted as a preview picture.
Uint8List _png(int width, int height) {
  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.add((ByteData(4)..setUint32(0, 13, Endian.big)).buffer.asUint8List());
  bytes.add('IHDR'.codeUnits);
  final data = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // color type: RGBA
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace
  bytes.add(data.buffer.asUint8List());
  return bytes.toBytes();
}

/// A browser's cookie jar, reduced to what this service sets.
class _Browser {
  _Browser(this.handler);

  final Handler handler;
  final cookies = <String, String>{};

  String get csrf => cookies['csrf'] ?? '';

  Future<Response> get(String path) =>
      _send(Request('GET', Uri.parse('$_base$path')));

  Future<Response> post(String path, Map<String, String> form) => _send(
    Request(
      'POST',
      Uri.parse('$_base$path'),
      body: Uri(queryParameters: {'csrf': csrf, ...form}).query,
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        'origin': _base,
      },
    ),
  );

  Future<Response> upload(String name, Uint8List bytes) => _send(
    Request(
      'POST',
      Uri.parse('$_base/api/v1/models'),
      body: bytes,
      headers: {
        'content-type': 'application/octet-stream',
        'x-csrf': csrf,
        'x-filename': Uri.encodeComponent(name),
        'origin': _base,
      },
    ),
  );

  Future<Response> uploadPreview(
    int modelId,
    Uint8List bytes, {
    required String sourceSha256,
  }) => _send(
    Request(
      'POST',
      Uri.parse('$_base/api/v1/models/$modelId/preview'),
      body: bytes,
      headers: {
        'content-type': 'image/png',
        'x-csrf': csrf,
        'x-source-sha256': sourceSha256,
        'origin': _base,
      },
    ),
  );

  Future<Response> saveSource(int modelId, String name, Uint8List bytes) =>
      _send(
        Request(
          'POST',
          Uri.parse('$_base/api/v1/models/$modelId/source'),
          body: bytes,
          headers: {
            'content-type': 'application/octet-stream',
            'x-csrf': csrf,
            'x-filename': Uri.encodeComponent(name),
            'origin': _base,
          },
        ),
      );

  Future<Response> _send(Request request) async {
    final withCookies = cookies.isEmpty
        ? request
        : request.change(
            headers: {
              'cookie': cookies.entries
                  .map((e) => '${e.key}=${e.value}')
                  .join('; '),
            },
          );
    final response = await handler(withCookies);
    for (final header
        in response.headersAll['set-cookie'] ?? const <String>[]) {
      final pair = header.split(';').first;
      final eq = pair.indexOf('=');
      final name = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      if (header.contains('Max-Age=0')) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
    return response;
  }
}

String _tokenIn(Letter letter) =>
    RegExp(r'token=([A-Za-z0-9_-]+)').firstMatch(letter.text)!.group(1)!;

void main() {
  late Database db;
  late Services services;
  late ConsoleMailer mailer;
  late MemoryBlobStore blobs;
  late Handler handler;

  setUpAll(() async {
    Jaspr.initializeApp(options: defaultServerOptions);
    final url =
        Platform.environment['MODELS_TEST_DATABASE_URL'] ??
        'postgres://models:models@localhost:55432/models';
    db = await Database.open(url);
    await db.run(
      (s) => s.execute('truncate users, rate_events restart identity cascade'),
    );

    mailer = ConsoleMailer(quiet: true);
    blobs = MemoryBlobStore();
    services = Services(
      config: const Config(
        port: 0,
        baseUrl: _base,
        databaseUrl: '',
        blobDirectory: '',
        mailFrom: 'models@example.com',
        resendApiKey: null,
        sessionSecret: 'test',
        uploadLimitBytes: 1024 * 1024,
      ),
      db: db,
      mailer: mailer,
      blobs: blobs,
    );
    Services.instance = services;
    handler = buildHandler(services);
  });

  tearDownAll(() => db.close());

  test('register, confirm, upload, keep it private, and get back in', () async {
    final ann = _Browser(handler);

    // A first visit hands out the CSRF cookie the form needs.
    expect((await ann.get('/register')).statusCode, 200);
    expect(ann.csrf, isNotEmpty);

    // A form without the token is refused, whatever else it carries.
    final forged = await _Browser(handler).post('/register', {
      'email': 'mallory@example.com',
      'password': 'long enough password',
    });
    expect(forged.statusCode, 403);

    // A typo in the second entry is caught, and nothing is created.
    final mistyped = await ann.post('/register', {
      'email': 'Ann@Example.com',
      'password': 'correct horse battery',
      'passwordConfirm': 'correct horse batterx',
    });
    expect(mistyped.statusCode, 422);
    expect(
      await mistyped.readAsString(),
      contains('The two passwords do not match.'),
    );

    // So is a password on every list, however well it is typed twice.
    final common = await ann.post('/register', {
      'email': 'Ann@Example.com',
      'password': 'Password2024!',
      'passwordConfirm': 'Password2024!',
    });
    expect(common.statusCode, 422);

    final registered = await ann.post('/register', {
      'email': 'Ann@Example.com',
      'displayName': 'Ann',
      'password': 'correct horse battery',
      'passwordConfirm': 'correct horse battery',
    });
    expect(registered.statusCode, 303);
    expect(registered.headers['location'], '/me?said=welcome');
    expect(ann.cookies['session'], isNotNull);
    expect(mailer.sent.last.to, 'Ann@Example.com');

    // The same address in another case is the same account.
    final again = await _Browser(handler).post('/register', {});
    expect(again.statusCode, 403);
    final twin = _Browser(handler);
    await twin.get('/register');
    final duplicate = await twin.post('/register', {
      'email': 'ann@example.com',
      'password': 'another long password',
    });
    expect(duplicate.statusCode, 422);

    // Signed in, but uploading waits for the address.
    expect((await ann.get('/me')).statusCode, 200);
    expect((await ann.upload('triangle.obj', _triangle)).statusCode, 403);

    final verifyToken = _tokenIn(
      mailer.sent.firstWhere((l) => l.subject.contains('Confirm')),
    );
    expect((await ann.get('/verify?token=$verifyToken')).statusCode, 200);
    expect(
      (await ann.get('/verify?token=$verifyToken')).statusCode,
      400,
      reason: 'a link works once',
    );

    // Something that is not a model is refused and not stored.
    final diary = await ann.upload(
      'diary.obj',
      Uint8List.fromList(utf8.encode('dear diary')),
    );
    expect(diary.statusCode, 422);
    expect(blobs.length, 0);

    final uploaded = await ann.upload('tiny_triangle.obj', _triangle);
    expect(uploaded.statusCode, 201);
    final body =
        jsonDecode(await uploaded.readAsString()) as Map<String, Object?>;
    final path = body['path']! as String;
    final id = body['id']! as int;
    expect(path, '/m/$id-tiny-triangle');

    final page = await ann.get(path);
    expect(page.statusCode, 200);
    final html = await page.readAsString();
    expect(html, contains('tiny triangle'));
    expect(await (await ann.get('/me')).readAsString(), contains('1 triangle'));

    // `tut-19`'s own preview-capture threading: the owner's own page names
    // itself editable and carries the source's real hash, both of which
    // `viewer.js` passes on to the build inside unchanged.
    expect(html, contains('data-editable="true"'));
    expect(html, contains('data-source-sha="${sha256.convert(_triangle)}"'));

    // A wrong slug redirects to the right one rather than failing.
    expect((await ann.get('/m/$id-old-name')).statusCode, 301);

    final download = await ann.get('/files/$id/source');
    expect(download.statusCode, 200);
    expect(await download.read().expand((chunk) => chunk).toList(), _triangle);

    // Nobody else sees it: not signed out, not another account.
    expect((await _Browser(handler).get(path)).statusCode, 404);
    expect((await _Browser(handler).get('/files/$id/source')).statusCode, 404);

    final bob = _Browser(handler);
    await bob.get('/register');
    expect(
      (await bob.post('/register', {
        'email': 'bob@example.com',
        'password': 'bob has a password',
        'passwordConfirm': 'bob has a password',
      })).statusCode,
      303,
    );
    expect((await bob.get(path)).statusCode, 404);
    expect((await bob.post('/m/$id/delete', {})).statusCode, 404);

    // Sign out, then back in.
    expect((await ann.post('/logout', {})).statusCode, 303);
    expect(ann.cookies['session'], isNull);
    expect((await ann.get('/me')).headers['location'], '/login?next=/me');

    final wrong = await ann.post('/login', {
      'email': 'ann@example.com',
      'password': 'not it at all',
    });
    expect(wrong.statusCode, 401);
    final right = await ann.post('/login', {
      'email': 'ann@example.com',
      'password': 'correct horse battery',
      'next': '/m/$id-tiny-triangle',
    });
    expect(right.statusCode, 303);
    expect(right.headers['location'], path);

    // A reset from another browser signs this one out.
    final elsewhere = _Browser(handler);
    await elsewhere.get('/forgot');
    final asked = await elsewhere.post('/forgot', {'email': 'ann@example.com'});
    expect(asked.statusCode, 200);
    // An unknown address gets the same page, and no letter.
    final lettersBefore = mailer.sent.length;
    final unknown = await elsewhere.post('/forgot', {
      'email': 'nobody@example.com',
    });
    expect(unknown.statusCode, 200);
    expect(mailer.sent.length, lettersBefore);

    final resetToken = _tokenIn(
      mailer.sent.lastWhere((l) => l.subject.contains('Reset')),
    );
    // A refused password leaves the link working for the next attempt.
    final refused = await elsewhere.post('/reset', {
      'token': resetToken,
      'password': 'password123',
      'passwordConfirm': 'password123',
    });
    expect(refused.statusCode, 422);
    final reset = await elsewhere.post('/reset', {
      'token': resetToken,
      'password': 'a brand new password',
      'passwordConfirm': 'a brand new password',
    });
    expect(reset.statusCode, 303);
    expect(mailer.sent.last.subject, contains('was changed'));
    expect(
      (await ann.get('/me')).statusCode,
      303,
      reason: 'every session ends with a reset',
    );
    expect(
      (await elsewhere.post('/reset', {
        'token': resetToken,
        'password': 'yet another password',
      })).statusCode,
      400,
      reason: 'a reset link works once',
    );

    final signedIn = await ann.post('/login', {
      'email': 'ann@example.com',
      'password': 'a brand new password',
    });
    expect(signedIn.statusCode, 303);

    // Deleting the model deletes its file, since nobody else points at it.
    expect((await ann.post('/m/$id/delete', {})).statusCode, 303);
    expect(blobs.length, 0);
    expect((await ann.get(path)).statusCode, 404);
  });

  test('guessing a password is slowed down per account', () async {
    final guesser = _Browser(handler);
    await guesser.get('/login');
    final codes = [
      for (var i = 0; i < 11; i++)
        (await guesser.post('/login', {
          'email': 'bob@example.com',
          'password': 'guess number $i',
        })).statusCode,
    ];
    expect(codes.take(10), everyElement(401));
    expect(codes.last, 429);
  });

  test('replaceSource three times in a row keeps all three blobs referenced '
      'and lists three revisions, newest first', () async {
    final owner = await services.users.create(
      email: 'revisions-owner@example.com',
      handle: 'revisions-owner',
      displayName: 'Revisions Owner',
      passwordHash: 'x',
    );
    final original = await blobs.put(
      Uint8List.fromList(utf8.encode('original triangle')),
    );
    final model = await services.models.create(
      ownerId: owner!.id,
      title: 'Revision Chair',
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: original,
        bytes: 20,
        contentType: 'model/obj',
        filename: 'chair.obj',
      ),
    );

    final saved = <String>[];
    for (var i = 1; i <= 3; i++) {
      final hash = await blobs.put(
        Uint8List.fromList(utf8.encode('revision $i content')),
      );
      saved.add(hash);
      final updated = await services.models.replaceSource(
        modelId: model.id,
        newSource: StoredFile(
          blobSha256: hash,
          bytes: 30 + i,
          contentType: 'model/obj',
          filename: 'chair-v$i.obj',
        ),
        triangleCount: 10 * i,
        sourceFormat: 'obj',
        actorUserId: owner.id,
      );
      // Each save moves the model's own denormalized columns with it.
      expect(updated.sizeBytes, 30 + i);
      expect(updated.triangleCount, 10 * i);
    }

    final revisions = await services.models.revisionsOf(model.id);
    expect(revisions.map((r) => r.blobSha256).toList(), [
      saved[2],
      saved[1],
      saved[0],
    ], reason: 'newest first');
    for (final revision in revisions) {
      expect(revision.modelId, model.id);
      expect(revision.createdBy, owner.id);
    }

    // The integrity-critical part: two of these blobs are no longer
    // `model_files`' current source — only the third save is — but each is
    // still the only thing its own revision row points at, so none of them
    // may look unreferenced while the model still exists.
    for (final hash in saved) {
      expect(await services.models.isReferenced(hash), isTrue);
    }

    final deletedHashes = await services.models.delete(model.id);
    expect(deletedHashes.toSet(), saved.toSet());

    // Once the model itself is gone, so is every revision that pointed at
    // these blobs — nothing is left referencing them.
    for (final hash in saved) {
      expect(await services.models.isReferenced(hash), isFalse);
      await blobs.delete(hash);
    }
    for (final hash in saved) {
      expect(await blobs.open(hash), isNull);
    }
  });

  test(
    "a revision id from one model cannot fetch another model's file",
    () async {
      final ownerA = await services.users.create(
        email: 'model-a-owner@example.com',
        handle: 'model-a-owner',
        displayName: 'Model A Owner',
        passwordHash: 'x',
      );
      final ownerB = await services.users.create(
        email: 'model-b-owner@example.com',
        handle: 'model-b-owner',
        displayName: 'Model B Owner',
        passwordHash: 'x',
      );

      final modelA = await services.models.create(
        ownerId: ownerA!.id,
        title: 'Model A',
        sourceFormat: 'obj',
        triangleCount: 1,
        source: StoredFile(
          blobSha256: await blobs.put(
            Uint8List.fromList(utf8.encode('model a original')),
          ),
          bytes: 10,
          contentType: 'model/obj',
          filename: 'a.obj',
        ),
      );
      await services.models.replaceSource(
        modelId: modelA.id,
        newSource: StoredFile(
          blobSha256: await blobs.put(
            Uint8List.fromList(utf8.encode('model a revision')),
          ),
          bytes: 11,
          contentType: 'model/obj',
          filename: 'a-v2.obj',
        ),
        triangleCount: 2,
        sourceFormat: 'obj',
        actorUserId: ownerA.id,
      );
      final revisionA = (await services.models.revisionsOf(modelA.id)).single;

      final modelB = await services.models.create(
        ownerId: ownerB!.id,
        title: 'Model B',
        sourceFormat: 'obj',
        triangleCount: 1,
        source: StoredFile(
          blobSha256: await blobs.put(
            Uint8List.fromList(utf8.encode('model b original')),
          ),
          bytes: 10,
          contentType: 'model/obj',
          filename: 'b.obj',
        ),
      );

      expect(
        await services.models.revisionFile(modelA.id, revisionA.id),
        isNotNull,
      );
      expect(
        await services.models.revisionFile(modelB.id, revisionA.id),
        isNull,
      );
      expect(await services.models.revisionFile(modelA.id, 999999999), isNull);
    },
  );

  test('preview pictures: save, fetch, ownership, staleness, validation and '
      'the rate limit', () async {
    final owner = _Browser(handler);
    await owner.get('/register');
    await owner.post('/register', {
      'email': 'preview-owner@example.com',
      'displayName': 'Preview Owner',
      'password': 'a perfectly cromulent password',
      'passwordConfirm': 'a perfectly cromulent password',
    });
    final ownerVerify = _tokenIn(
      mailer.sent.lastWhere(
        (l) =>
            l.to == 'preview-owner@example.com' &&
            l.subject.contains('Confirm'),
      ),
    );
    await owner.get('/verify?token=$ownerVerify');

    final uploaded = await owner.upload('preview_subject.obj', _triangle);
    expect(uploaded.statusCode, 201);
    final uploadedBody =
        jsonDecode(await uploaded.readAsString()) as Map<String, Object?>;
    final modelId = uploadedBody['id']! as int;
    final sourceSha = sha256.convert(_triangle).toString();

    // No picture yet: a 404, not an empty 200 — the two are not the same
    // thing to a client deciding whether to draw a placeholder.
    expect((await owner.get('/files/$modelId/preview')).statusCode, 404);

    // Captured against a source the model no longer has: refused, not
    // silently attached to whatever the model is now.
    final stale = await owner.uploadPreview(
      modelId,
      _png(64, 64),
      sourceSha256: 'f' * 64,
    );
    expect(stale.statusCode, 409);

    // Not a PNG at all: refused, and nothing is stored.
    final notPng = await owner.uploadPreview(
      modelId,
      _triangle,
      sourceSha256: sourceSha,
    );
    expect(notPng.statusCode, 422);

    // A PNG whose IHDR claims a picture far past any preview's reason to be
    // that size: refused too, without ever inflating any pixel data.
    final tooBig = await owner.uploadPreview(
      modelId,
      _png(64, 4096),
      sourceSha256: sourceSha,
    );
    expect(tooBig.statusCode, 422);

    // None of the rejected attempts left a preview behind.
    expect((await owner.get('/files/$modelId/preview')).statusCode, 404);

    // A real, correctly-sized PNG against the current source succeeds.
    final saved = await owner.uploadPreview(
      modelId,
      _png(320, 200),
      sourceSha256: sourceSha,
    );
    expect(saved.statusCode, 200);

    final fetched = await owner.get('/files/$modelId/preview');
    expect(fetched.statusCode, 200);
    expect(fetched.headers['content-type'], 'image/png');
    expect(
      await fetched.read().expand((chunk) => chunk).toList(),
      _png(320, 200),
    );
    final modelWithPreview = (await services.models.byId(modelId))!;
    expect(modelWithPreview.hasPreview, isTrue);

    // The model's own page shows the picture, for whoever has not clicked
    // "Open in 3D" yet.
    final pageWithPreview = await owner.get(modelWithPreview.path);
    expect(pageWithPreview.statusCode, 200);
    expect(
      await pageWithPreview.readAsString(),
      contains('/files/$modelId/preview'),
    );

    // Somebody else gets 404 setting a preview on this model — never 403,
    // which would confirm the model exists to someone who cannot edit it.
    final stranger = _Browser(handler);
    await stranger.get('/register');
    await stranger.post('/register', {
      'email': 'preview-stranger@example.com',
      'displayName': 'Stranger',
      'password': 'a different cromulent password',
      'passwordConfirm': 'a different cromulent password',
    });
    final strangersAttempt = await stranger.uploadPreview(
      modelId,
      _png(64, 64),
      sourceSha256: sourceSha,
    );
    expect(strangersAttempt.statusCode, 404);
    // And it changed nothing about the picture the owner already saved.
    expect(
      await (await owner.get(
        '/files/$modelId/preview',
      )).read().expand((chunk) => chunk).toList(),
      _png(320, 200),
    );

    // Saving again replaces the picture, and the one it replaced is freed —
    // the same garbage collection `/m/<id>/delete` already does for its own
    // files, now aware that a revision can also be the last thing holding a
    // blob alive.
    final firstPreviewHash = sha256.convert(_png(320, 200)).toString();
    final replaced = await owner.uploadPreview(
      modelId,
      _png(128, 128),
      sourceSha256: sourceSha,
    );
    expect(replaced.statusCode, 200);
    expect(await blobs.open(firstPreviewHash), isNull);
    expect(
      await (await owner.get(
        '/files/$modelId/preview',
      )).read().expand((chunk) => chunk).toList(),
      _png(128, 128),
    );

    // Enough preview saves from one account trip the rate limit — every
    // attempt counts against it, the same as a sign-in guess, whether or
    // not that particular attempt is one this test also expects to fail.
    final codes = <int>[
      for (var i = 0; i < 32; i++)
        (await owner.uploadPreview(
          modelId,
          _png(128, 128),
          sourceSha256: sourceSha,
        )).statusCode,
    ];
    expect(codes, contains(429));
  });

  test('saving a source over the HTTP handler: revisions, ownership, and '
      'validation before storage', () async {
    final owner = _Browser(handler);
    await owner.get('/register');
    await owner.post('/register', {
      'email': 'source-save-owner@example.com',
      'displayName': 'Source Save Owner',
      'password': 'a perfectly cromulent password',
      'passwordConfirm': 'a perfectly cromulent password',
    });
    final ownerVerify = _tokenIn(
      mailer.sent.lastWhere(
        (l) =>
            l.to == 'source-save-owner@example.com' &&
            l.subject.contains('Confirm'),
      ),
    );
    await owner.get('/verify?token=$ownerVerify');

    final uploaded = await owner.upload('editable.obj', _triangle);
    expect(uploaded.statusCode, 201);
    final modelId =
        (jsonDecode(await uploaded.readAsString())
                as Map<String, Object?>)['id']!
            as int;

    // Nothing to save yet: only the original upload exists, and that is not
    // a revision until something replaces it.
    final emptyRevisions = await owner.get('/api/v1/models/$modelId/revisions');
    expect(emptyRevisions.statusCode, 200);
    expect(jsonDecode(await emptyRevisions.readAsString()), isEmpty);

    // Saving a well-formed edit replaces the current file and records the
    // one it replaced as a revision.
    final firstSave = await owner.saveSource(modelId, 'editable.obj', _quad);
    expect(firstSave.statusCode, 200);
    final firstSaveBody =
        jsonDecode(await firstSave.readAsString()) as Map<String, Object?>;
    expect(firstSaveBody['id'], modelId);
    expect(firstSaveBody['triangleCount'], 2);
    expect(firstSaveBody['sizeBytes'], _quad.length);

    final afterFirstSave = await owner.get('/files/$modelId/source');
    expect(
      await afterFirstSave.read().expand((chunk) => chunk).toList(),
      _quad,
      reason: "the model's current file is the one just saved",
    );

    // `replaceSource` records the revision as what was just saved — the file
    // that becomes current, not the one it displaced — so with only one save
    // done, that lone revision and the current file are the same bytes; the
    // original, pre-edit upload from `create()` was never itself recorded as
    // a revision and has nothing pointing at it once this save moves
    // `model_files` on.
    final oneRevision = await owner.get('/api/v1/models/$modelId/revisions');
    final oneRevisionList =
        jsonDecode(await oneRevision.readAsString()) as List<Object?>;
    expect(oneRevisionList, hasLength(1));
    final firstRevision = oneRevisionList.single! as Map<String, Object?>;
    expect(firstRevision['bytes'], _quad.length);
    expect(
      firstRevision.keys,
      containsAll(['id', 'bytes', 'createdAt', 'createdBy']),
    );

    // The revision route serves that revision's own bytes, not whatever the
    // model happens to be current as by the time somebody asks.
    final firstRevisionId = firstRevision['id']! as int;
    final firstDownload = await owner.get(
      '/files/$modelId/revisions/$firstRevisionId',
    );
    expect(firstDownload.statusCode, 200);
    expect(await firstDownload.read().expand((chunk) => chunk).toList(), _quad);

    // Another account may not save to this model — 404, never 403, so a
    // private model's id is not confirmed to somebody who cannot edit it.
    // Signed in as an already-registered account from an earlier test rather
    // than registering a new one: every test here shares one IP's
    // `registerPerIp` budget, and this file already spends most of it.
    final stranger = _Browser(handler);
    await stranger.get('/login');
    final strangerSignIn = await stranger.post('/login', {
      'email': 'preview-owner@example.com',
      'password': 'a perfectly cromulent password',
    });
    expect(strangerSignIn.statusCode, 303);

    final strangersSave = await stranger.saveSource(
      modelId,
      'stolen.obj',
      _fan,
    );
    expect(strangersSave.statusCode, 404);
    // Reading the revision list, and the revision itself, are just as
    // invisible to somebody who cannot see this private model at all.
    expect(
      (await stranger.get('/api/v1/models/$modelId/revisions')).statusCode,
      404,
    );
    expect(
      (await stranger.get(
        '/files/$modelId/revisions/$firstRevisionId',
      )).statusCode,
      404,
    );
    // And none of it changed what the owner has.
    expect(
      await (await owner.get(
        '/files/$modelId/source',
      )).read().expand((chunk) => chunk).toList(),
      _quad,
    );

    // A second well-formed save adds a second revision, newest first — and
    // this is where the first one genuinely becomes "old": no longer what
    // `model_files` points at, but still its own row in `model_revisions`.
    final secondSave = await owner.saveSource(modelId, 'editable.obj', _fan);
    expect(secondSave.statusCode, 200);
    final secondSaveBody =
        jsonDecode(await secondSave.readAsString()) as Map<String, Object?>;
    expect(secondSaveBody['triangleCount'], 3);
    expect(secondSaveBody['sizeBytes'], _fan.length);

    final twoRevisions = await owner.get('/api/v1/models/$modelId/revisions');
    final twoRevisionsList =
        jsonDecode(await twoRevisions.readAsString()) as List<Object?>;
    expect(twoRevisionsList, hasLength(2));
    final newestRevision = twoRevisionsList.first! as Map<String, Object?>;
    final olderRevision = twoRevisionsList.last! as Map<String, Object?>;
    expect(newestRevision['bytes'], _fan.length, reason: 'newest first');
    expect(
      olderRevision['bytes'],
      _quad.length,
      reason: 'the first edit is now the oldest revision, no longer current',
    );
    expect(olderRevision['id'], firstRevisionId);

    // The owner's own page lists both, newest marked current, each linking
    // to its own download route — fetched straight from the repository when
    // the page renders, not through this same JSON endpoint.
    final modelForPage = (await services.models.byId(modelId))!;
    final pageWithRevisions = await owner.get(modelForPage.path);
    expect(pageWithRevisions.statusCode, 200);
    final pageWithRevisionsBody = await pageWithRevisions.readAsString();
    expect(pageWithRevisionsBody, contains('Revisions'));
    expect(pageWithRevisionsBody, contains('current'));
    expect(
      pageWithRevisionsBody,
      contains('/files/$modelId/revisions/${newestRevision['id']}'),
    );
    expect(
      pageWithRevisionsBody,
      contains('/files/$modelId/revisions/${olderRevision['id']}'),
    );

    // The point of keeping it: that older, no-longer-current revision is
    // still downloadable byte-for-byte, even though the model has moved on.
    final oldDownload = await owner.get(
      '/files/$modelId/revisions/$firstRevisionId',
    );
    expect(oldDownload.statusCode, 200);
    expect(await oldDownload.read().expand((chunk) => chunk).toList(), _quad);

    // A body that does not decode as a model is refused before anything is
    // stored, exactly as a bad initial upload already is — not a weaker
    // check because it is "just an update".
    final malformed = await owner.saveSource(
      modelId,
      'garbage.obj',
      Uint8List.fromList(utf8.encode('not a model at all')),
    );
    expect(malformed.statusCode, 422);

    // Crucially: the rejected save created no revision row at all. The count
    // is exactly what it was before the malformed attempt, proving the
    // validate-before-store ordering — decode first, write only on success.
    final revisionsAfterRejection = await owner.get(
      '/api/v1/models/$modelId/revisions',
    );
    expect(
      jsonDecode(await revisionsAfterRejection.readAsString()),
      hasLength(2),
    );
    // And the current file is still what the last accepted save left it as.
    expect(
      await (await owner.get(
        '/files/$modelId/source',
      )).read().expand((chunk) => chunk).toList(),
      _fan,
    );

    // A revision id that is real, but belongs to a different model, 404s
    // against that other model's download route rather than serving it. The
    // second model is created straight through the repository, the same way
    // the revision tests above it do, rather than another HTTP upload — it
    // only needs to exist and belong to somebody else.
    final strangerId = (await services.users.byEmail(
      'preview-owner@example.com',
    ))!.id;
    final strangersModel = await services.models.create(
      ownerId: strangerId,
      title: 'Strangers Own',
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: await blobs.put(
          Uint8List.fromList(utf8.encode('strangers own model')),
        ),
        bytes: 20,
        contentType: 'model/obj',
        filename: 'strangers_own.obj',
      ),
    );
    final strangersModelId = strangersModel.id;
    expect(
      (await stranger.get(
        '/files/$strangersModelId/revisions/$firstRevisionId',
      )).statusCode,
      404,
    );
  });

  test('a model moves into a project, out again, and between two projects the '
      'same account owns — never into one somebody else owns', () async {
    final owner = await services.users.create(
      email: 'project-owner@example.com',
      handle: 'project-owner',
      displayName: 'Project Owner',
      passwordHash: 'x',
    );
    final stranger = await services.users.create(
      email: 'project-stranger@example.com',
      handle: 'project-stranger',
      displayName: 'Project Stranger',
      passwordHash: 'x',
    );

    final workshop = await services.projects.create(
      ownerId: owner!.id,
      title: 'Workshop',
    );
    final gallery = await services.projects.create(
      ownerId: owner.id,
      title: 'Gallery',
    );
    final strangersProject = await services.projects.create(
      ownerId: stranger!.id,
      title: "Stranger's Project",
    );

    // `create` accepts a project up front — a model does not have to be
    // moved into one after the fact just to start out in one.
    final model = await services.models.create(
      ownerId: owner.id,
      title: 'Project Chair',
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: await blobs.put(
          Uint8List.fromList(utf8.encode('project chair')),
        ),
        bytes: 10,
        contentType: 'model/obj',
        filename: 'chair.obj',
      ),
      projectId: workshop.id,
    );
    expect((await services.models.byId(model.id))!.projectId, workshop.id);

    // Moving out to no project at all always succeeds — there is no
    // target owner to check.
    expect(await services.models.moveToProject(model.id, null), isTrue);
    expect((await services.models.byId(model.id))!.projectId, isNull);

    // Moving between two projects the same account owns succeeds.
    expect(await services.models.moveToProject(model.id, gallery.id), isTrue);
    expect((await services.models.byId(model.id))!.projectId, gallery.id);

    // A project owned by somebody else refuses the move and changes
    // nothing — the model stays exactly where it was.
    expect(
      await services.models.moveToProject(model.id, strangersProject.id),
      isFalse,
    );
    expect((await services.models.byId(model.id))!.projectId, gallery.id);
  });

  test(
    'deleting a project leaves its former models personal, not deleted',
    () async {
      final owner = await services.users.create(
        email: 'delete-project-owner@example.com',
        handle: 'delete-project-owner',
        displayName: 'Delete Project Owner',
        passwordHash: 'x',
      );
      final project = await services.projects.create(
        ownerId: owner!.id,
        title: 'Doomed Project',
      );
      final model = await services.models.create(
        ownerId: owner.id,
        title: 'Orphan Chair',
        sourceFormat: 'obj',
        triangleCount: 1,
        source: StoredFile(
          blobSha256: await blobs.put(
            Uint8List.fromList(utf8.encode('orphan chair')),
          ),
          bytes: 10,
          contentType: 'model/obj',
          filename: 'orphan.obj',
        ),
        projectId: project.id,
      );

      await services.projects.delete(project.id);

      // The FK's own `on delete set null` did this — no application code
      // walked the project's models to detach them.
      final afterDelete = await services.models.byId(model.id);
      expect(afterDelete, isNotNull);
      expect(afterDelete!.projectId, isNull);
      expect(await services.projects.byId(project.id), isNull);
    },
  );

  test('publishing records a category, and the database itself refuses one '
      'outside the known list', () async {
    final owner = await services.users.create(
      email: 'publish-owner@example.com',
      handle: 'publish-owner',
      displayName: 'Publish Owner',
      passwordHash: 'x',
    );
    final model = await services.models.create(
      ownerId: owner!.id,
      title: 'Publishable Chair',
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: await blobs.put(
          Uint8List.fromList(utf8.encode('publishable chair')),
        ),
        bytes: 10,
        contentType: 'model/obj',
        filename: 'publishable.obj',
      ),
    );

    await services.models.publish(
      model.id,
      Licence.cc0,
      category: Category.props,
    );
    final published = (await services.models.byId(model.id))!;
    expect(published.visibility, Visibility.public);
    expect(published.licence, Licence.cc0);
    expect(published.category, Category.props);

    // The Dart type system already keeps `publish` from being called
    // without a category, or with one that is not one of `Category`'s own
    // — the check constraint below is a backstop behind that, in case
    // anything other than `publish` ever writes this column directly. It
    // is never what a normal call through `publish` should be able to
    // trigger, which is why `publish` itself is never tested against it.
    await expectLater(
      db.run(
        (s) => s.execute(
          Sql.named("update models set category = 'bogus' where id = @id"),
          parameters: {'id': model.id},
        ),
      ),
      throwsA(anything),
    );
  });

  test(
    'published models can be filtered by category and searched by title',
    () async {
      final owner = await services.users.create(
        email: 'showcase-owner@example.com',
        handle: 'showcase-owner',
        displayName: 'Showcase Owner',
        passwordHash: 'x',
      );

      final glider = await services.models.create(
        ownerId: owner!.id,
        title: 'Zephyr Glider',
        sourceFormat: 'obj',
        triangleCount: 1,
        source: StoredFile(
          blobSha256: await blobs.put(
            Uint8List.fromList(utf8.encode('zephyr glider')),
          ),
          bytes: 10,
          contentType: 'model/obj',
          filename: 'glider.obj',
        ),
      );
      await services.models.publish(
        glider.id,
        Licence.cc0,
        category: Category.vehicles,
      );

      final statue = await services.models.create(
        ownerId: owner.id,
        title: 'Marble Sentinel',
        sourceFormat: 'obj',
        triangleCount: 1,
        source: StoredFile(
          blobSha256: await blobs.put(
            Uint8List.fromList(utf8.encode('marble sentinel')),
          ),
          bytes: 10,
          contentType: 'model/obj',
          filename: 'statue.obj',
        ),
      );
      await services.models.publish(
        statue.id,
        Licence.ccBy,
        category: Category.characters,
      );

      // Filtered by category: each shows up only under its own.
      final vehicles = await services.models.published(
        category: Category.vehicles,
      );
      expect(vehicles.map((m) => m.id), contains(glider.id));
      expect(vehicles.map((m) => m.id), isNot(contains(statue.id)));

      final characters = await services.models.published(
        category: Category.characters,
      );
      expect(characters.map((m) => m.id), contains(statue.id));
      expect(characters.map((m) => m.id), isNot(contains(glider.id)));

      // Searched by a word distinctive to one title: it does not return the
      // other, whichever way round the search is tried.
      final searchedZephyr = await services.models.published(search: 'zephyr');
      expect(searchedZephyr.map((m) => m.id), contains(glider.id));
      expect(searchedZephyr.map((m) => m.id), isNot(contains(statue.id)));

      final searchedSentinel = await services.models.published(
        search: 'sentinel',
      );
      expect(searchedSentinel.map((m) => m.id), contains(statue.id));
      expect(searchedSentinel.map((m) => m.id), isNot(contains(glider.id)));
    },
  );

  test('projects through the HTTP handler: create, list, rename, delete, '
      'moving a model in, out and never into somebody else\'s', () async {
    // Signed in as two already-registered, already-verified accounts from
    // earlier tests in this file rather than registering fresh ones — every
    // test here shares one IP's `registerPerIp` budget, and this file has
    // already spent all five of them by this point.
    final owner = _Browser(handler);
    await owner.get('/login');
    expect(
      (await owner.post('/login', {
        'email': 'source-save-owner@example.com',
        'password': 'a perfectly cromulent password',
      })).statusCode,
      303,
    );

    // Signed out, the page redirects to sign in, the same as `/me` already
    // does — and a signed-in visitor sees the nav link.
    expect(
      (await _Browser(handler).get('/projects')).headers['location'],
      '/login?next=/projects',
    );
    expect(
      await (await owner.get('/me')).readAsString(),
      contains('My projects'),
    );

    await owner.get('/projects');
    final created = await owner.post('/projects', {'title': 'Diorama Set'});
    expect(created.statusCode, 303);
    var projectPath = created.headers['location']!.split('?').first;
    expect(projectPath, matches(RegExp(r'^/p/\d+-diorama-set$')));
    final projectId = int.parse(
      RegExp(r'^/p/(\d+)-').firstMatch(projectPath)!.group(1)!,
    );

    // It shows up in the owner's own list.
    expect(
      await (await owner.get('/projects')).readAsString(),
      contains('Diorama Set'),
    );

    // A model, created standing alone, moves into the new project.
    final uploaded = await owner.upload('diorama_piece.obj', _triangle);
    final modelId =
        (jsonDecode(await uploaded.readAsString())
                as Map<String, Object?>)['id']!
            as int;
    final movedIn = await owner.post('/m/$modelId/move', {
      'project': '$projectId',
    });
    expect(movedIn.statusCode, 303);

    final withModel = await owner.get(projectPath);
    expect(withModel.statusCode, 200);
    expect(await withModel.readAsString(), contains('diorama piece'));

    // Moving between two of the owner's own projects updates both pages'
    // own listings — gone from the first, present in the second.
    final secondCreated = await owner.post('/projects', {
      'title': 'Second Shelf',
    });
    final secondPath = secondCreated.headers['location']!.split('?').first;
    final secondId = int.parse(
      RegExp(r'^/p/(\d+)-').firstMatch(secondPath)!.group(1)!,
    );
    final movedBetween = await owner.post('/m/$modelId/move', {
      'project': '$secondId',
    });
    expect(movedBetween.statusCode, 303);
    expect(
      await (await owner.get(projectPath)).readAsString(),
      isNot(contains('diorama piece')),
    );
    expect(
      await (await owner.get(secondPath)).readAsString(),
      contains('diorama piece'),
    );

    // Moved back to the first project for the rest of this test.
    await owner.post('/m/$modelId/move', {'project': '$projectId'});

    // Renaming changes the slug, and the old address still finds it.
    final renamed = await owner.post('/p/$projectId/describe', {
      'title': 'Renamed Diorama Set',
      'description': 'A set of pieces.',
    });
    expect(renamed.statusCode, 303);
    projectPath = renamed.headers['location']!.split('?').first;
    expect(projectPath, '/p/$projectId-renamed-diorama-set');
    final renamedPage = await owner.get(projectPath);
    expect(renamedPage.statusCode, 200);
    expect(await renamedPage.readAsString(), contains('Renamed Diorama Set'));

    // Moving back out to personal empties the project's own list.
    final movedOut = await owner.post('/m/$modelId/move', {'project': ''});
    expect(movedOut.statusCode, 303);
    final emptied = await owner.get(projectPath);
    expect(await emptied.readAsString(), isNot(contains('diorama piece')));

    // Another account gets 404 for every one of these — never 403, which
    // would confirm the project exists to somebody who cannot see it. Signed
    // in as yet another already-registered account, for the same reason the
    // owner above is too.
    final stranger = _Browser(handler);
    await stranger.get('/login');
    expect(
      (await stranger.post('/login', {
        'email': 'preview-owner@example.com',
        'password': 'a perfectly cromulent password',
      })).statusCode,
      303,
    );
    expect((await stranger.get(projectPath)).statusCode, 404);
    expect(
      (await stranger.post('/p/$projectId/describe', {
        'title': 'Stolen',
      })).statusCode,
      404,
    );
    expect((await stranger.post('/p/$projectId/delete', {})).statusCode, 404);
    // Nor may the stranger move their own model into this project — the
    // model is created straight through the repository, the same way the
    // earlier repository-level test does, since it only needs to exist and
    // belong to the stranger.
    final strangerId = (await services.users.byEmail(
      'preview-owner@example.com',
    ))!.id;
    final strangersModel = await services.models.create(
      ownerId: strangerId,
      title: "Stranger's Piece",
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: await blobs.put(
          Uint8List.fromList(utf8.encode('strangers piece')),
        ),
        bytes: 10,
        contentType: 'model/obj',
        filename: 'strangers_piece.obj',
      ),
    );
    final refused = await stranger.post('/m/${strangersModel.id}/move', {
      'project': '$projectId',
    });
    expect(refused.statusCode, 404);
    expect((await services.models.byId(strangersModel.id))!.projectId, isNull);
    // And nothing about the owner's project changed underneath them.
    expect((await owner.get(projectPath)).statusCode, 200);

    // The owner deletes the project; its model, already moved out, is
    // unaffected, and the project itself is gone.
    final deleted = await owner.post('/p/$projectId/delete', {});
    expect(deleted.statusCode, 303);
    expect(deleted.headers['location'], '/projects?said=project-deleted');
    expect((await owner.get(projectPath)).statusCode, 404);
    expect(
      await (await owner.get('/projects')).readAsString(),
      isNot(contains('Renamed Diorama Set')),
    );
  });

  test('publishing and unpublishing a model through the HTTP handler: a bad '
      'licence or category is refused and changes nothing, a good one shows '
      'up in the showcase, unpublishing takes it back out without deleting '
      'it, and nobody but the owner may do either', () async {
    // Signed in as an already-registered account, the same as the
    // projects test above and for the same reason — this file has already
    // spent every `registerPerIp` attempt it gets.
    final owner = _Browser(handler);
    await owner.get('/login');
    expect(
      (await owner.post('/login', {
        'email': 'source-save-owner@example.com',
        'password': 'a perfectly cromulent password',
      })).statusCode,
      303,
    );

    final uploaded = await owner.upload('publish_me.obj', _triangle);
    final body =
        jsonDecode(await uploaded.readAsString()) as Map<String, Object?>;
    final modelId = body['id']! as int;
    final modelPath = body['path']! as String;

    // A form without the CSRF token is refused before ownership is even
    // looked at, the same as every other POST on this service.
    expect(
      (await _Browser(handler).post('/m/$modelId/publish', {
        'licence': 'CC0-1.0',
        'category': 'props',
      })).statusCode,
      403,
    );

    // A licence outside the known list is refused, the form is re-shown,
    // and nothing about the model changes.
    final badLicence = await owner.post('/m/$modelId/publish', {
      'licence': 'not-a-real-licence',
      'category': 'props',
    });
    expect(badLicence.statusCode, 422);
    expect(
      await badLicence.readAsString(),
      contains('Choose one of the licences.'),
    );
    expect(
      (await services.models.byId(modelId))!.visibility,
      Visibility.private,
    );

    // So is a category outside the known list.
    final badCategory = await owner.post('/m/$modelId/publish', {
      'licence': 'CC0-1.0',
      'category': 'not-a-real-category',
    });
    expect(badCategory.statusCode, 422);
    expect(
      await badCategory.readAsString(),
      contains('Choose one of the categories.'),
    );
    expect(
      (await services.models.byId(modelId))!.visibility,
      Visibility.private,
    );

    // A good pair publishes it: visible to nobody yet, since a stranger
    // still gets a 404 until this request actually lands.
    final published = await owner.post('/m/$modelId/publish', {
      'licence': 'CC0-1.0',
      'category': 'props',
    });
    expect(published.statusCode, 303);
    expect(published.headers['location'], '$modelPath?said=published');

    final afterPublish = (await services.models.byId(modelId))!;
    expect(afterPublish.visibility, Visibility.public);
    expect(afterPublish.licence, Licence.cc0);
    expect(afterPublish.category, Category.props);
    expect(afterPublish.publishedAt, isNotNull);
    expect(
      (await services.models.published()).map((m) => m.id),
      contains(modelId),
    );

    // Now visible to a signed-out visitor, its licence and category shown.
    final publicView = await _Browser(handler).get(modelPath);
    expect(publicView.statusCode, 200);
    final publicHtml = await publicView.readAsString();
    expect(publicHtml, contains('CC0-1.0'));
    expect(publicHtml, contains('Props'));

    // Another account may not publish or unpublish it — 404, never 403,
    // the same as every other ownership refusal on this service — and
    // nothing about the model changes underneath them.
    final stranger = _Browser(handler);
    await stranger.get('/login');
    expect(
      (await stranger.post('/login', {
        'email': 'preview-stranger@example.com',
        'password': 'a different cromulent password',
      })).statusCode,
      303,
    );
    expect(
      (await stranger.post('/m/$modelId/publish', {
        'licence': 'CC-BY-4.0',
        'category': 'vehicles',
      })).statusCode,
      404,
    );
    expect((await stranger.post('/m/$modelId/unpublish', {})).statusCode, 404);
    final untouched = (await services.models.byId(modelId))!;
    expect(untouched.visibility, Visibility.public);
    expect(untouched.licence, Licence.cc0);
    expect(untouched.category, Category.props);

    // The owner takes it back down. The model itself is untouched — still
    // there, still reachable at its own address for the owner — only its
    // visibility moves, and it drops out of the showcase.
    final unpublished = await owner.post('/m/$modelId/unpublish', {});
    expect(unpublished.statusCode, 303);
    expect(unpublished.headers['location'], '$modelPath?said=unpublished');

    final afterUnpublish = (await services.models.byId(modelId))!;
    expect(afterUnpublish.visibility, Visibility.private);
    expect(afterUnpublish.licence, Licence.cc0);
    expect(afterUnpublish.category, Category.props);
    expect(afterUnpublish.publishedAt, afterPublish.publishedAt);
    expect(
      (await services.models.published()).map((m) => m.id),
      isNot(contains(modelId)),
    );
    expect((await owner.get(modelPath)).statusCode, 200);
    expect((await _Browser(handler).get(modelPath)).statusCode, 404);

    // Enough publish/unpublish attempts from one account trip the rate
    // limit — every attempt counts against it, whether or not that
    // particular attempt is one this test also expects to fail.
    final codes = <int>[
      for (var i = 0; i < 21; i++)
        (await owner.post('/m/$modelId/publish', {
          'licence': 'CC0-1.0',
          'category': 'props',
        })).statusCode,
    ];
    expect(codes, contains(429));
  });

  test('the public showcase at /explore renders published models, and a '
      'visitor can narrow them by category and by search', () async {
    // Direct repository writes, the same as the "filtered by category and
    // searched by title" test above and for the same reason — this file
    // has already spent every `registerPerIp` attempt it gets, and this
    // test is about what the page does with `published()`'s results, not
    // about registration.
    final owner = await services.users.create(
      email: 'explore-owner@example.com',
      handle: 'explore-owner',
      displayName: 'Explore Owner',
      passwordHash: 'x',
    );

    final glider = await services.models.create(
      ownerId: owner!.id,
      title: 'Aurora Glider',
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: await blobs.put(
          Uint8List.fromList(utf8.encode('aurora glider')),
        ),
        bytes: 10,
        contentType: 'model/obj',
        filename: 'aurora.obj',
      ),
    );
    await services.models.publish(
      glider.id,
      Licence.cc0,
      category: Category.vehicles,
    );

    final statue = await services.models.create(
      ownerId: owner.id,
      title: 'Bronze Sentinel',
      sourceFormat: 'obj',
      triangleCount: 1,
      source: StoredFile(
        blobSha256: await blobs.put(
          Uint8List.fromList(utf8.encode('bronze sentinel')),
        ),
        bytes: 10,
        contentType: 'model/obj',
        filename: 'bronze.obj',
      ),
    );
    await services.models.publish(
      statue.id,
      Licence.ccBy,
      category: Category.characters,
    );

    final visitor = _Browser(handler);

    // Unfiltered: both published models show up, no sign-in needed.
    final all = await visitor.get('/explore');
    expect(all.statusCode, 200);
    final allHtml = await all.readAsString();
    expect(allHtml, contains('Aurora Glider'));
    expect(allHtml, contains('Bronze Sentinel'));

    // Narrowed to a category: only the model filed under it shows up —
    // the filtering reaches the page, not only `published()` itself.
    final vehiclesHtml = await (await visitor.get(
      '/explore?category=vehicles',
    )).readAsString();
    expect(vehiclesHtml, contains('Aurora Glider'));
    expect(vehiclesHtml, isNot(contains('Bronze Sentinel')));

    // Searched by a word distinctive to one title.
    final searchedHtml = await (await visitor.get(
      '/explore?q=aurora',
    )).readAsString();
    expect(searchedHtml, contains('Aurora Glider'));
    expect(searchedHtml, isNot(contains('Bronze Sentinel')));

    // A search and a category that together match nothing shows the empty
    // state plainly, rather than a blank grid.
    final emptyHtml = await (await visitor.get(
      '/explore?q=aurora&category=characters',
    )).readAsString();
    expect(emptyHtml, isNot(contains('Aurora Glider')));
    expect(emptyHtml, isNot(contains('Bronze Sentinel')));
    expect(emptyHtml, contains('No published models'));
  });
}
