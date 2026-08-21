/// What a game's own words look like, told to the editor by the game.
///
///     flutter test test/looks_test.dart
///
/// **The question this answers came from looking at a wall.** A torch was two
/// coloured boxes where a torch should be — because the crypt's document says
/// `type: torch` and where it is, and what a torch *looks* like is in the
/// game's code: it builds one out of primitives and a light, and there is no
/// torch model anywhere for anybody to find.
///
/// The editor cannot work that out and must not guess. So the game says, in a
/// file the editor reads without understanding a word of it: `monster` and
/// `torch` are keys here, exactly as they are in a level.
library;

import 'dart:io';

import 'package:editor/src/gizmos.dart';
import 'package:editor/src/looks.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String _file = '''
{
  "monster": { "model": "assets/models/monster_{kind}.glb",
               "size": [0.9, 1.9, 0.9] },
  "torch":   { "size": [0.22, 0.75, 0.22], "tint": [1.0, 0.55, 0.12] }
}
''';

EntityDef _entity(String type, {Map<String, Object?> properties = const {}}) =>
    EntityDef.fromJson(<String, Object?>{
      'type': type,
      'at': <double>[0.0, 0.0, 0.0],
      ...properties,
    });

void main() {
  final looks = Looks.parse(_file);

  group('a model', () {
    test('comes from the type when the entity does not name one', () {
      expect(
        looks.modelFor(_entity('monster', properties: <String, Object?>{
          'kind': 'runner',
        })),
        'assets/models/monster_runner.glb',
      );
    });

    test('and a property fills the gap in the path', () {
      // One line covers three monsters, and a game that adds a fourth adds a
      // file rather than a mapping. The dungeon keeps that map in Dart —
      // `runner`, `shooter`, `tank` — and an editor cannot import it.
      expect(
        looks.modelFor(_entity('monster', properties: <String, Object?>{
          'kind': 'tank',
        })),
        'assets/models/monster_tank.glb',
      );
    });

    test('and what the entity itself says wins', () {
      // A level that names a model on one particular thing has said something
      // about that thing, and a rule about its type must not overrule it.
      expect(
        looks.modelFor(_entity('monster', properties: <String, Object?>{
          'kind': 'runner',
          'model': 'assets/models/boss.glb',
        })),
        'assets/models/boss.glb',
      );
    });

    test('and a gap with nothing to fill it is left alone', () {
      // Rather than half-substituted: `monster_.glb` is a file nobody has, and
      // a model that will not read leaves the mark — which is exactly what
      // somebody wants to see when a property is missing.
      expect(looks.modelFor(_entity('monster')),
          'assets/models/monster_{kind}.glb');
    });

    test('and a type nobody described has none', () {
      expect(looks.modelFor(_entity('torch')), isNull);
    });
  });

  group('a size and a colour', () {
    test('make a torch a slim upright thing rather than a cube', () {
      final torch = looks.sizeFor(_entity('torch'))!;

      expect(torch.y, greaterThan(torch.x * 2));
    });

    test('and the entity still wins', () {
      expect(
        looks.sizeFor(_entity('torch', properties: <String, Object?>{
          'size': <double>[4.0, 4.0, 4.0],
        })),
        Vector3(4.0, 4.0, 4.0),
      );
    });

    test('and a described colour beats the one made from the name', () {
      final described = looks.tintFor(_entity('torch'))!;

      expect(described, isNot(tintFor('torch')));
      expect(described.x, greaterThan(described.z), reason: 'a torch is warm');
    });
  });

  group('a game that says nothing', () {
    test('gets marks, which is what it got before any of this', () {
      expect(Looks.none.isEmpty, isTrue);
      expect(Looks.none.modelFor(_entity('monster')), isNull);
      expect(Looks.none.sizeFor(_entity('torch')), isNull);
    });

    test('and a file that is not a map at all is the same as none', () {
      // A game whose file will not parse should lose its marks, not its editor.
      expect(Looks.parse('[]').isEmpty, isTrue);
      expect(Looks.parse('"hello"').isEmpty, isTrue);
    });

    test('and a size that is not three numbers is ignored', () {
      final broken = Looks.parse('{"torch": {"size": [1, "tall", 3]}}');

      expect(broken.sizeFor(_entity('torch')), isNull);
    });
  });

  test('and the handles are the size the game said', () {
    // The whole point of the file, at the place it lands: what a click hits and
    // what gets drawn are the same box, so describing a torch makes it both
    // look right and behave right.
    final level = Level(entities: <EntityDef>[_entity('torch')]);

    final handle = handlesOf(level, looks: looks).single;

    expect(handle.size.y, closeTo(0.75, 1e-6));
    expect(handle.tint.x, closeTo(1.0, 1e-6));
  });

  group('the crypt\'s own file', () {
    // Read off the disk, because it is data: nothing fails to compile when it
    // is deleted or mistyped, and the symptom is a wall with two boxes on it.
    final file = File('../dungeon/assets/editor.json');

    test('is there and describes the things that had no model', () {
      expect(file.existsSync(), isTrue,
          reason: 'the game that asked this question has stopped answering it');

      final said = Looks.parse(file.readAsStringSync());

      expect(said.sizeFor(_entity('torch')), isNotNull);
      expect(said.modelFor(_entity('monster', properties: <String, Object?>{
        'kind': 'runner',
      })), isNotNull);
    });

    test('and every model it names is a file that exists', () {
      // **The failure this catches is silent.** A path with a typo in it draws
      // the mark instead, which is exactly what an undescribed type draws — so
      // the editor looks like it ignored the file rather than like the file is
      // wrong.
      final said = Looks.parse(file.readAsStringSync());

      // The kinds the crypt actually uses, filled into the path the same way
      // the editor fills it.
      for (final kind in <String>['runner', 'shooter', 'tank']) {
        final path = said.modelFor(_entity('monster',
            properties: <String, Object?>{'kind': kind}))!;
        expect(File('../dungeon/$path').existsSync(), isTrue,
            reason: '$path is named and is not there');
      }
    });

    test('and it is not in the game\'s bundle, so it costs a player nothing', () {
      // The game lists four asset directories and this is beside them rather
      // than in one, which is the difference between a file an editor reads and
      // a file every player downloads.
      final pubspec = File('../dungeon/pubspec.yaml').readAsStringSync();

      expect(pubspec, isNot(contains('assets/editor.json')));
    });
  });
}
