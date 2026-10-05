/// What this server offers, held against the list of commands that exists.
///
/// **The drift this file exists to stop has a shape.** `editorCommandNames`
/// lives beside the sealed hierarchy it describes, and its own doc says why: a
/// server keeping its own copy is a server that silently cannot call the
/// eleventh command, with nothing to say so until somebody asks for it. That is
/// exactly this package — so the copy is checked, both ways round, rather than
/// trusted.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef, expandRecipes;
import 'package:test/test.dart';

void main() {
  Set<String> namesOf(Iterable<EditorTool> tools) =>
      tools.map((EditorTool it) => it.name).toSet();

  test('every editor command is offered as a tool', () {
    expect(
      editorCommandNames.toSet().difference(namesOf(editorTools)),
      isEmpty,
      reason:
          'a command exists that this server cannot call, and an agent reading '
          'tools/list has no way to find out that it is missing',
    );
  });

  test('every tool is a command, a session verb or a way to look', () {
    // Named rather than counted: a count would pass a rename, and what a reader
    // of this file wants to know is *which* ones are not document commands.
    const beyondTheCommands = <String>{
      'list',
      'select',
      'undo',
      'redo',
      'generate',
      'validate',
      'save',
      'screenshot',
      'report',
      'optimizeLights',
      'play',
      'play_status',
      'play_swap',
      'play_stop',
      'play_devices',
      'setBehaviour',
      'removeBehaviour',
      'setCutscene',
      'removeCutscene',
    };
    expect(
      namesOf(editorTools).difference(editorCommandNames.toSet()),
      beyondTheCommands,
      reason:
          'a tool was added or dropped that is not one of the document '
          'commands; say what it is here so the set stays a decision',
    );
  });

  test('no tool is offered twice', () {
    expect(namesOf(editorTools), hasLength(editorTools.length));
  });

  test('every tool describes itself in a sentence', () {
    for (final offered in editorTools) {
      expect(
        offered.tool.description,
        isNotNull,
        reason:
            '${offered.name} has no description, so nothing tells an agent '
            'when to call it',
      );
      expect(offered.tool.description!.length, greaterThan(40));
    }
  });

  test('an argument the format cannot read is refused, not defaulted', () async {
    // Through the table rather than through the protocol, because this is about
    // what a body does with a map: the schema would have refused this call
    // before it arrived, and the reader behind it still has to answer no.
    final session = EditorSession(
      Editing.parse(_bareLevel, path: 'nowhere.json'),
    );
    final moveBy = editorTools.firstWhere(
      (EditorTool it) => it.name == 'moveBy',
    );
    final refused = await moveBy.run(session, <String, Object?>{
      'by': 'sideways',
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('cannot be read'));
  });

  group('generate', () {
    // The picture half is null for every tool but the screenshot.
    Future<Answer> generate(
      EditorSession session,
      Map<String, Object?> arguments,
    ) async {
      final answer = await editorTools
          .firstWhere((EditorTool it) => it.name == 'generate')
          .run(session, arguments);
      return (did: answer.did, says: answer.says);
    }

    const room = <String, Object?>{
      'kind': 'room',
      'seed': 7,
      'params': <String, Object?>{
        'at': <double>[20.0, 0.0, 0.0],
        'size': <double>[8.0, 3.0, 6.0],
        'doors': <Object?>[
          <String, Object?>{'side': 'north', 'width': 2.0, 'height': 2.4},
        ],
        'clutter': <String, Object?>{
          'count': 3,
          'size': <double>[1.0, 1.0, 1.0],
        },
      },
    };

    test(
      'writes the recipe into the document and counts what it builds',
      () async {
        final session = EditorSession(
          Editing.parse(_bareLevel, path: 'nowhere.json'),
        );
        final added = await generate(session, room);
        expect(added.did, isTrue, reason: added.says);
        expect(added.says, contains('from seed 7'));
        // The recipe, not its brushes: the document still has its one brush.
        final level = session.editing.level;
        expect(level.brushes, hasLength(1));
        expect(level.recipes.single.seed, 7);
        // Mutation: count the document's brushes instead of the recipe's and
        // this says "1 brush".
        final built = expandRecipes(level).brushes.length - 1;
        expect(built, greaterThan(6));
        expect(added.says, contains('$built brushes'));
      },
    );

    test('a level built from a recipe validates', () async {
      final session = EditorSession(
        Editing.parse(_litLevel, path: 'nowhere.json'),
      );
      await generate(session, room);
      // Mutation: build the vocabulary from the document's own rows only and
      // the room's reflection probes come back as unknown entities.
      expect(session.validate(), 'no issues');
    });

    test('the same seed writes the same level, and undo takes it back', () async {
      Future<String> written() async {
        final session = EditorSession(
          Editing.parse(_bareLevel, path: 'nowhere.json'),
        );
        final said = await generate(session, room);
        return '${said.says}\n${expandRecipes(session.editing.level).toJson()}';
      }

      expect(await written(), await written());
      final session = EditorSession(
        Editing.parse(_bareLevel, path: 'nowhere.json'),
      );
      await generate(session, room);
      final undone = session.undo();
      expect(undone.says, contains('generate a room from seed 7'));
      expect(session.editing.level.recipes, isEmpty);
    });

    test('a recipe no kit can build is refused and leaves no step', () async {
      final session = EditorSession(
        Editing.parse(_bareLevel, path: 'nowhere.json'),
      );
      final refused = await generate(session, <String, Object?>{
        'kind': 'room',
        'params': <String, Object?>{
          'at': <double>[0.0, 0.0, 0.0],
        },
      });
      expect(refused.did, isFalse);
      expect(refused.says, startsWith('no room was added'));
      expect(session.editing.level.recipes, isEmpty);
      expect(session.editing.canUndo, isFalse);
    });
  });

  group('behaviours', () {
    Future<Answer> call(
      EditorSession session,
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final answer = await editorTools
          .firstWhere((EditorTool it) => it.name == tool)
          .run(session, arguments);
      return (did: answer.did, says: answer.says);
    }

    const guard = <String, Object?>{
      'kind': 'sequence',
      'children': <Object?>[
        <String, Object?>{'kind': 'goTo', 'key': 'post'},
        <String, Object?>{'kind': 'wait', 'seconds': 1},
      ],
    };

    test('a tree is written, listed, saved and undone', () async {
      final session = EditorSession(
        Editing.parse(_bareLevel, path: 'nowhere.json'),
      );
      final wrote = await call(session, 'setBehaviour', <String, Object?>{
        'name': 'guard',
        'tree': guard,
      });
      expect(wrote.did, isTrue, reason: wrote.says);
      expect(session.listing(), contains('behaviours: guard'));
      // Mutation: a level that does not write its behaviours loses them on
      // the way through a save.
      final saved = Editing.parse(session.editing.write(), path: 'again.json');
      expect(saved.level.behaviours['guard'], guard);
      expect(session.undo().says, contains('set behaviour guard'));
      expect(session.editing.level.behaviours, isEmpty);
    });

    test(
      'a tree that does not read is refused with where, and no step',
      () async {
        final session = EditorSession(
          Editing.parse(_bareLevel, path: 'nowhere.json'),
        );
        final refused = await call(session, 'setBehaviour', <String, Object?>{
          'name': 'guard',
          'tree': <String, Object?>{
            'kind': 'sequence',
            'children': <Object?>[
              <String, Object?>{'kind': 'teleport'},
            ],
          },
        });
        expect(refused.did, isFalse);
        expect(refused.says, contains('teleport'));
        expect(refused.says, contains('children[0]'));
        expect(session.editing.level.behaviours, isEmpty);
        expect(session.editing.canUndo, isFalse);
      },
    );

    test('validate names an entity running a tree the level does not have', () {
      final session = EditorSession(
        Editing.parse(_guardedLevel, path: 'nowhere.json'),
      );
      // Mutation: a validator without the behaviour rule says nothing here.
      expect(session.validate(), contains('runs behaviour "guard"'));
      session.editing.setBehaviour('guard', guard);
      expect(session.validate(), 'no issues');
      expect(
        session.removeBehaviour('patrol').says,
        contains('there is no behaviour patrol'),
      );
    });
  });

  group('cutscenes', () {
    Future<Answer> call(
      EditorSession session,
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final answer = await editorTools
          .firstWhere((EditorTool it) => it.name == tool)
          .run(session, arguments);
      return (did: answer.did, says: answer.says);
    }

    const scene = <String, Object?>{
      'seconds': 4,
      'camera': <String, Object?>{
        'ease': true,
        'keys': <Object?>[
          <String, Object?>{
            't': 0,
            'at': <double>[0, 2, 4],
            'look': <double>[0, 1, 0],
          },
          <String, Object?>{
            't': 4,
            'at': <double>[4, 3, 0],
            'look': <double>[0, 1, 0],
          },
        ],
      },
      'subtitles': <Object?>[
        <String, Object?>{'from': 0.5, 'to': 3, 'text': 'Look.'},
      ],
    };

    test('the sanctum\'s scene, taken out and written back by an agent, '
        'leaves the level as it was', () async {
      final text = File(
        '../../apps/flutter3d_demo_dungeon/assets/levels/sanctum.json',
      ).readAsStringSync();
      final shipped = Editing.parse(text, path: 'sanctum.json');
      final scene = shipped.cutscenes['the_altar']!;
      final at = shipped.level.named('the_altar')!.position;
      final before = EditorSession(shipped).validate();

      final session = EditorSession(Editing.parse(text, path: 'sanctum.json'));
      expect(session.editing.removeCutscene('the_altar'), isTrue);
      expect(session.editing.level.named('the_altar'), isNull);
      final wrote = await call(session, 'setCutscene', <String, Object?>{
        'name': 'the_altar',
        // Through JSON, as an agent's arguments arrive.
        'sequence': jsonDecode(jsonEncode(scene)),
        'at': <double>[at.x, at.y, at.z],
      });
      expect(wrote.did, isTrue, reason: wrote.says);
      expect(session.validate(), before);
      expect(
        Editing.parse(session.editing.write(), path: 'a.json').cutscenes,
        shipped.cutscenes,
      );
    });

    test('an agent writes one from nothing, and the level validates', () async {
      final session = EditorSession(
        Editing.parse(_litLevel, path: 'nowhere.json'),
      );
      final wrote = await call(session, 'setCutscene', <String, Object?>{
        'name': 'intro',
        'sequence': scene,
        'at': <double>[0, 0, 0],
      });
      expect(wrote.did, isTrue, reason: wrote.says);
      expect(session.listing(), contains('cutscene'));
      expect(session.validate(), 'no issues');
      // Saved and read back, the scene is the entity's.
      final again = Editing.parse(session.editing.write(), path: 'a.json');
      expect(again.cutscenes['intro'], scene);
      expect(session.undo().says, contains('set cutscene intro'));
      expect(session.editing.cutscenes, isEmpty);
    });

    test('a scene that does not read is refused with where', () async {
      final session = EditorSession(
        Editing.parse(_bareLevel, path: 'nowhere.json'),
      );
      // Mutation: writing the sequence without reading it first.
      final refused = await call(session, 'setCutscene', <String, Object?>{
        'name': 'intro',
        'sequence': <String, Object?>{
          'seconds': 2,
          'actors': <Object?>[
            <String, Object?>{'t': 0, 'actor': 'guard', 'do': 'dance'},
          ],
        },
      });
      expect(refused.did, isFalse);
      expect(refused.says, contains('actors[0].do'));
      expect(session.editing.cutscenes, isEmpty);
      expect(session.editing.canUndo, isFalse);
    });

    test(
      'a name something else has is refused, and one can be removed',
      () async {
        final session = EditorSession(
          Editing.parse(_guardedLevel, path: 'nowhere.json'),
        );
        session.editing.level.entities.add(
          EntityDef(
            type: 'monster',
            name: 'gate',
            properties: <String, Object?>{'kind': 'runner'},
          ),
        );
        // Mutation: making a second entity under a name one already has.
        final clash = await call(session, 'setCutscene', <String, Object?>{
          'name': 'gate',
          'sequence': scene,
        });
        expect(clash.did, isFalse);
        expect(clash.says, contains('already the name'));
        final wrote = await call(session, 'setCutscene', <String, Object?>{
          'name': 'intro',
          'sequence': scene,
        });
        expect(wrote.did, isTrue);
        final replaced = await call(session, 'setCutscene', <String, Object?>{
          'name': 'intro',
          'sequence': <String, Object?>{'seconds': 1},
        });
        expect(replaced.says, startsWith('replaced'));
        expect(session.editing.cutscenes['intro'], <String, Object?>{
          'seconds': 1,
        });
        final removed = await call(session, 'removeCutscene', <String, Object?>{
          'name': 'intro',
        });
        expect(removed.did, isTrue);
        expect(session.editing.cutscenes, isEmpty);
      },
    );
  });

  test('optimizeLights keeps one of three lamps in one place, and undo '
      'puts all three back', () async {
    // The agent's way to the light optimizer: the same core, applied as one
    // `setLights` step. Mutation: drop the `editing.history.run` in
    // `EditorSession.optimizeLights`. The level keeps three lamps.
    final session = EditorSession(
      Editing.parse(_litRoom, path: 'nowhere.json'),
    );
    final optimize = editorTools.firstWhere(
      (EditorTool it) => it.name == 'optimizeLights',
    );
    final answer = await optimize.run(session, <String, Object?>{
      'views': <Object?>[
        <String, Object?>{
          'from': <double>[1.5, 1.6, 1.5],
          'at': <double>[-1.0, 0.5, -1.0],
        },
      ],
    });
    expect(answer.did, isTrue, reason: answer.says);
    expect(answer.says, startsWith('3 → 1 lights'));
    expect(answer.png, isNotNull);
    expect(session.editing.level.lights, hasLength(1));

    expect(session.undo().did, isTrue);
    expect(session.editing.level.lights, hasLength(3));
  });
}

/// A closed grey box of a room with three lamps hanging in one place.
final String _litRoom = () {
  String box(List<double> at, List<double> size) =>
      '{"at": $at, "size": $size, "material": "stone"}';
  const lamp =
      '{"type": "point", "at": [0.0, 2.2, 0.0], "intensity": 2.0, '
      '"range": 8.0}';
  return '''
{
  "version": 1,
  "materials": {"stone": {"baseColor": [0.6, 0.6, 0.6, 1.0]}},
  "brushes": [
    ${box(<double>[0.0, -0.25, 0.0], <double>[5.0, 0.5, 5.0])},
    ${box(<double>[0.0, 2.75, 0.0], <double>[5.0, 0.5, 5.0])},
    ${box(<double>[-2.25, 1.25, 0.0], <double>[0.5, 2.5, 4.0])},
    ${box(<double>[2.25, 1.25, 0.0], <double>[0.5, 2.5, 4.0])},
    ${box(<double>[0.0, 1.25, -2.25], <double>[4.0, 2.5, 0.5])},
    ${box(<double>[0.0, 1.25, 2.25], <double>[4.0, 2.5, 0.5])}
  ],
  "lights": [$lamp, $lamp, $lamp]
}
''';
}();

/// The smallest document `Level.fromJson` accepts: one brush, one material.
const String _bareLevel = '''
{
  "version": 1,
  "materials": {"stone": {"baseColor": [0.5, 0.5, 0.5, 1.0]}},
  "brushes": [{"at": [0.0, 0.0, 0.0], "size": [1.0, 1.0, 1.0], "material": "stone"}]
}
''';

/// [_bareLevel] with a light, and the materials a room recipe uses when its
/// params do not name any, so what `validate` has left to say is about the
/// recipe.
const String _litLevel = '''
{
  "version": 1,
  "materials": {
    "stone": {"baseColor": [0.5, 0.5, 0.5, 1.0]},
    "floor": {"baseColor": [0.5, 0.5, 0.5, 1.0]},
    "wall": {"baseColor": [0.5, 0.5, 0.5, 1.0]},
    "ceiling": {"baseColor": [0.5, 0.5, 0.5, 1.0]}
  },
  "brushes": [{"at": [0.0, 0.0, 0.0], "size": [1.0, 1.0, 1.0], "material": "stone"}],
  "lights": [{"type": "point", "at": [20.0, 2.0, 0.0], "intensity": 4.0, "range": 8.0}]
}
''';

/// [_litLevel] with a monster that runs a behaviour called guard.
const String _guardedLevel = '''
{
  "version": 1,
  "materials": {"stone": {"baseColor": [0.5, 0.5, 0.5, 1.0]}},
  "brushes": [{"at": [0.0, -0.5, 0.0], "size": [10.0, 1.0, 10.0], "material": "stone"}],
  "lights": [{"type": "point", "at": [0.0, 2.0, 0.0], "intensity": 4.0, "range": 8.0}],
  "entities": [{"type": "monster", "at": [1.0, 0.0, 1.0], "behaviour": "guard"}]
}
''';
