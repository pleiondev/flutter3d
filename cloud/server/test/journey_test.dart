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
import 'package:flutter3d_models/src/http/app.dart';
import 'package:flutter3d_models/src/mail/mailer.dart';
import 'package:flutter3d_models/src/services.dart';
import 'package:flutter3d_models/src/storage/blob_store.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

const _base = 'http://localhost:8793';
final _triangle = Uint8List.fromList(
  utf8.encode('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'),
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
    expect((await services.models.byId(modelId))!.hasPreview, isTrue);

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
}
