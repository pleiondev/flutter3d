/// What a game asks before anything of the player's leaves the device, and
/// that nothing does until the player says it may.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  String? read(String name) => documents[name];
  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// A store that only counts what is asked of it.
final class _Counted implements CloudSaveStore {
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
      expect(it.consents.cloud, isFalse);
      expect(it.consents.sendsRuns, isFalse);
      expect(it.consents.telemetry.asked, isFalse);

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
      expect(it.consents.answerTelemetry(true), isTrue);
      expect(it.consents.sendsRuns, isTrue);
      expect((await uploader.send(_demo())).did, isTrue);
      expect(posted, hasLength(1));
      expect(it.consents.answerCloud(true), isTrue);
      expect(
        (await it.consents.sync!.sync()).outcome,
        isNot(SyncOutcome.notConsented),
      );
      expect(it.store.calls, isNotEmpty);

      // And taken back, stops at the next send.
      it.consents.answerTelemetry(false);
      expect((await uploader.send(_demo())).did, isFalse);
      expect(posted, hasLength(1));
    },
  );

  test('a new wording asks again', () {
    final it = fresh();
    it.consents.answerTelemetry(true);
    final reworded = Consents(storage: it.consents.storage, policy: '2027-01');
    expect(reworded.telemetry.granted, isTrue);
    expect(reworded.sendsRuns, isFalse);
  });

  test('a build with no save server says so, and its switch does nothing', () {
    final consents = Consents(storage: _Storage(), policy: '2026-10');
    expect(consents.cloud, isFalse);
    expect(consents.answerCloud(true), isFalse);
    expect(consents.cloud, isFalse);
  });

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

  testWidgets('the panel asks both, off until turned on', (tester) async {
    final it = fresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrivacySection(consents: it.consents)),
      ),
    );
    Switch switchIn(String key) => tester.widget<Switch>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Switch),
      ),
    );
    expect(switchIn('privacy:cloud').value, isFalse);
    expect(switchIn('privacy:telemetry').value, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('privacy:telemetry')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    expect(switchIn('privacy:telemetry').value, isTrue);
    expect(it.consents.sendsRuns, isTrue);
    expect(it.consents.cloud, isFalse);
  });

  testWidgets('two runs equally far along: the player picks one', (
    tester,
  ) async {
    bool? kept;
    final asked = SyncReport(
      SyncOutcome.ask,
      'This device and the cloud each have a run.',
      local: SaveRecord(
        level: 'assets/levels/crypt.json',
        run: const Snapshot(<String, Object?>{}),
        step: 600,
      ),
      remote: SaveRecord(
        level: 'assets/levels/deep.json',
        run: const Snapshot(<String, Object?>{}),
        step: 4200,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => kept = await askWhichRun(context, asked),
            child: const Text('sync'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sync'));
    await tester.pumpAndSettle();
    expect(find.text('On this device: crypt.json, 10s in'), findsOneWidget);
    expect(find.text('In the cloud: deep.json, 1m10s in'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('run:remote')));
    await tester.pumpAndSettle();
    expect(kept, isFalse);
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
      );
      expect(cloud.sync, isNull);
      expect(cloud.uploader, isNull);
      cloud.consents.answerTelemetry(true);
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
        client: MockClient((http.Request request) async {
          asked.add('${request.method} ${request.url}');
          return http.Response('{"run": 7, "eraseKey": "k"}', 201);
        }),
      );
      expect(cloud.sync, isNotNull);
      expect((await cloud.send(_demo()))!.did, isFalse);
      expect(asked, isEmpty);
      cloud.consents.answerTelemetry(true);
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

  testWidgets('before a run begins, the cloud is asked only after a yes', (
    tester,
  ) async {
    final it = fresh();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // No cloud, nothing to say.
    expect(await syncBeforeBegin(context, null), isNull);
    // Mutation: syncing whether or not the player said yes.
    expect(await syncBeforeBegin(context, it.consents.sync), isNotNull);
    expect(it.store.calls, isEmpty);
    it.consents.answerCloud(true);
    await syncBeforeBegin(context, it.consents.sync);
    expect(it.store.calls, contains('fetch'));
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
