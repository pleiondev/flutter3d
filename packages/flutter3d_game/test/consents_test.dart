/// What a game asks before anything of the player's leaves the device, and
/// that nothing does until the player says it may.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  Future<String?> read(String name) async => documents[name];
  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

/// A store that only counts what is asked of it.
final class _Counted extends CloudSaveStore {
  final List<String> calls = <String>[];
  @override
  String get name => 'the test cloud';
  @override
  Future<CloudFetch> fetch(String slot) async {
    calls.add('fetch');
    return const CloudEmpty();
  }

  @override
  Future<CloudPut> put(
    String slot,
    String document, {
    String? replacing,
  }) async {
    calls.add('put');
    return const CloudStored(version: '1');
  }
}

Demo _demo() => Demo(
  level: 'assets/levels/one.json',
  levelHash: 'abc',
  start: const Snapshot(<String, Object?>{}),
  tape: InputTape(
    seed: 1,
    frames: <InputFrame>[for (var i = 0; i < 10; i++) const InputFrame()],
  ),
  buildStamp: 'test',
  checkpoints: DigestTrace(every: 1),
);

void main() {
  ({Consents consents, _Counted store, List<String> posted}) fresh() {
    final storage = _Storage();
    final store = _Counted();
    final sync = SaveSync(
      saves: SaveFile(appName: 'test', storage: storage),
      store: store,
    );
    return (
      consents: Consents(
        storage: storage,
        policy: '2026-10',
        sync: sync,
        now: () => DateTime.utc(2026, 10, 6),
      ),
      store: store,
      posted: <String>[],
    );
  }

  test(
    'on a fresh install both are no, and nothing leaves the device',
    () async {
      final it = fresh();
      expect(it.consents.hasCloudConsent, isFalse);
      expect(it.consents.sendsRuns, isFalse);
      expect(it.consents.telemetry.wasAsked, isFalse);

      // The cloud: not a request until the player says yes.
      final report = await it.consents.sync!.sync();
      expect(report.outcome, SyncOutcome.notConsented);
      expect(it.store.calls, isEmpty);

      // Telemetry: the uploader reads the answer as it stands at each send.
      final posted = <String>[];
      final uploader = TelemetryUploader(
        game: 'test',
        policy: it.consents.policy,
        consent: () => it.consents.telemetry,
        sink: HttpTelemetrySink(
          endpoint: Uri.parse('https://example.test/api/telemetry/runs'),
          post: (Uri url, String json) async {
            posted.add(json);
            return (status: 201, body: '{"run": 1, "eraseKey": "k"}');
          },
        ),
      );
      expect((await uploader.send(_demo())).did, isFalse);
      expect(posted, isEmpty);

      // Said yes to, each goes.
      // Mutation: an answer written under another policy than the one asked.
      expect(await it.consents.answerTelemetry(granted: true), isTrue);
      expect(it.consents.sendsRuns, isTrue);
      expect((await uploader.send(_demo())).did, isTrue);
      expect(posted, hasLength(1));
      expect(await it.consents.answerCloud(granted: true), isTrue);
      expect(
        (await it.consents.sync!.sync()).outcome,
        isNot(SyncOutcome.notConsented),
      );
      expect(it.store.calls, isNotEmpty);

      // And taken back, stops at the next send.
      await it.consents.answerTelemetry(granted: false);
      expect((await uploader.send(_demo())).did, isFalse);
      expect(posted, hasLength(1));
    },
  );

  test('the telemetry answer is enveloped, and its version 1 fixture and '
      'the shape before the envelope read', () async {
    // Minted on 2026-10-09 when the answer went into the envelope.
    final fixture = File('test/fixtures/v1/telemetry.json').readAsStringSync();
    final storage = _Storage()..documents[Consents.telemetryName] = fixture;
    final read = Consents(storage: storage, policy: '2026-10');
    await read.ready;
    expect(read.sendsRuns, isTrue);

    final bare = Map<String, Object?>.of(
      jsonDecode(fixture) as Map<String, Object?>,
    )..removeWhere((String key, _) => FormatSpec.envelopeKeys.contains(key));
    storage.documents[Consents.telemetryName] = jsonEncode(bare);
    final old = Consents(storage: storage, policy: '2026-10');
    await old.ready;
    expect(old.sendsRuns, isTrue);

    // A newer document is not asked, never a grant. Mutation: read past the
    // version and this one says yes.
    storage.documents[Consents.telemetryName] = jsonEncode(<String, Object?>{
      ...jsonDecode(fixture) as Map<String, Object?>,
      'version': Consents.telemetryVersion + 1,
    });
    final newer = Consents(storage: storage, policy: '2026-10');
    await newer.ready;
    expect(newer.telemetry.wasAsked, isFalse);

    await newer.answerTelemetry(granted: false);
    final written =
        jsonDecode(storage.documents[Consents.telemetryName]!)
            as Map<String, Object?>;
    expect(written['format'], 'f3d.telemetryConsent');
    expect(written['answer'], 'declined');
  });

  test('a new wording asks again', () async {
    final it = fresh();
    await it.consents.answerTelemetry(granted: true);
    final reworded = Consents(storage: it.consents.storage, policy: '2027-01');
    expect(reworded.telemetry.isGranted, isTrue);
    expect(reworded.sendsRuns, isFalse);
  });

  test(
    'a build with no save server says so, and its switch does nothing',
    () async {
      final consents = Consents(storage: _Storage(), policy: '2026-10');
      expect(consents.hasCloudConsent, isFalse);
      expect(await consents.answerCloud(granted: true), isFalse);
      expect(consents.hasCloudConsent, isFalse);
    },
  );

  test('a run is posted as JSON over a real client', () async {
    late http.Request seen;
    final post = httpJsonPost(
      MockClient((http.Request request) async {
        seen = request;
        return http.Response('{"says": "kept"}', 201);
      }),
    );
    final answer = await post(Uri.parse('https://example.test/x'), '{"a":1}');
    expect(answer, (status: 201, body: '{"says": "kept"}'));
    expect(seen.method, 'POST');
    expect(seen.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), <String, Object?>{'a': 1});
  });

  test(
    'with no server both are asked and nothing has anywhere to go',
    () async {
      final storage = _Storage();
      final cloud = GameCloud(
        game: 'test',
        storage: storage,
        saves: SaveFile(appName: 'test', storage: storage),
        server: '',
        policy: '2026-10',
      );
      expect(cloud.sync, isNull);
      expect(cloud.uploader, isNull);
      await cloud.consents.answerTelemetry(granted: true);
      expect(await cloud.send(_demo()), isNull);
    },
  );

  test(
    'with one, the saves and the runs go to it, the runs only on a yes',
    () async {
      final storage = _Storage();
      final asked = <String>[];
      final cloud = GameCloud(
        game: 'platformer',
        storage: storage,
        saves: SaveFile(appName: 'test', storage: storage),
        server: 'https://example.test/',
        policy: '2026-10',
        client: MockClient((http.Request request) async {
          asked.add('${request.method} ${request.url}');
          return http.Response('{"run": 7, "eraseKey": "k"}', 201);
        }),
      );
      expect(cloud.sync, isNotNull);
      expect((await cloud.send(_demo()))!.did, isFalse);
      expect(asked, isEmpty);
      await cloud.consents.answerTelemetry(granted: true);
      expect((await cloud.send(_demo()))!.did, isTrue);
      expect(asked, <String>['POST https://example.test/api/telemetry/runs']);
    },
  );

  test('every game asks both, in its settings', () {
    // A scan, as `season_test.dart` in the racing game does: each game's
    // screen is a widget no test can mount without a window.
    for (final game in <String>['dungeon', 'platformer', 'racing']) {
      final main = File(
        '../../apps/flutter3d_demo_$game/lib/main.dart',
      ).readAsStringSync();
      expect(main, contains('privacy: _cloud.consents'), reason: game);
      expect(main, contains('_cloud.send('), reason: game);
    }
  });

  test('the two games with a run to keep sync it before they begin', () {
    for (final game in <String>['dungeon', 'platformer']) {
      final main = File(
        '../../apps/flutter3d_demo_$game/lib/main.dart',
      ).readAsStringSync();
      expect(
        main,
        contains('syncBeforeBegin(context, _cloud.sync)'),
        reason: game,
      );
    }
  });
}
