/// Prefabs in the editor: made from a selection, placed, overridden,
/// applied, reverted and unpacked, each one step of undo.
///
///     dart test test/prefab_editing_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Editing _open() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0, -0.5, 0],
        'size': <double>[10, 1, 10],
      },
    ],
    'entities': <Object?>[
      <String, Object?>{
        'type': 'marker',
        'name': 'base',
        'at': <double>[2, 0, 2],
      },
      <String, Object?>{
        'type': 'lamp',
        'name': 'bulb',
        'at': <double>[2, 3, 2],
        'glow': <String, Object?>{'strength': 1.0},
      },
    ],
  }),
  path: '/levels/test.json',
);

/// [editing] with both entities made into the prefab `post`, its instance
/// selected.
Editing _withPost() {
  final editing = _open()
    ..select(Piece.entity, 0)
    ..toggle(Piece.entity, 1);
  expect(editing.history.run(const CreatePrefab('post')), isTrue);
  return editing;
}

List<EntityDef> _played(Editing editing) =>
    expandRecipes(editing.level).entities;

void main() {
  test('a selection becomes a prefab and one instance where it stood', () {
    final editing = _withPost();

    expect(editing.level.entities, hasLength(1));
    expect(editing.instance?.prefab, 'post');
    expect(editing.level.entities.single.position, Vector3(2, 0, 2));
    expect(
      editing.level.prefabs['post']!.entities.map((EntityDef e) => e.position),
      <Vector3>[Vector3.zero(), Vector3(0, 3, 0)],
    );
    // The level plays as it did before: the same two things in the same
    // places. Mutation: forget to subtract the origin in `createPrefab`.
    expect(_played(editing).map((EntityDef e) => e.position), <Vector3>[
      Vector3(2, 0, 2),
      Vector3(2, 3, 2),
    ]);
    expect(editing.level.toJson()['version'], Level.formatVersion);

    editing.undo();
    expect(editing.level.prefabs, isEmpty);
    expect(editing.level.entities, hasLength(2));
  });

  test('an edit of the template reaches every instance', () {
    final editing = _withPost();
    expect(
      editing.history.run(PlacePrefab('post', Vector3(6, 0, 0), called: 'b')),
      isTrue,
    );
    expect(
      editing.history.run(const SetPrefabField('post', 'bulb', 'size', 3)),
      isTrue,
    );
    expect(
      _played(editing)
          .where((EntityDef e) => e.type == 'lamp')
          .map((EntityDef e) => e.properties['size']),
      <Object?>[3, 3],
    );
  });

  test('an override is one instance\'s, until it is applied', () {
    final editing = _withPost();
    editing.history.run(PlacePrefab('post', Vector3(6, 0, 0), called: 'b'));
    editing.history.run(const SetOverride('bulb', 'glow.strength', 4.0));

    double strength(String name) {
      final lamp = _played(editing).firstWhere((EntityDef e) => e.name == name);
      final glow = lamp.properties['glow']! as Map<Object?, Object?>;
      return glow['strength']! as double;
    }

    expect(strength('b/bulb'), 4.0);
    expect(strength('bulb'), 1.0);

    expect(editing.history.run(const ApplyOverrides()), isTrue);
    expect(editing.instance!.overrides, isEmpty);
    expect(strength('bulb'), 4.0, reason: 'the template changed');
  });

  test('a reverted override shows the template again', () {
    final editing = _withPost();
    editing.history.run(const SetOverride('base', 'size', 9));
    expect(editing.history.run(const RevertOverrides(path: 'base')), isTrue);
    expect(editing.instance!.overrides, isEmpty);
    expect(editing.history.run(const RevertOverrides()), isFalse);
  });

  test('unpacking leaves the entities and no link', () {
    final editing = _withPost();
    editing.history.run(const SetOverride('base', 'size', 9));
    expect(editing.history.run(const UnpackPrefab()), isTrue);

    expect(
      editing.level.entities.where((EntityDef e) => e.type == 'prefab'),
      isEmpty,
    );
    expect(editing.level.entities.first.properties['size'], 9);
    expect(editing.selection, hasLength(2));
  });

  test('a prefab that would contain itself is refused', () {
    final editing = _withPost();
    // Make a second prefab around the first's instance, then point the
    // first at the second.
    editing.select(Piece.entity, 0);
    expect(editing.history.run(const CreatePrefab('outer')), isTrue);
    final before = editing.write();
    expect(
      editing.history.run(
        const SetPrefabField('post', 'base', 'type', 'prefab'),
      ),
      isFalse,
      reason: 'a prefab row that names no prefab does not expand',
    );
    editing.history.run(
      const SetPrefabField('post', 'base', 'prefab', 'outer'),
    );
    expect(
      editing.history.run(
        const SetPrefabField('post', 'base', 'type', 'prefab'),
      ),
      isFalse,
      reason: 'post → outer → post',
    );
    expect(prefabCycle(editing.level.prefabs), isNull);
    expect(editing.level.prefabs['post']!.entities.first.type, 'marker');
    expect(editing.write(), isNot(before), reason: 'the harmless edit stays');
  });
}
