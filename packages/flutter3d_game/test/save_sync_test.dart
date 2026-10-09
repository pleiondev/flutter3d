/// A save on this device and a copy in the cloud, made one — and nothing sent
/// until the player says it may be.
///
///     flutter test test/save_sync_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// A store that keeps one slot, versions it, and records every call.
final class _Store extends CloudSaveStore {
  String? document;
  int revision = 0;
  final List<String> calls = <String>[];

  /// Another device's write, landed between this one's fetch and its put.
  String? writtenMeanwhile;

  @override
  String get name => 'the test cloud';

  @override
  Future<CloudFetch> fetch(String slot) async {
    calls.add('fetch $slot');
    final kept = document;
    return kept == null
        ? const CloudEmpty()
        : CloudDocument(kept, version: '$revision');
  }

  @override
  Future<CloudPut> put(
    String slot,
    String document, {
    String? replacing,
  }) async {
    calls.add('put $slot');
    final meanwhile = writtenMeanwhile;
    if (meanwhile != null) {
      writtenMeanwhile = null;
      this.document = meanwhile;
      revision++;
    }
    final current = this.document == null ? null : '$revision';
    if (replacing != current) return const CloudMoved();
    this.document = document;
    revision++;
    return CloudStored(version: '$revision');
  }
}

SaveRecord _run(int coins, {int step = 0}) => SaveRecord(
  level: 'one',
  run: Snapshot(<String, Object?>{'coins': coins}),
  step: step,
);

void main() async {
  late _Storage storage;
  late SaveFile saves;
  late _Store store;
  late SaveSync sync;

  setUp(() async {
    storage = _Storage();
    saves = SaveFile(appName: 't', storage: storage, onIssue: (_) {});
    store = _Store();
    sync = SaveSync(saves: saves, store: store);
  });

  group('consent', () {
    test('nothing is sent or asked for before the player agrees', () async {
      // Mutation: check consent after the fetch, or not at all. The first
      // tells a server who is playing before they said it may know; the
      // second uploads their run.
      await saves.writeRecord(_run(5, step: 100));

      final report = await sync.sync();

      expect(report.outcome, SyncOutcome.notConsented);
      expect(store.calls, isEmpty);
      expect(store.document, isNull);
    });

    test('consent is off on a fresh install and off when unreadable', () async {
      // Mutation: treat a missing or broken consent document as yes.
      expect(sync.hasConsent, isFalse);
      await storage.write(SaveSync.stateName, '{"consented": "yes"');
      expect(sync.hasConsent, isFalse);
      await storage.write(SaveSync.stateName, '{"consented": "yes"}');
      expect(sync.hasConsent, isFalse, reason: 'only true is consent');
    });

    test('the state is enveloped, keeps what it does not read, and its '
        'version 1 fixture reads', () async {
      // Minted on 2026-10-09 when the state went into the envelope.
      storage.documents[SaveSync.stateName] = File(
        'test/fixtures/v1/cloud_saves.json',
      ).readAsStringSync();
      final read = SaveSync(saves: saves, store: store);
      await read.ready;
      expect(read.hasConsent, isTrue);
      expect(read.base, '0123456789abcdef');

      storage.documents[SaveSync.stateName] = jsonEncode(<String, Object?>{
        'consented': true,
        'region': 'eu',
      });
      final old = SaveSync(saves: saves, store: store);
      await old.ready;
      expect(old.hasConsent, isTrue);
      await old.consent();
      final written =
          jsonDecode(storage.documents[SaveSync.stateName]!)
              as Map<String, Object?>;
      // Mutation: write the state without the envelope, or drop `region`.
      expect(written['format'], 'f3d.cloudSaves');
      expect(written['region'], 'eu');

      storage.documents[SaveSync.stateName] = jsonEncode(<String, Object?>{
        'format': 'f3d.cloudSaves',
        'version': SaveSync.stateVersion + 1,
        'consented': true,
      });
      final newer = SaveSync(saves: saves, store: store);
      await newer.ready;
      expect(newer.hasConsent, isFalse, reason: 'a newer document is no');
    });

    test('consent is kept, and withdrawing forgets the base', () async {
      expect(await sync.consent(), isTrue);
      expect(SaveSync(saves: saves, store: store).hasConsent, isTrue);

      await saves.writeRecord(_run(5));
      await sync.sync();
      expect(sync.base, isNotNull);

      // Mutation: keep the base on withdrawal. Turning cloud saves back on
      // months later resolves against a run both sides have long left.
      await sync.withdraw();
      expect(sync.hasConsent, isFalse);
      expect(sync.base, isNull);
      store.calls.clear();
      expect((await sync.sync()).outcome, SyncOutcome.notConsented);
      expect(store.calls, isEmpty);
    });

    test('settling a choice also needs consent', () async {
      await sync.consent();
      await saves.writeRecord(_run(1, step: 50));
      store.document = SaveFile.encode(_run(2, step: 50));
      final asked = await sync.sync();
      expect(asked.outcome, SyncOutcome.ask);

      await sync.withdraw();
      store.calls.clear();
      final settled = await sync.settle(asked, keepLocal: true);

      expect(settled.outcome, SyncOutcome.notConsented);
      expect(store.calls, isEmpty);
    });
  });

  group('with consent', () {
    setUp(() async => sync.consent());

    test('a first sync sends the run there is', () async {
      await saves.writeRecord(_run(5, step: 100));

      final report = await sync.sync();

      expect(report.outcome, SyncOutcome.uploaded);
      expect(saves.parse(store.document!)!.run.data['coins'], 5);
      expect(sync.base, (await saves.readRecord())!.digest);
    });

    test('a new device takes the run from the cloud', () async {
      store.document = SaveFile.encode(_run(9, step: 300));

      final report = await sync.sync();

      expect(report.outcome, SyncOutcome.downloaded);
      expect((await saves.read())!.run.data['coins'], 9);
      expect((await saves.readRecord())!.step, 300);
    });

    test('the further run wins when both moved', () async {
      await saves.writeRecord(_run(1, step: 100));
      store.document = SaveFile.encode(_run(2, step: 900));

      expect((await sync.sync()).outcome, SyncOutcome.downloaded);
      expect((await saves.read())!.run.data['coins'], 2);
    });

    test('equal runs say so and send nothing', () async {
      await saves.writeRecord(_run(4, step: 10));
      store.document = SaveFile.encode(_run(4, step: 10));
      store.calls.clear();

      expect((await sync.sync()).outcome, SyncOutcome.inSync);
      expect(store.calls, <String>['fetch save.json']);
    });

    test('a step back taken on this device is sent, not undone', () async {
      // Both sides agreed on the long run; then the player went back to an
      // earlier checkpoint here. Mutation: drop the base from `resolveSaves`,
      // and the further run in the cloud comes back over the player's choice.
      await saves.writeRecord(_run(8, step: 900));
      await sync.sync();
      await saves.writeRecord(_run(3, step: 200));

      expect((await sync.sync()).outcome, SyncOutcome.uploaded);
      expect(saves.parse(store.document!)!.run.data['coins'], 3);
    });

    test('two runs equally far along wait for the player', () async {
      await saves.writeRecord(_run(1, step: 500));
      store.document = SaveFile.encode(_run(2, step: 500));

      final asked = await sync.sync();
      expect(asked.outcome, SyncOutcome.ask);
      expect(
        (await saves.read())!.run.data['coins'],
        1,
        reason: 'nothing moved yet',
      );

      final kept = await sync.settle(asked, keepLocal: true);
      expect(kept.outcome, SyncOutcome.uploaded);
      expect(saves.parse(store.document!)!.run.data['coins'], 1);
    });

    test(
      'a write that lost a race fetches again rather than overwriting',
      () async {
        // Another device wrote between this one's fetch and its put. Mutation:
        // put without `replacing`, and the other device's run is overwritten
        // without ever being compared.
        await saves.writeRecord(_run(1, step: 100));
        store.writtenMeanwhile = SaveFile.encode(_run(7, step: 800));

        final report = await sync.sync();

        expect(report.outcome, SyncOutcome.downloaded);
        expect((await saves.read())!.run.data['coins'], 7);
        expect(store.calls, <String>[
          'fetch save.json',
          'put save.json',
          'fetch save.json',
        ]);
      },
    );

    test('a cloud save from a newer build is left alone', () async {
      // Mutation: treat an unreadable remote as no remote. The local run is
      // then uploaded over progress made on a newer build of the game.
      await saves.writeRecord(_run(1, step: 100));
      final newer = SaveFile(
        appName: 't',
        storage: _Storage(),
        schema: SaveSchema(<SaveMigration>[(run) => run]),
      );
      store.document = SaveFile.encode(
        SaveRecord(
          level: 'one',
          run: Snapshot(<String, Object?>{'coins': 2}),
          schema: newer.schema.version,
        ),
      );
      final before = store.document;

      final report = await sync.sync();

      expect(report.outcome, SyncOutcome.refused);
      expect(report.message, contains('newer build'));
      expect(store.document, before);
    });

    test('a store that is down is an answer, not a throw', () async {
      final down = SaveSync(saves: saves, store: _Down());

      final report = await down.sync();

      expect(report.outcome, SyncOutcome.unavailable);
      expect(report.message, 'no network');
    });
  });
}

final class _Down extends CloudSaveStore {
  @override
  String get name => 'down';

  @override
  Future<CloudFetch> fetch(String slot) async =>
      const CloudUnavailable('no network');

  @override
  Future<CloudPut> put(String slot, String document, {String? replacing}) =>
      throw UnimplementedError();
}
