/// N10: a level filed by its bytes behind a short code, what a moderator and a
/// report do to it, and `RunService` from `flutter3d_sim` against the real
/// routes — the two halves of one protocol, checked together rather than each
/// against a description of the other.
///
///     dart test test/share_routes_test.dart
///
/// Mutation: file by the bytes as sent rather than as re-written and the same
/// bundle with its keys reordered gets a second code; publish on arrival in
/// review mode and an unmoderated upload is open to anyone; rename `code`,
/// `bundle` or `message` on either side and the client answers a refusal for
/// a call that worked.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_models/src/config.dart';
import 'package:flutter3d_models/src/http/share_routes.dart';
import 'package:flutter3d_models/src/shares/share_service.dart';
import 'package:flutter3d_models/src/shares/share_store.dart';
import 'package:flutter3d_models/src/shares/short_code.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const String _token = 'a-moderator-token-long-enough';

Level _level({String name = 'strip'}) => Level(
  name: name,
  materials: <String, LevelMaterial>{'stone': LevelMaterial()},
  brushes: <Brush>[
    Brush(
      center: Vector3(0.0, -0.5, 0.0),
      size: Vector3(20.0, 1.0, 4.0),
      material: 'stone',
    ),
  ],
  entities: const <EntityDef>[],
);

/// A run of [steps] steps through [level]. Nothing here plays it: a share is
/// checked against its level's hash, not re-simulated, so a tape and a trace
/// of made-up states are all it needs.
Demo _run(Level level, {int steps = 120}) {
  final trace = DigestTrace(every: 10);
  for (var step = 1; step <= steps; step++) {
    trace.observe(step, <String, Object?>{'x': step / 20.0});
  }
  return Demo(
    level: 'levels/${level.name}.json',
    levelHash: level.digestHex,
    start: Snapshot(<String, Object?>{'x': 0.0}),
    tape: InputTape(
      seed: 1,
      frames: <InputFrame>[
        for (var step = 0; step < steps; step++) const InputFrame(stickX: 1.0),
      ],
    ),
    buildStamp: 'test',
    checkpoints: trace,
  );
}

ShareBundle _bundle({Demo? run, String? title, String game = 'walk'}) =>
    ShareBundle(game: game, level: _level().toJson(), run: run, title: title);

/// The routes over a store in memory, mounted the way `app.dart` mounts them,
/// with a route after them under the same prefix so falling through is
/// tested too.
final class _Server {
  _Server({
    ShareModeration moderation = ShareModeration.review,
    String? token = _token,
    int reportsToHide = 3,
    int maxBodyBytes = 1024 * 1024,
  }) : service = ShareService(
         store: MemoryShareStore(),
         moderation: moderation,
         moderatorToken: token,
         reportsToHide: reportsToHide,
         maxBodyBytes: maxBodyBytes,
         now: () => DateTime.utc(2026, 10, 1, 12),
       );

  final ShareService service;

  MemoryShareStore get store => service.store as MemoryShareStore;

  late final Handler handler =
      (Router(notFoundHandler: (Request request) => Response.notFound('none'))
            ..mount('/api/', shareRoutes(service).call)
            ..get(
              '/api/v1/models',
              (Request request) => Response.ok('the models route'),
            ))
          .call;

  Future<(int, Map<String, Object?>)> call(
    String method,
    String path, {
    Object? body,
    bool moderator = false,
    String? authorization,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('https://models.example/api$path'),
        body: body == null ? null : (body is String ? body : jsonEncode(body)),
        headers: <String, String>{
          if (moderator) 'authorization': 'Bearer $_token',
          'authorization': ?authorization,
        },
      ),
    );
    final text = await response.readAsString();
    return (response.statusCode, jsonDecode(text) as Map<String, Object?>);
  }

  Future<String> share(ShareBundle bundle) async {
    final (_, filed) = await call('POST', '/v1/shares', body: bundle.toJson());
    return filed['code']! as String;
  }

  Future<int> decide(String code, Map<String, Object?> decision) async =>
      (await call(
        'POST',
        '/v1/moderation/shares/$code',
        body: decision,
        moderator: true,
      )).$1;

  /// [RunService] talking to these routes without a socket, from the base a
  /// game would be handed.
  RunService client() => RunService(
    base: Uri.parse('https://models.example/api/'),
    transport: (RunRequest request) async {
      final response = await handler(
        Request(request.method, request.uri, body: request.body),
      );
      return RunResponse(response.statusCode, await response.readAsString());
    },
  );
}

void main() {
  group('in review mode', () {
    test('a share waits for a moderator before anyone can open it', () async {
      final server = _Server();
      final (status, filed) = await server.call(
        'POST',
        '/v1/shares',
        body: _bundle(run: _run(_level()), title: 'east').toJson(),
      );
      expect(status, 201, reason: '${filed['message']}');
      expect(filed['status'], 'pending');
      final code = filed['code']! as String;
      expect(code, hasLength(shortestCode));

      final (early, waiting) = await server.call('GET', '/v1/shares/$code');
      expect(early, 202);
      expect(waiting['bundle'], isNull);

      expect(await server.decide(code, {'decision': 'publish'}), 200);
      final (opened, json) = await server.call('GET', '/v1/shares/$code');
      expect(opened, 200);
      final bundle = ShareBundle.fromJson(
        json['bundle']! as Map<String, Object?>,
      );
      expect(bundle.title, 'east');
      expect(bundle.run!.steps, 120);
    });

    test(
      'the same bundle shared twice is filed once, under one code',
      () async {
        final server = _Server();
        final json = _bundle().toJson();
        final reordered = <String, Object?>{
          for (final key in json.keys.toList().reversed) key: json[key],
        };

        final first = await server.call('POST', '/v1/shares', body: json);
        final second = await server.call('POST', '/v1/shares', body: reordered);

        expect(first.$1, 201);
        expect(second.$1, 200);
        expect(second.$2['code'], first.$2['code']);
        expect(server.store.records, hasLength(1));
        // What is kept is what the address names, byte for byte.
        final code = first.$2['code']! as String;
        final kept = server.store.bundles[code]!;
        expect(kept, jsonEncode(json));
        expect(
          first.$2['address'],
          sha256.convert(utf8.encode(kept)).toString(),
        );
        expect(code, codeOf(first.$2['address']! as String, shortestCode));
      },
    );

    test('a code is read the way people type it', () async {
      final server = _Server();
      final code = await server.share(_bundle());
      final typed = '${code.substring(0, 3).toLowerCase()}-${code.substring(3)}'
          .replaceAll('0', 'o')
          .replaceAll('1', 'l');

      expect((await server.call('GET', '/v1/shares/$typed')).$1, 202);
      expect((await server.call('GET', '/v1/shares/not-a-code')).$1, 404);
    });

    test('a bundle whose run is from another level is refused', () async {
      final server = _Server();
      final json = _bundle().toJson()
        ..['run'] = _run(_level(name: 'elsewhere')).toJson();

      final (status, answer) = await server.call(
        'POST',
        '/v1/shares',
        body: json,
      );

      expect(status, 422);
      expect(answer['message'], contains('another version of the level'));
      expect(server.store.records, isEmpty);
    });

    test(
      'a game name or a title this server will not show is refused',
      () async {
        final server = _Server();

        final (game, gameAnswer) = await server.call(
          'POST',
          '/v1/shares',
          body: _bundle(game: 'Walk Two').toJson(),
        );
        final (title, titleAnswer) = await server.call(
          'POST',
          '/v1/shares',
          body: _bundle(title: 'east\nwest').toJson(),
        );

        expect(game, 422);
        expect(gameAnswer['message'], contains('"Walk Two"'));
        expect(title, 422);
        expect(titleAnswer['message'], contains('one line'));
        expect(server.store.records, isEmpty);
      },
    );

    test('a removal says why, and the code answers with it', () async {
      final server = _Server();
      final code = await server.share(_bundle());

      expect(await server.decide(code, {'decision': 'remove'}), 422);
      expect(
        await server.decide(code, {'decision': 'remove', 'reason': 'spam'}),
        200,
      );

      final (status, answer) = await server.call('GET', '/v1/shares/$code');
      expect(status, 410);
      expect(answer['message'], contains('spam'));
      // Shared again, the level is the same removed row, not a fresh one.
      final (again, refiled) = await server.call(
        'POST',
        '/v1/shares',
        body: _bundle().toJson(),
      );
      expect(again, 200);
      expect(refiled['status'], 'removed');
    });

    test('moderation refuses anyone without the token', () async {
      final server = _Server();
      final code = await server.share(_bundle());

      expect((await server.call('GET', '/v1/moderation/queue')).$1, 401);
      final (wrong, answer) = await server.call(
        'GET',
        '/v1/moderation/queue',
        authorization: 'Bearer $_token-',
      );
      expect(wrong, 401);
      expect(answer['message'], contains('MODELS_SHARES_MODERATOR_TOKEN'));
      expect(
        (await server.call(
          'POST',
          '/v1/moderation/shares/$code',
          body: {'decision': 'publish'},
          authorization: 'Bearer ${_token.substring(1)}',
        )).$1,
        401,
      );
      expect(server.store.records[code]!.status, ShareStatus.pending);

      final (queued, queue) = await server.call(
        'GET',
        '/v1/moderation/queue',
        moderator: true,
      );
      expect(queued, 200);
      expect(
        (queue['items']! as List<Object?>).single,
        containsPair('code', code),
      );
      final (looked, record) = await server.call(
        'GET',
        '/v1/moderation/shares/$code',
        moderator: true,
      );
      expect(looked, 200);
      expect(record['bundle'], isA<Map<String, Object?>>());
    });

    test(
      'with no moderator token, nothing is taken and moderation is off',
      () async {
        // Mutation: a review server with nobody to review would keep every
        // upload pending forever, and an empty token would let an empty
        // `Bearer ` header through.
        final server = _Server(token: null);

        final (status, answer) = await server.call(
          'POST',
          '/v1/shares',
          body: _bundle().toJson(),
        );
        expect(status, 503);
        expect(answer['message'], contains('MODELS_SHARES_MODERATOR_TOKEN'));
        expect(server.store.records, isEmpty);
        expect(
          (await server.call(
            'GET',
            '/v1/moderation/queue',
            authorization: 'Bearer ',
          )).$1,
          503,
        );
      },
    );

    test('what these routes do not answer falls through to the rest of '
        '/api/', () async {
      final server = _Server();
      final response = await server.handler(
        Request('GET', Uri.parse('https://models.example/api/v1/models')),
      );
      expect(await response.readAsString(), 'the models route');
    });
  });

  group('in open mode', () {
    test('reports send a published level back to review, and publishing it '
        'again answers them', () async {
      final server = _Server(
        moderation: ShareModeration.open,
        reportsToHide: 2,
      );
      final (_, filed) = await server.call(
        'POST',
        '/v1/shares',
        body: _bundle().toJson(),
      );
      final code = filed['code']! as String;
      expect(filed['status'], 'published');

      final (empty, _) = await server.call(
        'POST',
        '/v1/shares/$code/reports',
        body: {'reason': ' '},
      );
      expect(empty, 422);
      for (final reason in <String>['offensive title', 'offensive title']) {
        final (reported, answer) = await server.call(
          'POST',
          '/v1/shares/$code/reports',
          body: {'reason': reason},
        );
        expect(reported, 202);
        expect(answer['message'], contains(code));
      }

      expect((await server.call('GET', '/v1/shares/$code')).$1, 202);
      final (_, queue) = await server.call(
        'GET',
        '/v1/moderation/queue',
        moderator: true,
      );
      final item = (queue['items']! as List<Object?>).single! as Map;
      expect(item['reports'], hasLength(2));

      expect(await server.decide(code, {'decision': 'publish'}), 200);
      expect((await server.call('GET', '/v1/shares/$code')).$1, 200);
      expect(server.store.records[code]!.reports, isEmpty);
    });

    test('a body over the limit is refused before it is read whole', () async {
      final server = _Server(
        moderation: ShareModeration.open,
        maxBodyBytes: 2048,
      );

      final (status, answer) = await server.call(
        'POST',
        '/v1/shares',
        body: ' ' * 4096,
      );

      expect(status, 413);
      expect(answer['message'], contains('2048'));
      final (report, _) = await server.call(
        'POST',
        '/v1/shares/0000000/reports',
        body: ' ' * 5000,
      );
      expect(report, 413);
    });
  });

  group('RunService against these routes', () {
    test('a bundle shared, published and opened is the bundle sent', () async {
      final server = _Server();
      final client = server.client();
      final sent = _bundle(run: _run(_level()), title: 'east');

      final shared = await client.share(sent);
      final code = (shared as ServiceDone<SharedBundle>).value.code;
      expect(shared.value.status, ShareStatus.pending);
      expect(shared.value.address, hasLength(64));

      final early = await client.open(code);
      expect(
        early,
        isA<ServiceRefused<ShareBundle>>().having(
          (r) => r.reason,
          'reason',
          contains('moderator'),
        ),
      );

      await server.decide(code, {'decision': 'publish'});
      final opened = await client.open(code.toLowerCase());

      final bundle = (opened as ServiceDone<ShareBundle>).value;
      expect(bundle.levelHash, sent.levelHash);
      expect(
        bundle.run!.checkpoints.hexDigests,
        sent.run!.checkpoints.hexDigests,
      );
    });

    test('a report reaches the moderation queue, and a refusal is the '
        "server's sentence", () async {
      final server = _Server();
      final client = server.client();
      final code =
          ((await client.share(_bundle())) as ServiceDone<SharedBundle>)
              .value
              .code;

      final answer = await client.report(code, 'not a level');
      expect(answer, isA<ServiceDone<String>>());
      expect(server.store.records[code]!.reports.single.reason, 'not a level');

      final unknown = await client.open('ZZZZZZZ');
      expect(
        unknown,
        isA<ServiceRefused<ShareBundle>>().having(
          (r) => r.reason,
          'reason',
          contains('no level is shared under "ZZZZZZZ"'),
        ),
      );
    });
  });

  group('configuration', () {
    const base = <String, String>{
      'MODELS_BASE_URL': 'https://models.example',
      'MODELS_DATABASE_URL': 'postgres://nobody@127.0.0.1/none',
      'MODELS_BLOB_DIR': '/tmp/none',
      'MODELS_SECRET': 'a-secret',
    };

    test('sharing is reviewed and unmoderated unless a deploy says so', () {
      final config = Config.fromEnvironment(base);
      expect(config.shareModeration, ShareModeration.review);
      expect(config.shareModeratorToken, isNull);
      expect(config.shareReportsToHide, 3);

      final open = Config.fromEnvironment(<String, String>{
        ...base,
        'MODELS_SHARES_MODERATION': 'open',
        'MODELS_SHARES_MODERATOR_TOKEN': _token,
        'MODELS_SHARES_REPORTS_TO_HIDE': '5',
      });
      expect(open.shareModeration, ShareModeration.open);
      expect(open.shareModeratorToken, _token);
      expect(open.shareReportsToHide, 5);
    });

    test('a setting present and wrong stops the start, named', () {
      expect(
        () => Config.fromEnvironment(<String, String>{
          ...base,
          'MODELS_SHARES_MODERATION': 'lax',
          'MODELS_SHARES_MODERATOR_TOKEN': 'short',
          'MODELS_SHARES_REPORTS_TO_HIDE': '0',
        }),
        throwsA(
          isA<ConfigError>().having((e) => e.missing, 'missing', hasLength(3)),
        ),
      );
    });
  });
}
