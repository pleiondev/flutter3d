/// `LevelPatch` carries an edit to a running game as the rows that changed,
/// and refuses to be applied to any level but the one it was made against.
///
///     dart test test/level_patch_test.dart
///
/// Mutation: drop the `was` check in `applyTo` and a patch made against one
/// arrangement of brushes edits whichever brush now stands at that index;
/// align by position instead of by digest and a brush deleted from the
/// middle becomes a replacement of every row after it.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Map<String, Object?> _brush(double x, {String material = 'stone'}) =>
    <String, Object?>{
      'at': <double>[x, 0, 0],
      'size': <double>[1, 1, 1],
      'material': material,
    };

Map<String, Object?> _document() => <String, Object?>{
  'version': 1,
  'name': 'yard',
  'fogDensity': 0.02,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'color': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[for (var i = 0; i < 10; i++) _brush(i * 2.0)],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0, 3, 0],
    },
    <String, Object?>{
      'type': 'point',
      'at': <double>[6, 3, 0],
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'crate',
      'at': <double>[2, 0, 2],
    },
  ],
};

Level _edited(void Function(Map<String, Object?> json) edit) {
  final json = jsonDecode(jsonEncode(_document())) as Map<String, Object?>;
  edit(json);
  return Level.fromJson(json);
}

List<Object?> _list(Map<String, Object?> json, String key) =>
    json[key]! as List<Object?>;

/// The level [patch] makes of [level], or a failure naming the refusal.
Level _applied(LevelPatch patch, Level level) => switch (patch.applyTo(level)) {
  LevelPatched(:final level) => level,
  LevelPatchRefused(:final reason) => fail('refused: $reason'),
};

void main() {
  final before = Level.fromJson(_document());

  test('a moved brush is one row, and the run is told it was a brush', () {
    final after = _edited((json) => _list(json, 'brushes')[4] = _brush(8.5));

    final patch = LevelPatch.between(before, after);

    expect(patch.rows, hasLength(1));
    expect(patch.rows.single.at, 4);
    expect(patch.materials, isEmpty);
    expect(patch.fields, isEmpty);
    final result = patch.applyTo(before) as LevelPatched;
    expect(result.level.digestHex, after.digestHex);
    expect(result.diff.simulation, <String>['brushes']);
  });

  test('a brush taken from the middle is one edit, not the rest shifted', () {
    final after = _edited((json) => _list(json, 'brushes').removeAt(3));

    final patch = LevelPatch.between(before, after);

    expect(patch.rows, hasLength(1));
    expect(patch.rows.single.removes, isTrue);
    expect(_applied(patch, before).digestHex, after.digestHex);
  });

  test('a lamp recoloured is that lamp; one added is a count change', () {
    final recoloured = _edited(
      (json) => (_list(json, 'lights')[1]! as Map<String, Object?>)['color'] =
          <double>[1, 0.5, 0.2],
    );
    final one = LevelPatch.between(before, recoloured).applyTo(before);
    expect((one as LevelPatched).diff.lights, <int>[1]);
    expect(one.diff.lightCountChanged, isFalse);
    expect(one.diff.isPresentationOnly, isTrue);

    final added = _edited(
      (json) => _list(json, 'lights').insert(1, <String, Object?>{
        'type': 'point',
        'at': <double>[3, 3, 0],
      }),
    );
    final two = LevelPatch.between(before, added).applyTo(before);
    expect((two as LevelPatched).diff.lightCountChanged, isTrue);
    expect(two.diff.isPresentationOnly, isTrue);
  });

  test('materials go by name and the fog as a field', () {
    final after = _edited((json) {
      (json['materials']! as Map<String, Object?>)['moss'] = <String, Object?>{
        'color': <double>[0.1, 0.4, 0.1, 1.0],
      };
      json['fogDensity'] = 0.05;
    });

    final patch = LevelPatch.between(before, after);

    expect(patch.rows, isEmpty);
    expect(patch.materials.keys, <String>['moss']);
    expect(patch.fields.keys, <String>['fogDensity']);
    final result = patch.applyTo(before) as LevelPatched;
    expect(result.diff.materials, <String>['moss']);
    expect(result.diff.fog, isTrue);
    expect(result.diff.isPresentationOnly, isTrue);
  });

  test('a list one side lacks goes whole, and is compared as a document', () {
    final bare = Level.fromJson(
      <String, Object?>{..._document()}..remove('lights'),
    );

    final patch = LevelPatch.between(bare, before);

    expect(patch.fields.keys, <String>['lights']);
    final result = patch.applyTo(bare) as LevelPatched;
    expect(result.level.digestHex, before.digestHex);
    expect(result.diff.lightCountChanged, isTrue);
  });

  test('refuses a level it was not made against, naming both', () {
    final after = _edited((json) => json['fogDensity'] = 0.05);
    final other = _edited((json) => _list(json, 'brushes').removeAt(0));

    final result = LevelPatch.between(before, after).applyTo(other);

    expect(result, isA<LevelPatchRefused>());
    expect(
      (result as LevelPatchRefused).reason,
      allOf(contains(before.digestHex), contains(other.digestHex)),
    );
  });

  test('refuses a row that is not the one it names', () {
    final after = _edited((json) => _list(json, 'brushes')[4] = _brush(8.5));
    final patch = LevelPatch.between(before, after);
    final pointedElsewhere = LevelPatch(
      base: patch.base,
      hash: patch.hash,
      rows: <RowEdit>[
        RowEdit(
          list: 'brushes',
          at: 5,
          was: patch.rows.single.was,
          row: patch.rows.single.row,
        ),
      ],
    );

    final result = pointedElsewhere.applyTo(before);

    expect((result as LevelPatchRefused).reason, contains('brushes[5]'));
  });

  test('crosses the wire as JSON and still applies', () {
    final after = _edited((json) {
      _list(json, 'brushes')
        ..removeAt(7)
        ..insert(2, _brush(-3, material: 'moss'));
      _list(json, 'entities').add(<String, Object?>{'type': 'crate'});
      json['music'] = 'rain.ogg';
    });

    final sent = LevelPatch.fromJson(
      jsonDecode(jsonEncode(LevelPatch.between(before, after).toJson()))
          as Map<String, Object?>,
    );

    final result = sent.applyTo(before) as LevelPatched;
    expect(result.level.digestHex, after.digestHex);
    expect(result.diff.simulation, <String>['brushes', 'entities']);
    expect(result.diff.music, isTrue);
  });

  test('any shuffle of rows patches to exactly the edited level', () {
    // Removals, insertions, moves and duplicates at random, against the
    // whole-document digest: the claim is that the alignment never produces
    // a patch that makes a different level.
    final random = math.Random(7);
    for (var round = 0; round < 200; round++) {
      final after = _edited((json) {
        final brushes = _list(json, 'brushes');
        for (var n = random.nextInt(6); n > 0; n--) {
          switch (random.nextInt(4)) {
            case 0 when brushes.isNotEmpty:
              brushes.removeAt(random.nextInt(brushes.length));
            case 1:
              brushes.insert(
                random.nextInt(brushes.length + 1),
                _brush(random.nextInt(40) / 2),
              );
            case 2 when brushes.isNotEmpty:
              brushes[random.nextInt(brushes.length)] = _brush(-1.0 - round);
            case _ when brushes.isNotEmpty:
              brushes.add(brushes[random.nextInt(brushes.length)]);
          }
        }
      });
      final patch = LevelPatch.between(before, after);
      expect(
        _applied(patch, before).digestHex,
        after.digestHex,
        reason: 'round $round',
      );
      expect(
        patch.rows.length,
        lessThanOrEqualTo(10 + after.brushes.length),
        reason: 'never more edits than rows on both sides',
      );
    }
  });

  test('the same level is an empty patch', () {
    expect(
      LevelPatch.between(before, Level.fromJson(_document())).isEmpty,
      isTrue,
    );
  });
}
