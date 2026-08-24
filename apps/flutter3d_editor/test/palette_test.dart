/// What can be put into a level, and where it lands.
///
///     flutter test test/palette_test.dart
///
/// **The palette is built from the document, which is the only honest place to
/// get it.** This application has no vocabulary — it cannot know that a game
/// has monsters, or that this one calls them `monster` — so what it offers is
/// what the level already contains. A level with lifts offers lifts, and a
/// game this repository has never heard of gets an editor that knows its
/// words without a line being written about it.
library;

import 'dart:convert';

import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/gizmos.dart';
import 'package:flutter3d_editor/src/palette_items.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

String _document() => jsonEncode(<String, Object?>{
      'version': 1,
      'name': 'test',
      'materials': <String, Object?>{
        'stone': <String, Object?>{'baseColor': <double>[0.5, 0.5, 0.5, 1.0]},
        // A second one, and deliberately the rarer: with one material a brush
        // placed in the wrong material is indistinguishable from one placed in
        // the right one, and the test below was exactly that useless.
        'iron': <String, Object?>{'baseColor': <double>[0.3, 0.3, 0.35, 1.0]},
      },
      'brushes': <Object?>[
        <String, Object?>{
          'at': <double>[0.0, 0.0, 0.0],
          'size': <double>[10.0, 1.0, 10.0],
          'material': 'stone',
        },
        <String, Object?>{
          'at': <double>[0.0, 4.0, 0.0],
          'size': <double>[10.0, 1.0, 10.0],
          'material': 'stone',
        },
      ],
      'lights': <Object?>[
        <String, Object?>{'at': <double>[0.0, 3.0, 0.0], 'intensity': 2.0},
      ],
      'entities': <Object?>[
        <String, Object?>{'type': 'torch', 'at': <double>[1.0, 2.0, 0.0]},
        <String, Object?>{
          'type': 'monster',
          'at': <double>[3.0, 1.0, 0.0],
          'name': 'ghoul',
          'patrol': <Object?>['a', 'b'],
        },
        <String, Object?>{'type': 'torch', 'at': <double>[-1.0, 2.0, 0.0]},
      ],
    });

Editing _open() => Editing.parse(_document(), path: '/levels/test.json');

/// The palette row for [what], the way a click on the panel finds it.
Placeable _row(Editing editing, String what) =>
    paletteOf(editing.level).firstWhere((Placeable it) => it.what == what);

void main() {
  group('the list', () {
    test('is what this level is made of', () {
      final palette = paletteOf(_open().level)
          .map((Placeable it) => it.what)
          .toList();

      expect(palette, contains('monster'));
      expect(palette, contains('torch'));
      expect(palette, isNot(contains('coin')),
          reason: 'it offered a word this level has never used');
    });

    test('and a brush is offered as its materials, not as the word "brush"', () {
      // **The question that caused this**: "is brush a wall?" It is not — a
      // brush is a box, and what makes it a wall rather than a floor is the
      // material it names. A palette offering "brush" asks somebody to place a
      // thing and then find out what it turned out to be.
      final palette = paletteOf(_open().level);

      expect(palette.map((Placeable it) => it.what), contains('stone'));
      expect(palette.map((Placeable it) => it.what), isNot(contains('brush')));
      expect(palette.first.kind, Piece.brush);
    });

    test('and a material nothing is built of yet is still offered', () {
      // Usually one somebody wrote down in order to build with it.
      final level = Level(materials: <String, LevelMaterial>{
        'ice': LevelMaterial(),
      });

      final palette = paletteOf(level);

      expect(palette.map((Placeable it) => it.what), contains('ice'));
      expect(palette.firstWhere((Placeable it) => it.what == 'ice').count, 0);
    });

    test('and it says how many of each there are', () {
      // Worth its space: a level with no exit and a level with three are both
      // worth noticing before playing it.
      final counts = <String, int>{
        for (final it in paletteOf(_open().level)) it.what: it.count,
      };

      expect(counts['torch'], 2);
      expect(counts['monster'], 1);
      expect(counts['stone'], 2);
      expect(counts['iron'], 0);
      expect(counts[kLight], 1);
    });

    test('and an empty level still offers what the engine defines', () {
      final palette = paletteOf(Level());

      expect(palette.map((Placeable it) => it.kind),
          containsAll(<Piece>[Piece.brush, Piece.light]));
    });
  });

  group('placing', () {
    test('a monster copies one this level already has', () {
      // The palette's whole shape follows from this: the editor cannot know
      // what a `monster` needs in it, so it does not write one — it copies the
      // last one, which is usually the one somebody has just got right.
      final editing = _open();

      editing.place(_row(editing, 'monster'), Vector3(6.0, 1.0, 6.0));

      expect(editing.level.entities.length, 4);
      final placed = editing.entity!;
      expect(placed.type, 'monster');
      expect(placed.properties['patrol'], <Object?>['a', 'b']);
      expect(placed.position, Vector3(6.0, 1.0, 6.0));
    });

    test('and selects what it placed, because the next thing is to move it', () {
      final editing = _open();

      editing.place(_row(editing, 'torch'), Vector3(2.0, 2.0, 2.0));

      expect(editing.kind, Piece.entity);
      expect(editing.entity!.type, 'torch');
    });

    test('and a light is made rather than copied', () {
      final editing = _open();

      editing.place(_row(editing, kLight), Vector3(0.0, 4.0, 0.0));

      expect(editing.level.lights.length, 2);
      expect(editing.kind, Piece.light);
    });

    test('and a brush lands in the material its row named', () {
      // The rarer material on purpose: a level is mostly one thing, so placing
      // the commonest proves nothing about whether the row was read at all.
      final editing = _open();

      editing.place(_row(editing, 'iron'), Vector3(4.0, 0.0, 4.0));

      expect(editing.level.brushes.length, 3);
      expect(editing.kind, Piece.brush);
      expect(editing.brush!.material, 'iron',
          reason: 'it placed ${editing.brush!.material}, which is what most of '
              'this level is made of rather than what the row said');
    });

    test('and it lands on the grid like everything else', () {
      final editing = _open();

      editing.place(_row(editing, 'torch'), Vector3(1.1, 2.2, 3.3));

      expect(editing.entity!.position.x, 1.0);
      expect(editing.entity!.position.y, 2.25);
    });

    test('and a type with nothing to copy is made bare rather than refused', () {
      // Cannot come from the palette, which only lists what is here — but a
      // caller may ask, and refusing would mean an editor that cannot be the
      // first to place something.
      final editing = _open();

      editing.place(
        Placeable(
          kind: Piece.entity,
          what: 'wumpus',
          count: 0,
          tint: Vector3.zero(),
        ),
        Vector3.zero(),
      );

      expect(editing.entity!.type, 'wumpus');
    });

    test('and undo takes it away again', () {
      final editing = _open();

      editing.place(_row(editing, 'monster'), Vector3(6.0, 1.0, 6.0));
      editing.undo();

      expect(editing.level.entities.length, 3);
    });
  });
}
