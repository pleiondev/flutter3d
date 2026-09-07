import 'package:dart_mcp/server.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

import 'editor_session.dart';

/// One tool: what an agent is offered, and what calling it does.
///
/// **A pair rather than a table and a switch.** The obvious arrangement is a
/// list of [Tool] for `tools/list` and a `switch` on the name in `tools/call`,
/// and the two drift the moment somebody adds one and forgets the other — an
/// offered tool that answers "no tool registered with that name", which nothing
/// notices because both halves compile. Here a tool that is offered is a tool
/// that has a body, because they are the same object.
final class EditorTool {
  const EditorTool(this.tool, this.run);

  /// What `tools/list` hands the agent: a name, a sentence and a schema.
  final Tool tool;

  /// What calling it does to the document.
  final Answer Function(EditorSession session, Map<String, Object?> arguments)
  run;

  String get name => tool.name;
}

/// Three numbers, which is how the document spells every position and size.
ListSchema _vector(String about) => ListSchema(
  description: about,
  items: NumberSchema(),
  minItems: 3,
  maxItems: 3,
);

/// Which of the document's three lists something is in.
///
/// The names are `Piece`'s own, so the word an agent types is the word the
/// listing printed and the word `EditorCommand.fromJson` reads back.
UntitledSingleSelectEnumSchema _pieceKind(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: <String>[for (final piece in Piece.values) piece.name],
    );

/// The [Piece] a word names, or null when it names none.
///
/// The schema already refuses anything else — `registerTool` validates a call
/// against it before this is reached — so what this is really for is the null:
/// `select` with no `kind` at all means "select nothing", which is a thing an
/// agent is allowed to ask for.
Piece? _piece(Object? name) {
  for (final piece in Piece.values) {
    if (piece.name == name) return piece;
  }
  return null;
}

/// Runs the command [name] stands for, built out of the call's own arguments.
///
/// **This is the whole reason the package is small.** `EditorCommand.fromJson`
/// already reads a map with a `command` key into one of ten values — it was
/// written for exactly this caller, and its doc says so — so a tool call is that
/// map with the tool's name written into it. Nothing here re-decides what a
/// vector is, what may be left out, or which commands exist.
///
/// A map it cannot read is refused rather than defaulted, which is that
/// function's rule and worth repeating: a `moveBy` with an unreadable `by` that
/// quietly moved nothing would look exactly like a `moveBy` that ran.
Answer Function(EditorSession, Map<String, Object?>) _command(String name) =>
    (EditorSession session, Map<String, Object?> arguments) {
      final command = EditorCommand.fromJson(<String, Object?>{
        'command': name,
        ...arguments,
      });
      if (command == null) {
        return (
          did: false,
          says:
              '$name cannot be read from those arguments — check the schema '
              'that tools/list gave for it',
        );
      }
      return session.run(command);
    };

/// The ten document commands, one tool each, under the names they already have.
///
/// **Named from [editorCommandNames] and nowhere else.** That list lives beside
/// the sealed hierarchy it describes, and its own doc gives the reason: a server
/// keeping its own copy is a server that silently cannot call the eleventh
/// command, with nothing to say so until somebody asks for it. `test/tools_test.dart`
/// holds this file to that list, both ways round.
List<EditorTool> get _commandTools => <EditorTool>[
  EditorTool(
    Tool(
      name: 'moveBy',
      description:
          'Move the selection by a vector, in metres. Whatever is selected — '
          'a brush, a light or an entity — lands on the quarter-metre grid, so '
          'the document keeps numbers a person can read in a diff.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{'by': _vector('how far, as x, y, z')},
        required: <String>['by'],
      ),
    ),
    _command('moveBy'),
  ),
  EditorTool(
    Tool(
      name: 'resize',
      description:
          'Grow or shrink the selected brush about its own centre, in metres. '
          'Brushes only: a light has no size, and an entity\'s is the game\'s '
          'business. No side goes below a quarter of a metre, which is the '
          'smallest thing that can still be found again.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'by': _vector('how much bigger on each side'),
        },
        required: <String>['by'],
      ),
    ),
    _command('resize'),
  ),
  EditorTool(
    Tool(
      name: 'addBrush',
      description:
          'Put a new box of geometry down and select it. Leave the material '
          'out and the document decides: whatever this level is mostly made '
          'of, because a brush naming a material the level has not declared '
          'draws as grey and reads as a mistake.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'at': _vector('where the centre goes'),
          'size': _vector('how big, defaulting to two metres cubed'),
          'material': StringSchema(
            description: 'a material the level declares; call list to see them',
          ),
        },
        required: <String>['at'],
      ),
    ),
    _command('addBrush'),
  ),
  EditorTool(
    Tool(
      name: 'addLight',
      description:
          'Put a new point light down and select it. A light is a thing the '
          'engine defines rather than a word this game happens to use, which '
          'is why it can be invented here instead of copied.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'at': _vector('where it goes'),
          'intensity': NumberSchema(description: 'how strong, default 4'),
          'range': NumberSchema(description: 'how far it reaches, default 8'),
        },
        required: <String>['at'],
      ),
    ),
    _command('addLight'),
  ),
  EditorTool(
    Tool(
      name: 'place',
      description:
          'Put one of something the level already contains at a point, and '
          'select it. An entity is placed by copying the last one of its type, '
          'with everything it was carrying: this editor has no vocabulary of '
          'its own, so it cannot know what a torch needs in it, and a bare one '
          'with the right type and nothing else may not appear in the game at '
          'all. Call list first to see what words this level uses.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'kind': _pieceKind('which of the three lists to add to'),
          'what': StringSchema(
            description:
                'a material for a brush, a type for an entity, "light" '
                'for a light',
          ),
          'at': _vector('where it goes'),
        },
        required: <String>['kind', 'what', 'at'],
      ),
    ),
    _command('place'),
  ),
  EditorTool(
    Tool(
      name: 'duplicate',
      description:
          'Copy the selection a step to the side and select the copy. Beside '
          'rather than on top, because two things in one place are one thing '
          'as far as anybody can see.',
      inputSchema: ObjectSchema(),
    ),
    _command('duplicate'),
  ),
  EditorTool(
    Tool(
      name: 'delete',
      description:
          'Remove the selection. Every index after it in that list moves down '
          'by one, so call list again before selecting anything else.',
      inputSchema: ObjectSchema(),
    ),
    _command('delete'),
  ),
  EditorTool(
    Tool(
      name: 'setField',
      description:
          'Write one field of the selection, or clear it by leaving the value '
          'out. This is how everything the other tools cannot reach is edited: '
          'a brush\'s material, whether it is solid, whether it casts a '
          'shadow, its layer; a light\'s colour, range and type; any property '
          'an entity carries. A value the level format cannot read is refused '
          'rather than written, because the point of an editor is producing '
          'documents that load.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'key': StringSchema(
            description: 'the field name, as the file spells it',
          ),
          'value': Schema.combined(
            description: 'what to write; leave it out to remove the field',
            anyOf: <Schema>[
              StringSchema(),
              NumberSchema(),
              BooleanSchema(),
              ListSchema(),
              ObjectSchema(),
              NullSchema(),
            ],
          ),
        },
        required: <String>['key'],
      ),
    ),
    _command('setField'),
  ),
  EditorTool(
    Tool(
      name: 'brighten',
      description:
          'Multiply the selected light\'s strength by a factor. A factor and '
          'not an amount, because light is read that way: the step from 1 to 2 '
          'is the step from 8 to 16.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'by': NumberSchema(
            description: 'above 1 makes it stronger, below 1 weaker',
            exclusiveMinimum: 0,
          ),
        },
        required: <String>['by'],
      ),
    ),
    _command('brighten'),
  ),
  EditorTool(
    Tool(
      name: 'turn',
      description:
          'Turn the selected entity about the vertical, in radians. Entities '
          'only: a brush has no facing in this format, and a light points '
          'along a direction rather than a yaw.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'by': NumberSchema(description: 'radians, positive is anticlockwise'),
        },
        required: <String>['by'],
      ),
    ),
    _command('turn'),
  ),
];

/// Everything this server offers: the ten commands, and the six verbs that are
/// about the session rather than about the document.
///
/// **The two that are not commands are the two the plan was missing**, and they
/// are missing in the same way. `list` is how a program with no screen finds out
/// what is in the level — every other verb works on "the selection", and a
/// selection is a kind and an index nobody can guess. `validate` is how it finds
/// out whether what it just built is a level at all; without it the first news
/// of a broken document is a diff somebody reads later.
List<EditorTool> get editorTools => <EditorTool>[
  EditorTool(
    Tool(
      name: 'list',
      description:
          'Everything in the level, one line each: the kind, the index, what '
          'the document calls it, where it is and how big it is. The kind and '
          'the index are exactly what select takes. Call this first, and again '
          'after anything is deleted — the document keeps three plain lists, so '
          'removing one thing renumbers everything after it.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        (did: true, says: session.listing()),
  ),
  EditorTool(
    Tool(
      name: 'select',
      description:
          'Choose what the other tools act on, by the kind and index list '
          'printed. Call it with nothing to select nothing.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'kind': _pieceKind('which list it is in'),
          'index': IntegerSchema(
            description: 'which one in that list, counting from zero',
            minimum: 0,
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final index = arguments['index'];
      return session.select(
        _piece(arguments['kind']),
        index is int ? index : null,
      );
    },
  ),
  ..._commandTools,
  EditorTool(
    Tool(
      name: 'undo',
      description:
          'Put the document back the way it was before the last change, and '
          'say which change that was. Sixty-four steps deep, and a step is a '
          'whole snapshot of the document rather than a reversed command.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) => session.undo(),
  ),
  EditorTool(
    Tool(
      name: 'redo',
      description:
          'Put back the change undo took away. Making a new change clears the '
          'way forward, because a new change is a new future.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) => session.redo(),
  ),
  EditorTool(
    Tool(
      name: 'validate',
      description:
          'What is wrong with the level, as the game would see it: geometry '
          'that overlaps, a brush naming a material nothing declares, a light '
          'that reaches nowhere, two things answering to one name. Everything '
          'the document names is taken as a word this game uses, so nothing '
          'here objects to vocabulary it has never heard of. Worth calling '
          'before saving.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        (did: true, says: session.validate()),
  ),
  EditorTool(
    Tool(
      name: 'save',
      description:
          'Write the document out. With no path it writes back where it came '
          'from — which is refused when the file says it was generated by some '
          'tool, because saving over one loses the work the next run of that '
          'tool would throw away. Give a path and the copy takes ownership of '
          'itself.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(
            description: 'where to write it, or leave it out to write back',
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final path = arguments['path'];
      return session.save(path is String ? path : null);
    },
  ),
  EditorTool(
    Tool(
      name: 'screenshot',
      description:
          'Not available in this process, and offered so that the reason is an '
          'answer rather than a missing tool.',
      inputSchema: ObjectSchema(),
    ),
    // **Declared and refused, which is not the same as absent.** An agent that
    // finds no `screenshot` tool concludes the server is incomplete and tries
    // to get a picture some other way; one that is told why stops asking. The
    // reason is a fact about this repository rather than an unfinished
    // feature: every renderer here reaches `GraphicsDevice`, whose `present`
    // returns a Flutter `Widget`, so a process that can draw a level is a
    // Flutter process — and `dart run` cannot resolve a package that depends
    // on the Flutter SDK, which is what
    // `packages/flutter3d_cpu/tool/dump_fixture.dart` records finding out.
    (EditorSession session, Map<String, Object?> arguments) => (
      did: false,
      says:
          'this server cannot draw. Every backend in flutter3d reaches a '
          'device whose finished frame is a Flutter widget, so rendering a '
          'level needs the Flutter tool to run it — and this process is '
          'started by dart run, which cannot resolve a package that depends on '
          'the Flutter SDK. Open the level in apps/flutter3d_editor to look at '
          'it; validate is what this process can say about it instead.',
    ),
  ),
];
