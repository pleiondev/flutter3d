/// What this server offers, held against the list of commands that exists.
///
/// **The drift this file exists to stop has a shape.** `editorCommandNames`
/// lives beside the sealed hierarchy it describes, and its own doc says why: a
/// server keeping its own copy is a server that silently cannot call the
/// eleventh command, with nothing to say so until somebody asks for it. That is
/// exactly this package — so the copy is checked, both ways round, rather than
/// trusted.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show expandRecipes;
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
