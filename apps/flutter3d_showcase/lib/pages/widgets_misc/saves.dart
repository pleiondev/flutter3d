/// Saves that outlive the build that wrote them: a schema with versions and
/// the migrations between them, an autosave at the moments a session tends
/// to end, and a copy in the cloud settled against this device's by step and
/// digest.
///
/// Everything here is kept in memory — a storage of a map and a cloud of
/// one slot — so the page writes nothing to the machine it runs on. A game
/// passes its platform's `Storage` and an `HttpCloudSaves` or
/// `PlatformCloudSaves` instead, and nothing else changes.
///
/// Quoted by `saves.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

// #region schema
/// The game's save data, by version. Version 0 kept health as a number;
/// version 1 made it a row of hearts; version 2 added a key ring. The
/// version is the number of migrations, so it cannot move without one.
final SaveSchema _schema = SaveSchema(<SaveMigration>[
  (Map<String, Object?> run) {
    final int health = (run.remove('health') as num? ?? 3).toInt();
    return run..['hearts'] = <bool>[for (var i = 0; i < health; i++) true];
  },
  (Map<String, Object?> run) => run..['keys'] = <String>[],
]);
// #endregion schema

/// A storage that is a map, counting its writes.
final class _Memory extends Storage {
  final Map<String, String> documents = <String, String>{};
  int writes = 0;

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async {
    writes++;
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

/// A cloud of one slot, versioned the way an `ETag` versions it, which
/// records every call made to it.
final class _Cloud extends CloudSaveStore {
  String? document;
  int revision = 0;
  final List<String> calls = <String>[];

  @override
  String get name => 'the cloud';

  @override
  Future<CloudFetch> fetch(String slot) async {
    calls.add('fetch');
    final String? kept = document;
    return kept == null
        ? const CloudEmpty()
        : CloudDocument(kept, version: '$revision');
  }

  @override
  Future<CloudPut> put(String slot, String doc, {String? replacing}) async {
    calls.add('put');
    if (replacing != (document == null ? null : '$revision')) {
      return const CloudMoved();
    }
    document = doc;
    revision++;
    return CloudStored(version: '$revision');
  }
}

/// One level's worth of the run.
final class _Level {
  int hearts = 3;
  int coins = 0;
  int steps = 0;
}

// #region session
/// The game, as a `RunSession`: how a level is opened, written down and
/// put back, and how far the run has got in steps.
final class _Game extends RunSession<_Level> {
  _Game(SaveFile saves) : super(firstLevel: 'cellar', saves: saves);

  @override
  Future<_Level> loadLevel(String asset) async => _Level();

  @override
  RunOutcome outcomeOf(_Level level) => RunOutcome.playing;

  @override
  String? nextOf(_Level level) => null;

  @override
  Snapshot snapshotOf(_Level level) => Snapshot(<String, Object?>{
    'hearts': <bool>[for (var i = 0; i < level.hearts; i++) true],
    'coins': level.coins,
    'keys': <String>[],
  });

  @override
  void restoreInto(_Level level, Snapshot snapshot) {
    level
      ..hearts = (snapshot.data['hearts'] as List<Object?>? ?? const []).length
      ..coins = snapshot.data.integer('coins');
  }

  @override
  int stepOf(_Level level) => level.steps;
}
// #endregion session

/// What the page found, kept for its claim and its picture.
final class SavesReport {
  SaveRead? old;
  SaveRead? newer;
  bool resumed = false;
  int heartsAfterLoad = 0;
  int coinsAfterLoad = 0;
  final List<bool> autosaves = <bool>[];
  final List<int> writesAfter = <int>[];
  int writtenSchema = -1;
  final List<SyncOutcome> outcomes = <SyncOutcome>[];
  int callsBeforeConsent = -1;
  int coinsAfterDownload = 0;
  bool inSyncAtEnd = false;
  int localStep = 0;
  int cloudStep = 0;
}

final class SavesDemo extends ShowcaseDemo {
  final SavesReport report = SavesReport();

  late final MeshNode _device;
  late final MeshNode _cloud;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.35
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Future<void> prepare(DemoContext context) => _run(report);

  static Future<void> _run(SavesReport out) async {
    final storage = _Memory();
    final saves = SaveFile(
      appName: 'showcase',
      storage: storage,
      onIssue: (_) {},
      schema: _schema,
    );

    // #region migrate
    // A save from the first release: no schema in it, so version 0, and
    // health as a number.
    const oldSave =
        '{"level": "cellar", "step": 900, '
        '"run": {"health": 2, "coins": 12}}';
    out.old = SaveRecord.read(jsonDecode(oldSave), _schema);
    // And one from a build newer than this one, which must be left alone.
    out.newer = SaveRecord.read(<String, Object?>{
      'level': 'cellar',
      'schema': 3,
      'run': <String, Object?>{'hearts': <bool>[], 'coins': 1},
    }, _schema);
    // #endregion migrate

    // #region load
    storage.documents[SaveFile.name] = oldSave;
    final game = _Game(saves);
    out.resumed = await game.begin();
    out.heartsAfterLoad = game.level!.hearts;
    out.coinsAfterLoad = game.level!.coins;
    // #endregion load

    // #region autosave
    final autosave = Autosave(game);
    final int before = storage.writes;
    out.autosaves
      ..add(await autosave.paused(now: false)) // playing: nothing to do
      ..add(await autosave.paused(now: true)) // into a pause: written
      ..add(await autosave.paused(now: true)); // still paused: not again
    out.writesAfter.add(storage.writes - before);
    await autosave.checkpoint(); // the same run: SaveFile skips the write
    out.writesAfter.add(storage.writes - before);
    game.level!
      ..coins += 5
      ..steps = 960;
    await autosave.checkpoint(); // a run that moved: written
    out.writesAfter.add(storage.writes - before);
    out.writtenSchema = (await saves.readRecord())?.schema ?? -1;
    // #endregion autosave

    // #region sync
    final cloud = _Cloud();
    final sync = SaveSync(saves: saves, store: cloud);
    // Off on a fresh install: no store is called at all.
    out.outcomes.add((await sync.sync()).outcome);
    out.callsBeforeConsent = cloud.calls.length;

    await sync.consent();
    out.outcomes.add((await sync.sync()).outcome); // the cloud was empty

    // Another device played on from there, three hundred steps further.
    cloud
      ..document = SaveFile.encode(
        SaveRecord(
          level: 'cellar',
          run: game.snapshotOf(_Level()..coins = 40),
          step: 1260,
          schema: _schema.version,
        ),
      )
      ..revision += 1;
    out.outcomes.add((await sync.sync()).outcome); // the further run is kept
    out.coinsAfterDownload = (await saves.readRecord())!.run.data.integer(
      'coins',
    );

    // Then both played apart, equally far: only the player can choose.
    await saves.writeRecord(
      SaveRecord(
        level: 'cellar',
        run: game.snapshotOf(_Level()..coins = 41),
        step: 1500,
        schema: _schema.version,
      ),
    );
    cloud
      ..document = SaveFile.encode(
        SaveRecord(
          level: 'cellar',
          run: game.snapshotOf(_Level()..coins = 52),
          step: 1500,
          schema: _schema.version,
        ),
      )
      ..revision += 1;
    final SyncReport asked = await sync.sync();
    out.outcomes.add(asked.outcome);
    out.outcomes.add((await sync.settle(asked, keepLocal: true)).outcome);
    // #endregion sync

    // Both sides now hold the run this device kept.
    final SaveRecord? local = await saves.readRecord();
    final SaveRecord? there = saves.parse(cloud.document ?? '');
    out
      ..inSyncAtEnd =
          resolveSaves(local: local, remote: there, base: sync.base) ==
              SaveResolution.inSync &&
          local != null
      ..localStep = local?.step ?? 0
      ..cloudStep = there?.step ?? 0;
  }

  @override
  Scene build(DemoContext context) {
    _device = blockNode(
      context,
      'this device',
      Vector3(0.8, 1.0, 0.8),
      Vector4(0.45, 0.7, 0.95, 1),
    );
    _cloud = blockNode(
      context,
      'the cloud',
      Vector3(0.8, 1.0, 0.8),
      Vector4(0.85, 0.85, 0.9, 1),
    );
    for (final (MeshNode node, int step, double x) in <(MeshNode, int, double)>[
      (_device, report.localStep, -1.0),
      (_cloud, report.cloudStep, 1.0),
    ]) {
      final double h = 0.2 + step / 1000.0;
      node
        ..setScale(1.0, h, 1.0)
        ..setPosition(x, h / 2.0, 0.0);
    }
    return sceneOf(<SceneNode>[
      floorNode(context, width: 6.0, depth: 4.0),
      _device,
      _cloud,
      // The hearts the version-0 save's health became.
      for (var i = 0; i < report.heartsAfterLoad; i++)
        ballNode(
          context,
          'heart $i',
          0.18,
          Vector4(0.9, 0.3, 0.35, 1),
          at: Vector3(-0.4 + i * 0.4, 0.2, 1.2),
        ),
    ]);
  }

  /// The page's claim, as the first thing that is not so, or null.
  @visibleForTesting
  String? wrong() {
    // #region check
    final SaveRead? old = report.old;
    if (old is! SaveFound || old.upgradedFrom != 0) {
      return 'the version-0 save was not migrated: $old';
    }
    final Map<String, Object?> run = old.record.run.data;
    if (old.record.schema != 2 ||
        run.containsKey('health') ||
        (run['hearts'] as List<Object?>?)?.length != 2 ||
        run['keys'] is! List ||
        old.record.step != 900) {
      return 'the migrated run is $run at schema ${old.record.schema}';
    }
    if (report.newer is! SaveNotRead || !(report.newer! as SaveNotRead).newer) {
      return 'a save from a newer build was not refused as newer';
    }
    if (!report.resumed ||
        report.heartsAfterLoad != 2 ||
        report.coinsAfterLoad != 12) {
      return 'the old save did not load into the game';
    }
    if (report.autosaves.join(',') != 'false,true,false' ||
        report.writesAfter.join(',') != '1,1,2' ||
        report.writtenSchema != 2) {
      return 'autosave wrote ${report.writesAfter} after ${report.autosaves}';
    }
    final String outcomes = <String>[
      for (final SyncOutcome o in report.outcomes) o.name,
    ].join(',');
    if (outcomes != 'notConsented,uploaded,downloaded,ask,uploaded' ||
        report.callsBeforeConsent != 0 ||
        report.coinsAfterDownload != 40 ||
        !report.inSyncAtEnd) {
      return 'the sync went $outcomes';
    }
    // #endregion check
    return null;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    final String? problem = wrong();
    if (problem != null) throw StateError(problem);
  }
}
