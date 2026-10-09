/// The index of save slots, in the format envelope.
///
///     flutter test test/save_slots_test.dart
///
/// **The index is the one file that says which slots hold a run**, because a
/// `Storage` has names and no listing. It was a bare `{"version": 1}`; it is
/// `f3d.saveSlots` now, and the old shape still reads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Snapshot;
import 'package:flutter_test/flutter_test.dart';

final class _Storage extends Storage {
  _Storage([Map<String, String>? documents])
    : documents = documents ?? <String, String>{};

  final Map<String, String> documents;

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async =>
      documents[name] = contents;

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  test('the version 1 index fixture lists its slots', () async {
    // Minted on 2026-10-09, when the index went into the envelope.
    final text = File('test/fixtures/v1/saves.json').readAsStringSync();
    final slots = SaveSlots(
      appName: 'test',
      storage: _Storage(<String, String>{SaveSlots.indexName: text}),
    );
    expect(await slots.ids(), <String>['main', 'autosave']);
  });

  test('the index before the envelope reads, and is written back in it, '
      'keeping what a later build added', () async {
    final storage = _Storage(<String, String>{
      SaveSlots.indexName: jsonEncode(<String, Object?>{
        'version': 1,
        'slots': <String>['a'],
        'pinned': 'a',
      }),
    });
    final slots = SaveSlots(appName: 'test', storage: storage);
    expect(await slots.ids(), <String>['a']);

    await slots
        .slot('b')
        .write('level.json', const Snapshot(<String, Object?>{}));

    // Mutation: write `{'version': 1, 'slots': ids}` again and the envelope
    // and `pinned` are gone.
    final written =
        jsonDecode(storage.documents[SaveSlots.indexName]!)
            as Map<String, Object?>;
    expect(written['format'], 'f3d.saveSlots');
    expect(written['slots'], <String>['a', 'b']);
    expect(written['pinned'], 'a');
  });

  test(
    'an index from a newer build is listed and never written over',
    () async {
      final newer = jsonEncode(<String, Object?>{
        'format': 'f3d.saveSlots',
        'version': SaveSlots.indexVersion + 1,
        'slots': <String>['a'],
      });
      final log = IssueLog();
      final storage = _Storage(<String, String>{SaveSlots.indexName: newer});
      final slots = SaveSlots(
        appName: 'test',
        storage: storage,
        onIssue: log.add,
      );

      expect(await slots.ids(), <String>['a']);
      await slots
          .slot('b')
          .write('level.json', const Snapshot(<String, Object?>{}));

      // Mutation: write the index regardless and the newer build loses it.
      expect(storage.documents[SaveSlots.indexName], newer);
      expect(log.isNotEmpty, isTrue);
    },
  );
}
