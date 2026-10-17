/// The level as an outliner shows it.
///
///     dart test test/outline_test.dart
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Level _level() => Level.fromJson(<String, Object?>{
  'version': 1,
  'name': 'test',
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[2.0, 2.0, 2.0],
      'material': 'stone',
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'name': 'hall lamp',
      'at': <double>[0.0, 3.0, 0.0],
    },
  ],
  'entities': <Object?>[
    <String, Object?>{'type': 'torch'},
    <String, Object?>{'type': 'spawn'},
    <String, Object?>{'type': 'torch', 'name': 'doorway'},
  ],
});

void main() {
  test('brushes, lights, then one heading per entity type', () {
    // Mutation: drop the `if (... == type)` filter in the entity rows. Every
    // heading then holds all three entities, and the torch count reads 3.
    final groups = outlineOf(_level());

    expect(
      <String>[for (final g in groups) g.title],
      <String>['Brushes', 'Lights', 'torch', 'spawn'],
    );
    final torches = groups[2].entries;
    expect(<int>[for (final e in torches) e.index], <int>[0, 2]);
  });

  test('a name is the label, and what it is moves to the detail', () {
    final groups = outlineOf(_level());

    expect(groups[1].entries.single.label, 'hall lamp');
    expect(groups[2].entries[0].label, 'torch 0');
    expect(groups[2].entries[1].label, 'doorway');
    expect(groups[2].entries[1].detail, 'torch');
    expect(groups[0].entries.single.detail, 'stone');
  });

  test('a filter keeps matching rows and drops empty headings', () {
    // Mutation: keep every heading regardless of what is left under it. The
    // brushes, lights and spawn headings come back empty.
    final groups = outlineOf(_level(), filter: 'DOOR');

    expect(groups, hasLength(1));
    expect(groups.single.title, 'torch');
    expect(groups.single.entries.single.picked, (kind: Piece.entity, index: 2));
  });
}
