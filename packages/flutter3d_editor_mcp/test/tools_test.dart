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
