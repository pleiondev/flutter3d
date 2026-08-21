/// What a monster is drawn as, and what it is doing.
///
///     flutter test test/monster_looks_test.dart
///
/// **The monsters were coloured capsules, and the file said so**: "what this
/// game's monsters are coloured, until they have models". They have models now,
/// and the interesting half is not the mesh — it is that a brain with six
/// states has to choose a clip, from three third-party exports that do not
/// carry the same clips.
///
/// Checked against the files this game ships, by reading their glTF. A mapping
/// that names a clip no model has is a monster frozen mid-stride, and there is
/// no run of the game that makes that obvious: you have to catch one in that
/// state and look at it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dungeon/src/monster_looks.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// The clip names inside a GLB, read from its JSON chunk.
///
/// Twenty lines of `ByteData` rather than a dependency, and rather than loading
/// the model through the engine — which would need a graphics device to upload
/// meshes this test never looks at.
Set<String> _clipsIn(String path) {
  final bytes = File(path).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'glTF',
      reason: '$path is not a GLB');
  final length = view.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, Object?>;
  final animations = json['animations'];
  if (animations is! List) return <String>{};
  return animations
      .whereType<Map<String, Object?>>()
      .map((Map<String, Object?> a) => a['name'])
      .whereType<String>()
      .toSet();
}

/// The models this game gives its monsters, by roster name.
///
/// Derived from the roster rather than read out of `DungeonMonsters`' private
/// table, so this checks the files the game will ask for rather than the map's
/// own opinion of them.
/// Read from `DungeonMonsters` rather than assembled from the roster and a
/// naming convention. **The first version did the latter and a mutation walked
/// through it**: deleting the tank's entry left the file on disk, so the test
/// went on finding it and the game went on drawing a capsule.
Map<String, String> _models() => DungeonMonsters.modelsForKind;

void main() {
  test('every monster in the roster has a model, and it is on disk', () {
    // Both halves, because either alone passes while the other is broken: a
    // kind missing from the table is a capsule, and a table naming a file that
    // is not there is a capsule too.
    for (final kind in Monsters.byName.keys) {
      final path = DungeonMonsters.modelsForKind[kind];
      expect(path, isNotNull, reason: '$kind is not given a model');
      expect(File(path!).existsSync(), isTrue,
          reason: '$kind is given $path, which is not there');
    }
  });

  test('and every state names a clip', () {
    // An empty list is a monster that keeps playing whatever it was, which for
    // a dead one means standing up again.
    for (final state in MonsterState.values) {
      expect(DungeonMonsters.clipsForState[state], isNotEmpty,
          reason: '$state would leave the monster mid-stride');
    }
  });

  group('every state', () {
    test('finds a clip in every model that ships', () {
      // **The claim this file exists for.** The runner has `Run`, `Punch` and
      // `HitReact`; the other two have none of those, and spell the third
      // `HitRecieve` — with the typo, which is in somebody else's file.
      //
      // Mutation: drop `Walk` from the chase list, or `Bite_Front` from the
      // attack list, and two of the three monsters slide about in their idle
      // pose.
      for (final entry in _models().entries) {
        final available = _clipsIn(entry.value);
        for (final state in MonsterState.values) {
          final wanted = DungeonMonsters.clipsForState[state]!;
          expect(wanted.any(available.contains), isTrue,
              reason: '${entry.key} has none of $wanted for $state; '
                  'it has $available');
        }
      }
    });

    test('and the preferred clip is the one the model has, where it has it', () {
      // The order is not decoration. A model with both `Run` and `Walk` should
      // run when it is chasing, and the list is how that is said — putting
      // `Walk` first would make every chase a stroll and nothing would fail.
      final runner = _clipsIn('assets/models/monster_runner.glb');

      expect(runner.contains('Run'), isTrue,
          reason: 'the runner cannot run, so this test proves nothing');
      expect(DungeonMonsters.clipsForState[MonsterState.chase]!.first, 'Run');
    });
  });

  test('and the exporter prefix is gone from every clip', () {
    // The files arrive with `CharacterArmature|` on every clip name — a fact
    // about a Blender file, not about an animation. `tool/prepare_monsters.py`
    // strips it; if that step is ever skipped, every name above misses and
    // every monster is a statue.
    for (final path in _models().values) {
      for (final clip in _clipsIn(path)) {
        expect(clip, isNot(contains('|')), reason: '$path still has $clip');
      }
    }
  });
}
