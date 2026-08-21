/// The half of a level that is not geometry.
///
///     flutter test test/pieces_test.dart
///
/// **A level editor that can only touch walls is a level editor that cannot
/// make a level.** The crypt is fifty-one brushes and sixteen other things: a
/// spawn point, six torches, two monsters, three pickups, a door, a key, a
/// trigger, a note and the way out. None of those are drawn by the renderer,
/// none of them could be clicked on, and none of them could be moved.
library;

import 'dart:convert';

import 'package:editor/src/editing.dart';
import 'package:editor/src/gizmos.dart';
import 'package:editor/src/picking.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

String _document() => jsonEncode(<String, Object?>{
      'version': 1,
      'name': 'test',
      'materials': <String, Object?>{
        'stone': <String, Object?>{'baseColor': <double>[0.5, 0.5, 0.5, 1.0]},
      },
      'brushes': <Object?>[
        <String, Object?>{
          'at': <double>[0.0, 0.0, -10.0],
          'size': <double>[20.0, 4.0, 1.0],
          'material': 'stone',
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0.0, 2.0, -4.0],
          'color': <double>[1.0, 0.6, 0.2],
          'intensity': 4.0,
          'range': 9.0,
        },
      ],
      'entities': <Object?>[
        <String, Object?>{'type': 'player_spawn', 'at': <double>[0.0, 0.0, 8.0]},
        // A torch **on** the wall, which in a document means inside it: the
        // wall runs from z = -9.5 to z = -10.5 and the torch sits in the middle
        // of it, a quarter of a metre behind the face a ray meets first.
        <String, Object?>{'type': 'torch', 'at': <double>[-4.0, 1.0, -10.0]},
        <String, Object?>{
          'type': 'monster',
          'at': <double>[2.0, 1.0, -6.0],
          'yaw': 1.5,
          'name': 'ghoul',
          // A property this editor has never heard of and must not lose.
          'patrol': <Object?>['a', 'b'],
        },
      ],
    });

Editing _open() => Editing.parse(_document(), path: '/levels/test.json');

void main() {
  group('selecting', () {
    test('a light is a thing that can be selected', () {
      final editing = _open()..select(Piece.light, 0);

      expect(editing.light, isNotNull);
      expect(editing.brush, isNull, reason: 'a light answered as a brush');
      expect(editing.says, contains('light'));
    });

    test('and so is a monster', () {
      final editing = _open()..select(Piece.entity, 2);

      expect(editing.entity!.type, 'monster');
      expect(editing.says, contains('ghoul'));
    });

    test('and an index past the end of a list selects nothing', () {
      final editing = _open()..select(Piece.light, 9);

      expect(editing.piece, isNull);
      expect(editing.kind, isNull, reason: 'it kept a kind with no index');
    });
  });

  group('moving', () {
    test('a monster moves it, on the same grid a wall uses', () {
      // One method for all three: the document keeps a monster's position in
      // `at` and a brush's in `at`, and an editor with a verb per kind is an
      // editor with three places to get the grid wrong.
      final editing = _open()..select(Piece.entity, 2);

      editing.nudge(Vector3(0.3, 0.0, 0.0));

      expect(editing.entity!.position.x, 2.25);
    });

    test('and a light moves the light rather than the room', () {
      final editing = _open()..select(Piece.light, 0);

      editing.nudge(Vector3(0.0, 1.0, 0.0));

      expect(editing.light!.position.y, 3.0);
      expect(editing.level.brushes.single.centre.y, 0.0);
    });
  });

  group('copying', () {
    test('a monster keeps everything the editor does not understand', () {
      // **This is how a level gets a second monster.** The editor has no
      // vocabulary — it cannot know what a monster needs in it, or which of a
      // lift's twelve properties matter — so it does not invent one. It copies
      // one the level already has, with everything it was carrying.
      final editing = _open()..select(Piece.entity, 2);

      editing.duplicate();

      expect(editing.level.entities.length, 4);
      final copy = editing.entity!;
      expect(copy.type, 'monster');
      expect(copy.yaw, 1.5);
      expect(copy.properties['patrol'], <Object?>['a', 'b']);
    });

    test('and it lands beside the original rather than inside it', () {
      final editing = _open()..select(Piece.entity, 2);

      editing.duplicate();

      expect(editing.entity!.position.x, greaterThan(2.0));
      expect(editing.entity!.position.z, -6.0);
    });

    test('and a light copies its colour and its reach', () {
      final editing = _open()..select(Piece.light, 0);

      editing.duplicate();

      expect(editing.level.lights.length, 2);
      expect(editing.light!.color.y, closeTo(0.6, 1e-6));
      expect(editing.light!.range, 9.0);
    });
  });

  group('deleting', () {
    test('takes the selected light and not a brush of the same number', () {
      // The bug a single index invites: three lists, one number, and a delete
      // that removes whichever list happened to be assumed.
      final editing = _open()..select(Piece.light, 0);

      editing.remove();

      expect(editing.level.lights, isEmpty);
      expect(editing.level.brushes.length, 1);
      expect(editing.piece, isNull);
    });

    test('and undo brings a monster back with its properties', () {
      final editing = _open()..select(Piece.entity, 2);

      editing.remove();
      expect(editing.level.entities.length, 2);

      editing.undo();

      expect(editing.level.entities.length, 3);
      expect(editing.level.entities[2].properties['patrol'],
          <Object?>['a', 'b']);
    });
  });

  group('a light', () {
    test('can be added, because the engine defines what one is', () {
      // A `LevelLight` is a place, a colour, a strength and a reach — writing a
      // new one down is not this application guessing at a game's vocabulary.
      // What a `monster` needs in it is not knowable here; what a point light
      // needs is.
      final editing = _open();

      editing.addLight(Vector3(1.0, 2.0, 3.0));

      expect(editing.level.lights.length, 2);
      expect(editing.kind, Piece.light);
      expect(editing.light!.position, Vector3(1.0, 2.0, 3.0));
    });

    test('and brightens by a factor rather than by an amount', () {
      // Light is read that way: the step from 1 to 2 is the step from 8 to 16,
      // and a constant would be useless at one end and unusable at the other.
      final editing = _open()..select(Piece.light, 0);

      editing.brighten(1.25);

      expect(editing.light!.intensity, closeTo(5.0, 1e-3));
    });

    test('and never quite goes out', () {
      // A light of zero is a light nobody can find again except by reading the
      // file.
      final editing = _open()..select(Piece.light, 0);

      for (var press = 0; press < 40; press++) {
        editing.brighten(0.8);
      }

      expect(editing.light!.intensity, greaterThanOrEqualTo(0.05),
          reason: 'forty presses put it at ${editing.light!.intensity}, which '
              'is a light nobody can find again except by reading the file');
    });
  });

  test('and an entity can be turned to face somewhere else', () {
    final editing = _open()..select(Piece.entity, 2);

    editing.turn(0.5);

    expect(editing.entity!.yaw, closeTo(2.0, 1e-3));
    expect(editing.entity!.properties['patrol'], <Object?>['a', 'b'],
        reason: 'turning it lost what it was carrying');
  });

  group('what a click hits', () {
    test('a monster in front of a wall, not the wall', () {
      // **Not a nicety.** A torch is on a wall, a monster stands on a floor, a
      // lift's marker sits inside the block it moves. Sorted strictly by
      // distance, every one of those is unclickable: the surface it is attached
      // to is always a little nearer.
      final level = _open().level;
      final handles = handlesOf(level);

      final found = Picking.at(
        handles,
        Vector3(2.0, 1.0, 4.0),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(found, isNotNull);
      expect(found!.kind, Piece.entity);
      expect(found.index, 2);
    });

    test('and a torch that is inside the wall it hangs on', () {
      // **The case the preference exists for**, and the one the first version
      // of this test missed by putting the monster in open air where it was
      // nearer anyway. A torch is authored inside the stonework; the wall's
      // surface is always the first thing a ray meets, so sorted strictly by
      // distance the torch is unclickable — which is to say every torch in the
      // crypt was unclickable.
      final found = Picking.at(
        handlesOf(_open().level),
        Vector3(-4.0, 1.0, 4.0),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(found!.kind, Piece.entity,
          reason: 'the wall in front of the torch took the click');
      expect(_open().level.entities[found.index].type, 'torch');
    });

    test('and the wall when nothing is standing against it', () {
      final found = Picking.at(
        handlesOf(_open().level),
        Vector3(-8.0, 0.0, 4.0),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(found!.kind, Piece.brush);
    });

    test('and a light, which the renderer draws nothing for at all', () {
      final found = Picking.at(
        handlesOf(_open().level),
        Vector3(0.0, 2.0, 4.0),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(found!.kind, Piece.light);
    });
  });

  group('the marks', () {
    test('are a colour per type, and the same colour every launch', () {
      // The editor cannot know that `monster` is dangerous and `pickup` is not
      // — it has no vocabulary. What it can do is give every distinct word its
      // own hue, so six of a kind read as six of a kind.
      expect(tintFor('monster'), tintFor('monster'));
      expect(tintFor('monster'), isNot(tintFor('pickup')));
    });

    test('and where the player starts is green, because that is what an editor '
        'looks for first', () {
      final spawn = tintFor('player_spawn');

      expect(spawn.y, greaterThan(spawn.x));
      expect(spawn.y, greaterThan(spawn.z));
    });

    test('and a light wears its own colour', () {
      final handles = handlesOf(_open().level)
          .where((Handle it) => it.kind == Piece.light);

      expect(handles.single.tint.x, greaterThan(handles.single.tint.z),
          reason: 'an orange lamp is not marked orange');
    });

    test('and a black light still has a mark somebody can see', () {
      final level = Level(lights: <LevelLight>[
        LevelLight(color: Vector3.zero()),
      ]);

      final tint = handlesOf(level).single.tint;

      expect(tint.length, greaterThan(0.1));
    });
  });
}
