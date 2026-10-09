/// `/convert`'s routes and `MODELS_EDITOR`'s gate, with no database: who is
/// asking is a function the test answers, the converter answers at once, and
/// "Save to my models" records what it was handed.
///
///     dart test test/convert_routes_test.dart
///
/// Mutation: drop the `canUpload` check and an unconfirmed account converts;
/// drop the CSRF check on either POST and a forged form saves a model into
/// somebody's cabinet; look a result up by id alone and another account
/// downloads it; let the source-save route reach the model while the editor
/// is off and it answers anything but 410.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_models/src/config.dart';
import 'package:flutter3d_models/src/convert/conversion_store.dart';
import 'package:flutter3d_models/src/convert/converter.dart';
import 'package:flutter3d_models/src/convert/exporter.dart';
import 'package:flutter3d_models/src/domain/user.dart';
import 'package:flutter3d_models/src/http/convert_routes.dart';
import 'package:flutter3d_models/src/http/cookies.dart';
import 'package:flutter3d_models/src/http/editor_gate.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _origin = 'https://models.pleion.dev';
const _policy = CookiePolicy(secure: true, origin: _origin);
const _csrf = 'token-123';

User _user(int id, {required bool confirmed}) => User(
  id: id,
  email: 'person$id@example.com',
  handle: 'person$id',
  displayName: 'Person $id',
  createdAt: DateTime.utc(2026),
  emailVerifiedAt: confirmed ? DateTime.utc(2026) : null,
);

final _owner = _user(1, confirmed: true);
final _unconfirmed = _user(2, confirmed: false);
final _stranger = _user(3, confirmed: true);

/// The model bytes the fake converter hands back.
final _model = Uint8List.fromList([0x46, 0x33, 0x44, 0x01]);

class _Harness {
  _Harness({int uploadLimitBytes = 1024 * 1024, ConversionOutcome? outcome})
    : root = Directory.systemTemp.createTempSync('convert-routes-') {
    store = ConversionStore(root: root, sweepEvery: null);
    routes = ConversionRoutes(
      whoIs: (Request request) async =>
          switch (request.headers['x-test-user']) {
            '1' => _owner,
            '2' => _unconfirmed,
            '3' => _stranger,
            _ => null,
          },
      policy: _policy,
      store: store,
      uploadLimitBytes: uploadLimitBytes,
      saveModel: (User user, String fileName, Uint8List bytes) async {
        saved.add((user.id, fileName, bytes));
        return const SavedModel(7, '/m/7-chair');
      },
      export:
          (
            Uint8List source, {
            required String sourceName,
            required ExportFormat format,
            required String baseName,
          }) async {
            exported.add((sourceName, format, baseName));
            if (format == ExportFormat.usdz) {
              return const ExportRefused('the writer has no room for this');
            }
            return Exported(
              ExportedFile(
                bytes: Uint8List.fromList(utf8.encode('${format.column}!')),
                contentType: format == ExportFormat.gltf
                    ? 'application/zip'
                    : format.contentType,
                zipped: format == ExportFormat.gltf,
              ),
            );
          },
      convert:
          (
            Uint8List bytes, {
            required String fileName,
            required ConversionTarget target,
          }) async {
            converted++;
            return outcome ??
                ConversionDone(
                  files: [
                    ConvertedFile('chair.f3d', _model),
                    ConvertedFile(
                      'materials/oak.fmat',
                      Uint8List.fromList(utf8.encode('{}')),
                    ),
                  ],
                  reports: const [
                    InputReport(
                      input: 'chair.obj',
                      format: 'obj',
                      outcome: 'converted',
                      error: null,
                      written: ['chair.f3d', 'materials/oak.fmat'],
                      mapped: ['model -> chair.f3d'],
                      dropped: ['a light: not read from OBJ'],
                      warnings: [],
                    ),
                  ],
                  notOffered: const [],
                );
          },
    );
    handler = routes.handler;
  }

  final Directory root;
  late final ConversionStore store;
  late final ConversionRoutes routes;
  late final Handler handler;
  final List<(int, String, Uint8List)> saved = [];
  final List<(String, ExportFormat, String)> exported = [];
  int converted = 0;

  void dispose() => root.deleteSync(recursive: true);

  Future<Response> send(
    String method,
    String path, {
    String? user,
    bool csrf = true,
    Map<String, String> headers = const {},
    Object? body,
  }) async => await handler(
    Request(
      method,
      Uri.parse('$_origin$path'),
      headers: {
        'cookie': '__Host-csrf=$_csrf',
        'origin': _origin,
        'x-test-user': ?user,
        if (csrf && method == 'POST' && body is! String) 'x-csrf': _csrf,
        ...headers,
      },
      body: body,
    ),
  );

  Future<Response> upload({
    String? user = '1',
    bool csrf = true,
    String target = 'model',
    List<int> bytes = const [1, 2, 3],
  }) => send(
    'POST',
    '/api/v1/conversions',
    user: user,
    csrf: csrf,
    headers: {'x-filename': 'chair.obj', 'x-target': target},
    body: bytes,
  );

  /// Converts as the owner and returns the result's path.
  Future<String> convertOnce() async {
    final response = await upload();
    expect(response.statusCode, 201);
    final body = jsonDecode(await response.readAsString()) as Map;
    return body['path'] as String;
  }

  Future<Response> save(
    String resultPath, {
    String? user = '1',
    String file = 'chair.f3d',
    String csrfField = _csrf,
  }) => send(
    'POST',
    '$resultPath/save',
    user: user,
    headers: {'content-type': 'application/x-www-form-urlencoded'},
    body:
        'csrf=${Uri.encodeQueryComponent(csrfField)}'
        '&file=${Uri.encodeQueryComponent(file)}',
  );
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('converting', () {
    test('is refused signed out', () async {
      final response = await h.upload(user: null);
      expect(response.statusCode, 401);
      expect(h.converted, 0);
    });

    test('is refused to an account whose address is not confirmed', () async {
      final response = await h.upload(user: '2');
      expect(response.statusCode, 403);
      expect(await response.readAsString(), contains('Confirm'));
      expect(h.converted, 0);
    });

    test('is refused without the page\'s token, or from elsewhere', () async {
      expect((await h.upload(csrf: false)).statusCode, 403);
      final forged = await h.send(
        'POST',
        '/api/v1/conversions',
        user: '1',
        headers: {
          'x-csrf': _csrf,
          'origin': 'https://evil.example',
          'x-target': 'model',
        },
        body: const [1, 2, 3],
      );
      expect(forged.statusCode, 403);
      expect(h.converted, 0);
    });

    test('needs a target it knows', () async {
      final response = await h.upload(target: 'everything-please');
      expect(response.statusCode, 422);
      expect(h.converted, 0);
    });

    test('keeps the upload limit', () async {
      final small = _Harness(uploadLimitBytes: 8);
      addTearDown(small.dispose);
      final response = await small.upload(bytes: List.filled(9, 0));
      expect(response.statusCode, 413);
      expect(small.converted, 0);
    });

    test('has no rate limit', () async {
      for (var i = 0; i < 25; i++) {
        expect((await h.upload()).statusCode, 201);
      }
      expect(h.converted, 25);
    });

    test('answers a refusal with the converter\'s sentence', () async {
      final refusing = _Harness(
        outcome: const ConversionRefused(
          'Converting took longer than 2 '
          'minutes, so it was stopped and nothing was kept.',
        ),
      );
      addTearDown(refusing.dispose);
      final response = await refusing.upload();
      expect(response.statusCode, 422);
      expect(await response.readAsString(), contains('took longer'));
    });
  });

  group('a result', () {
    test('shows its files and report to the account that made it', () async {
      final path = await h.convertOnce();
      final page = await h.send('GET', path, user: '1');
      expect(page.statusCode, 200);
      final html = await page.readAsString();
      expect(html, contains('chair.f3d'));
      expect(html, contains('Save to my models'));
      expect(html, contains('a light: not read from OBJ'));
    });

    test('is nobody else\'s to see or download', () async {
      final path = await h.convertOnce();
      expect((await h.send('GET', path, user: '3')).statusCode, 404);
      expect(
        (await h.send(
          'GET',
          '$path/file?path=chair.f3d',
          user: '3',
        )).statusCode,
        404,
      );
      expect((await h.send('GET', '$path/all.zip', user: '3')).statusCode, 404);
      // Signed out: sent to sign in, and shown nothing.
      expect((await h.send('GET', path)).statusCode, 303);
      expect(
        (await h.send('GET', '$path/file?path=chair.f3d')).statusCode,
        404,
      );
    });

    test('downloads what it holds, and nothing it does not', () async {
      final path = await h.convertOnce();
      final file = await h.send('GET', '$path/file?path=chair.f3d', user: '1');
      expect(file.statusCode, 200);
      expect(file.headers['content-disposition'], contains('chair.f3d'));
      expect(await file.read().expand((c) => c).toList(), _model);

      final archive = await h.send('GET', '$path/all.zip', user: '1');
      expect(archive.statusCode, 200);

      for (final wrong in ['../../etc/passwd', '0', 'chair.F3D', '']) {
        final response = await h.send(
          'GET',
          '$path/file?path=${Uri.encodeQueryComponent(wrong)}',
          user: '1',
        );
        expect(response.statusCode, 404, reason: wrong);
      }
    });

    test('is gone after its hour', () async {
      final now = DateTime.utc(2026, 10, 8, 12);
      final clock = [now];
      final store = ConversionStore(
        root: h.root,
        sweepEvery: null,
        clock: () => clock.first,
      );
      final held = await store.keep(
        ownerId: 1,
        sourceName: 'chair.obj',
        target: ConversionTarget.model,
        done: ConversionDone(
          files: [ConvertedFile('chair.f3d', _model)],
          reports: const [],
          notOffered: const [],
        ),
      );
      expect(store.find(held.id, 1), isNotNull);
      clock[0] = now.add(const Duration(hours: 1));
      expect(store.find(held.id, 1), isNull);
      await store.sweep();
      expect(Directory('${h.root.path}/${held.id}').existsSync(), isFalse);
    });
  });

  group('Save to my models', () {
    test('keeps the model through the upload path and opens it', () async {
      final path = await h.convertOnce();
      final response = await h.save(path);
      expect(response.statusCode, 303);
      expect(response.headers['location'], '/m/7-chair?said=converted');
      expect(h.saved.single.$1, 1);
      expect(h.saved.single.$2, 'chair.f3d');
      expect(h.saved.single.$3, _model);
    });

    test('is refused with a forged form', () async {
      final path = await h.convertOnce();
      final response = await h.save(path, csrfField: 'not-the-token');
      expect(response.statusCode, 403);
      expect(h.saved, isEmpty);
    });

    test('is refused to an unconfirmed account and to anybody else', () async {
      final path = await h.convertOnce();
      expect((await h.save(path, user: '2')).statusCode, 403);
      expect((await h.save(path, user: '3')).statusCode, 404);
      expect((await h.save(path, user: null)).statusCode, 303);
      expect(h.saved, isEmpty);
    });

    test('takes only a model: a material is a download', () async {
      final path = await h.convertOnce();
      final response = await h.save(path, file: 'materials/oak.fmat');
      expect(response.statusCode, 404);
      expect(h.saved, isEmpty);
    });

    test('says the converted .f3d is what it keeps when there is no '
        'original', () async {
      final path = await h.convertOnce();
      final html = await (await h.send('GET', path, user: '1')).readAsString();
      expect(html, contains('keeps chair.f3d, the converted model'));
    });

    test('keeps the uploaded .glb byte for byte, not the .f3d', () async {
      final glb = Uint8List.fromList([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]);
      final withOriginal = _Harness(
        outcome: ConversionDone(
          files: [ConvertedFile('chair.f3d', _model)],
          reports: const [],
          notOffered: const [],
          original: KeepableOriginal(fileName: 'chair.glb', bytes: glb),
        ),
      );
      addTearDown(withOriginal.dispose);
      final path = await withOriginal.convertOnce();
      final html = await (await withOriginal.send(
        'GET',
        path,
        user: '1',
      )).readAsString();
      expect(html, contains('keeps your chair.glb as you sent it'));

      final response = await withOriginal.save(path);
      expect(response.statusCode, 303);
      expect(withOriginal.saved.single.$2, 'chair.glb');
      expect(withOriginal.saved.single.$3, glb);
    });

    test(
      'keeps a GLB written from a .gltf with its .bin, and says so',
      () async {
        final glb = Uint8List.fromList([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 1]);
        final fromZip = _Harness(
          outcome: ConversionDone(
            files: [ConvertedFile('scene/chair.f3d', _model)],
            reports: const [],
            notOffered: const [],
            original: KeepableOriginal(
              fileName: 'chair.glb',
              bytes: glb,
              writtenFrom: 'scene/chair.gltf',
            ),
          ),
        );
        addTearDown(fromZip.dispose);
        final path = await fromZip.convertOnce();
        final html = await (await fromZip.send(
          'GET',
          path,
          user: '1',
        )).readAsString();
        expect(html, contains('a glTF binary written from scene/chair.gltf'));
        final response = await fromZip.save(path, file: 'scene/chair.f3d');
        expect(response.statusCode, 303);
        expect(fromZip.saved.single.$2, 'chair.glb');
        expect(fromZip.saved.single.$3, glb);
      },
    );

    test('keeps each .f3d when there are several, original or not', () async {
      final several = _Harness(
        outcome: ConversionDone(
          files: [
            ConvertedFile('a.f3d', _model),
            ConvertedFile('b.f3d', _model),
          ],
          reports: const [],
          notOffered: const [],
          original: KeepableOriginal(
            fileName: 'a.glb',
            bytes: Uint8List.fromList([1]),
          ),
        ),
      );
      addTearDown(several.dispose);
      final path = await several.convertOnce();
      expect((await several.save(path, file: 'b.f3d')).statusCode, 303);
      expect(several.saved.single.$2, 'b.f3d');
    });
  });

  group('Download as… on a result', () {
    test('writes the model in each format, typed and named', () async {
      final path = await h.convertOnce();
      final html = await (await h.send('GET', path, user: '1')).readAsString();
      expect(html, contains('Download as…'));
      expect(html, contains('$path/as/stl?path=chair.f3d'));
      expect(html, contains('For Blender (.glb)'));

      for (final (format, type, name) in [
        ('glb', 'model/gltf-binary', 'chair.glb'),
        ('gltf', 'application/zip', 'chair-gltf.zip'),
        ('stl', 'model/stl', 'chair.stl'),
        ('f3d', 'application/octet-stream', 'chair.f3d'),
      ]) {
        final response = await h.send(
          'GET',
          '$path/as/$format?path=chair.f3d',
          user: '1',
        );
        expect(response.statusCode, 200, reason: format);
        expect(response.headers['content-type'], type, reason: format);
        expect(
          response.headers['content-disposition'],
          contains('filename="$name"'),
          reason: format,
        );
      }
      // The .f3d is the held file itself; nothing was written for it.
      expect(h.exported.map((e) => e.$2), [
        ExportFormat.glb,
        ExportFormat.gltf,
        ExportFormat.stl,
      ]);
    });

    test('writes once: the second request is the kept file', () async {
      final path = await h.convertOnce();
      for (var i = 0; i < 3; i++) {
        final response = await h.send(
          'GET',
          '$path/as/glb?path=chair.f3d',
          user: '1',
        );
        expect(response.statusCode, 200);
        expect(await response.readAsString(), 'glb!');
      }
      expect(h.exported, hasLength(1));
    });

    test('is nobody else\'s, and only a model\'s', () async {
      final path = await h.convertOnce();
      expect(
        (await h.send(
          'GET',
          '$path/as/glb?path=chair.f3d',
          user: '3',
        )).statusCode,
        404,
      );
      expect(
        (await h.send('GET', '$path/as/glb?path=chair.f3d')).statusCode,
        404,
      );
      expect(
        (await h.send(
          'GET',
          '$path/as/glb?path=materials/oak.fmat',
          user: '1',
        )).statusCode,
        404,
      );
      expect(
        (await h.send(
          'GET',
          '$path/as/blend?path=chair.f3d',
          user: '1',
        )).statusCode,
        404,
      );
      expect(h.exported, isEmpty);
    });

    test('answers a writer\'s refusal with 422 and its reason', () async {
      final path = await h.convertOnce();
      final response = await h.send(
        'GET',
        '$path/as/usdz?path=chair.f3d',
        user: '1',
      );
      expect(response.statusCode, 422);
      expect(
        await response.readAsString(),
        contains('the writer has no room for this'),
      );
    });
  });

  group('MODELS_EDITOR', () {
    const minimum = <String, String>{
      'MODELS_BASE_URL': 'https://models.example',
      'MODELS_DATABASE_URL': 'postgres://nobody@127.0.0.1/none',
      'MODELS_BLOB_DIR': '/tmp/none',
      'MODELS_SECRET': 'a-secret',
    };

    test('is off unless it says on', () {
      expect(Config.fromEnvironment(minimum).editor, isFalse);
      expect(
        Config.fromEnvironment({...minimum, 'MODELS_EDITOR': 'off'}).editor,
        isFalse,
      );
      expect(
        Config.fromEnvironment({...minimum, 'MODELS_EDITOR': 'on'}).editor,
        isTrue,
      );
    });

    test('stops the start when it is neither', () {
      expect(
        () => Config.fromEnvironment({...minimum, 'MODELS_EDITOR': 'yes'}),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.missing,
            'missing',
            contains('MODELS_EDITOR (on or off)'),
          ),
        ),
      );
    });

    test('off, a source save is answered 410 with the reason', () async {
      final off = Config.fromEnvironment(minimum);
      final refused = sourceSaveRefusal(off);
      expect(refused, isNotNull);
      expect(refused!.statusCode, 410);
      final body = jsonDecode(await refused.readAsString()) as Map;
      expect(body['error'], contains('switched off'));
    });

    test('on, it lets the save through to the usual checks', () {
      final on = Config.fromEnvironment({...minimum, 'MODELS_EDITOR': 'on'});
      expect(sourceSaveRefusal(on), isNull);
    });
  });
}
