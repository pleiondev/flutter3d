import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show LevelRecipe, levelKits;
import 'package:vector_math/vector_math.dart';

import 'editor_session.dart';

/// One tool: what an agent is offered, and what calling it does to the
/// document — see `flutter3d_mcp_kit`'s [OfferedTool] for why a pair rather
/// than a table and a switch.
///
/// A [PictureAnswer], because one of them draws; every other tool's picture
/// is null, and [_told] is how they say so.
typedef EditorTool = OfferedTool<EditorSession, PictureAnswer>;

/// A tool whose answer is a sentence and nothing to look at.
EditorTool _told(
  Tool tool,
  FutureOr<Answer> Function(EditorSession, Map<String, Object?>) run,
) => EditorTool(tool, (
  EditorSession session,
  Map<String, Object?> arguments,
) async {
  final answer = await run(session, arguments);
  return (did: answer.did, says: answer.says, png: null);
});

/// The point a call's [key] names, or null when it names none. The schema
/// has already held it to three numbers.
Vector3? _point(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! List || value.length != 3) return null;
  final numbers = value.whereType<num>().toList();
  if (numbers.length != 3) return null;
  return Vector3(
    numbers[0].toDouble(),
    numbers[1].toDouble(),
    numbers[2].toDouble(),
  );
}

/// The schema of where a picture is taken from, shared by the two tools
/// that look.
Map<String, Schema> get _cameraProperties => <String, Schema>{
  'from': _vector(
    'where the eye is, in metres; leave both out for a view from inside '
    'the level near one upper corner, looking at its middle',
  ),
  'at': _vector('the point the eye looks at'),
};

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
  _told(
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
  _told(
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
  _told(
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
  _told(
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
  _told(
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
  _told(
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
  _told(
    Tool(
      name: 'delete',
      description:
          'Remove the selection. Every index after it in that list moves down '
          'by one, so call list again before selecting anything else.',
      inputSchema: ObjectSchema(),
    ),
    _command('delete'),
  ),
  _told(
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
  _told(
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
  _told(
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
  _told(
    Tool(
      name: 'setLights',
      description:
          'Replace every light in the level with the ones given, as one '
          'change that one undo takes back. Each light is written the way the '
          'level file spells one: type, at, direction, color, intensity, '
          'range, castsShadow, name. optimizeLights uses this to apply what '
          'it found.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'lights': ListSchema(
            description: 'the whole new set, in order',
            items: ObjectSchema(),
          ),
          'why': StringSchema(
            description: 'what the change is called in the undo history',
          ),
        },
        required: <String>['lights'],
      ),
    ),
    _command('setLights'),
  ),
];

/// The views a call names under `views`, or null when it names none — each
/// an object with `from` and `at`, three numbers each.
List<LightView>? _views(Map<String, Object?> arguments) {
  final rows = arguments['views'];
  if (rows is! List || rows.isEmpty) return null;
  final views = <LightView>[
    for (final row in rows.whereType<Map<Object?, Object?>>())
      if (_point(row.cast<String, Object?>(), 'from') case final Vector3 from)
        if (_point(row.cast<String, Object?>(), 'at') case final Vector3 at)
          (from: from, at: at),
  ];
  return views.isEmpty ? null : views;
}

/// Everything this server offers: the ten commands, the six verbs that are
/// about the session rather than about the document, and the two that look
/// at it — `screenshot` and `report`.
///
/// **The two that are not commands are the two the plan was missing**, and they
/// are missing in the same way. `list` is how a program with no screen finds out
/// what is in the level — every other verb works on "the selection", and a
/// selection is a kind and an index nobody can guess. `validate` is how it finds
/// out whether what it just built is a level at all; without it the first news
/// of a broken document is a diff somebody reads later.
List<EditorTool> get editorTools => <EditorTool>[
  _told(
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
  _told(
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
  _told(
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
  _told(
    Tool(
      name: 'redo',
      description:
          'Put back the change undo took away. Making a new change clears the '
          'way forward, because a new change is a new future.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) => session.redo(),
  ),
  _told(
    Tool(
      name: 'generate',
      description:
          'Add a piece of level built by a seeded kit: a room with doorways '
          'cut in its walls, a corridor, or a scatter of copies of one thing. '
          'The document keeps the recipe — kind, seed and params — and the '
          'level is built from it wherever it is used, so the same seed builds '
          'the same brushes every time; the answer says how many. room reads '
          'size [w, h, d] (required), at, doors [{side, offset, width, '
          'height}], materials {floor, wall, ceiling} and clutter {count, '
          'size, material}. corridor reads from, to, width, height, doors, '
          'materials and clutter. scatter reads at, size, count, spacing, and '
          'an entity row or a brush {size, material} to copy.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'kind': UntitledSingleSelectEnumSchema(
            description: 'which kit builds it',
            values: levelKits.keys.toList(),
          ),
          'seed': IntegerSchema(
            description: 'what its chances are drawn from; default 0',
          ),
          'params': ObjectSchema(description: "the kit's settings"),
        },
        required: <String>['kind'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final seed = arguments['seed'];
      final params = arguments['params'];
      return session.generate(
        LevelRecipe(
          kind: arguments['kind']! as String,
          seed: seed is int ? seed : 0,
          params: params is Map<String, Object?>
              ? params
              : const <String, Object?>{},
        ),
      );
    },
  ),
  _told(
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
  _told(
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
          'A picture of the level as it stands, drawn in software: every '
          'brush in its material\'s colour (no textures), lit by the level\'s '
          'own lights, with a small yellow box at each light and a blue one at '
          'each entity so things that have no shape can still be seen. Take '
          'one before and after a change.',
      inputSchema: ObjectSchema(properties: _cameraProperties),
    ),
    // **It used to be declared and refused**, because every renderer reached a
    // device whose finished frame was a Flutter widget. That stopped being
    // true when the device registry replaced `present`, and the level's scene
    // moved to `LevelScene` in the editor core, so this draws for real.
    (EditorSession session, Map<String, Object?> arguments) =>
        session.screenshot(_point(arguments, 'from'), _point(arguments, 'at')),
  ),
  _told(
    Tool(
      name: 'report',
      description:
          'What the camera sees, one line per brush, light and entity in the '
          'order list prints them: how many pixels of a 320×200 frame it owns '
          '(or whether it is hidden, outside the view or behind the camera), '
          'the box on the screen those pixels fill, how far away it is, and '
          'what covers the part of the screen it would fill — the things that '
          'can be in front of it, each with its share of that part. The way to '
          'find out whether a torch can be seen from where a player stands, '
          'and which wall is in the way when it cannot.',
      inputSchema: ObjectSchema(properties: _cameraProperties),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.report(_point(arguments, 'from'), _point(arguments, 'at')),
  ),
  EditorTool(
    Tool(
      name: 'optimizeLights',
      description:
          'Fewer lights that light the level the way it is lit now. Draws '
          'every light alone from the views, then removes the lights others '
          'already cover and merges pairs close enough to be one, retuning '
          'the strengths of the rest, and keeps only changes whose picture '
          'stays within a small difference of the original with almost no '
          'pixel going dark. Applied as one change that undo takes back; '
          'answers with the moves, the numbers (lights, shading cost, '
          'difference, darkened pixels) and a picture of the new lighting.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'views': ListSchema(
            description:
                'where players stand and look, each {from, at}; leave out to '
                'look four ways from every player spawn',
            items: ObjectSchema(
              properties: <String, Schema>{
                'from': _vector('the eye'),
                'at': _vector('the point it looks at'),
              },
              required: <String>['from', 'at'],
            ),
          ),
          'apply': BooleanSchema(
            description: 'false to only say what would change; default true',
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.optimizeLights(
          views: _views(arguments),
          apply: arguments['apply'] != false,
        ),
  ),
];
