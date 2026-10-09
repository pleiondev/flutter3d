import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show LevelRecipe, LevelRules, levelKits;
import 'package:vector_math/vector_math.dart';

import 'capture_files.dart';
import 'editor_session.dart';
import 'mcp_tool.dart';
import 'play_session.dart' show buildTargets;

/// One tool: what an agent is offered, and what calling it does to the
/// document — see `flutter3d_mcp/kit.dart`'s [OfferedTool] for why a pair rather
/// than a table and a switch.
///
/// A [PictureAnswer], because one of them draws; every other tool's picture
/// is null, and [_told] is how they say so.
typedef EditorTool = OfferedTool<EditorSession, PictureAnswer>;

/// A tool whose answer is a sentence and nothing to look at.
EditorTool _told(
  ToolSpec tool,
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
/// `selection.set` with no `kind` at all means "select nothing", which is a thing an
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
/// function's rule and worth repeating: a `selection.move` with an unreadable `by` that
/// quietly moved nothing would look exactly like a `selection.move` that ran.
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

/// `P12` for an agent: the frame the running game actually drew, pass by
/// pass and draw by draw, through the `ext.flutter3d.render.*` extensions
/// the game registered — the game started by `play.start`, or any game whose VM
/// service address is given.
List<EditorTool> get _renderTools {
  /// The address to ask: the one given, or the game `play.start` runs.
  String? at(EditorSession session, Map<String, Object?> arguments) =>
      switch (arguments['vmService']) {
        final String given when given.isNotEmpty => given,
        _ => session.play.vmService,
      };
  final vmService = StringSchema(
    description:
        'the game\'s VM service address, ws:// or http://; leave out for '
        'the game play started',
  );
  EditorTool tool(
    String name,
    String verb,
    String description,
    Map<String, Schema> parameters, {
    List<String> required = const <String>[],
  }) => _told(
    mcpTool(
      name: name,
      description: description,
      inputSchema: ObjectSchema(
        properties: <String, Schema>{'vmService': vmService, ...parameters},
        required: required,
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) async {
      final address = at(session, arguments);
      if (address == null) {
        return (
          did: false,
          says: 'no game is running: call play first, or give vmService',
        );
      }
      final answer = await session.play.ask(
        address,
        'ext.flutter3d.render.$verb',
        args: <String, String>{
          for (final MapEntry(:key, :value) in arguments.entries)
            if (key != 'vmService' && value != null) key: '$value',
        },
      );
      return switch (answer) {
        (json: final Map<String, Object?> json, refused: null) => (
          did: true,
          says: const JsonEncoder.withIndent('  ').convert(json),
        ),
        (json: _, refused: final String? why) => (
          did: false,
          says: why ?? 'the game did not answer',
        ),
      };
    },
  );
  final fresh = BooleanSchema(
    description:
        'true for a new capture of the next frame; false to read the one '
        'held',
  );
  final pass = StringSchema(
    description: 'a pass, by its index or name from render_passes',
  );
  return <EditorTool>[
    tool(
      'render_passes',
      'passes',
      'The running game\'s next frame, pass by pass: each pass, what it read '
          'and wrote, how many draws it made, and the frame\'s size. Takes a '
          'new capture, which the other render tools then read.',
      <String, Schema>{'fresh': fresh},
    ),
    tool(
      'render_draws',
      'draws',
      'The draws of the captured frame, a page at a time: index, pass, node '
          'name, material, sizes. render.draw opens one.',
      <String, Schema>{
        'fresh': fresh,
        'pass': pass,
        'offset': IntegerSchema(description: 'the first row; default 0'),
        'limit': IntegerSchema(description: 'how many rows; default 200'),
      },
    ),
    tool(
      'render_draw',
      'draw',
      'One draw of the captured frame: its pipeline state and every value '
          'bound for it.',
      <String, Schema>{
        'index': IntegerSchema(description: 'the draw\'s index'),
      },
      required: <String>['index'],
    ),
    tool(
      'render_pick',
      'pick',
      'Which draws put the pixel at x, y (from the top left) on the screen: '
          'the node the picking pass found there and its draws, in a capture '
          'of that same frame, which the other render tools then read.',
      <String, Schema>{
        'x': IntegerSchema(description: 'pixels from the left'),
        'y': IntegerSchema(description: 'pixels from the top'),
      },
      required: <String>['x', 'y'],
    ),
    tool(
      'render_read_pixel',
      'readPixel',
      'One pixel of one pass\'s output, as stored and as read back.',
      <String, Schema>{
        'pass': pass,
        'x': IntegerSchema(description: 'pixels from the left'),
        'y': IntegerSchema(description: 'pixels from the top'),
        'resource': StringSchema(description: 'which output; the first'),
      },
      required: <String>['pass', 'x', 'y'],
    ),
    tool(
      'render_pass_output',
      'passOutput',
      'A summary of one pass\'s output: its format, size and range.',
      <String, Schema>{
        'pass': pass,
        'resource': StringSchema(description: 'which output; the first'),
      },
      required: <String>['pass'],
    ),
    tool(
      'render_scan_nan',
      'scanNan',
      'Every pass output searched for NaN and infinity, with the first '
          'pixel of each.',
      <String, Schema>{'fresh': fresh},
    ),
    tool(
      'render_stats',
      'stats',
      'What the next frame cost: draws, triangles, passes, targets.',
      <String, Schema>{'fresh': fresh},
    ),
    tool(
      'render_memory',
      'memory',
      'What the running game\'s renderer holds on the device, by category '
          '— textures, buffers, render targets, meshes, shaders and '
          'pipelines — each line with its count and bytes, largest first. '
          'Bytes are what the data needs; a driver may allocate more. Takes '
          'no capture.',
      <String, Schema>{},
    ),
    tool(
      'render_debug_views',
      'debugViews',
      'Every debug view by name, with its kind (material, geometry, '
          'identity, validation) and what it paints: the names '
          'RenderSettings.debugView and SceneNode.debugView take.',
      <String, Schema>{},
    ),
    _told(
      mcpTool(
        name: 'render_capture_save',
        description:
            'The running game\'s captured frame written to a file: every '
            'pass, every draw with its uniforms decoded, and a PNG thumbnail '
            'of every image. Attach it to a bug report; capture.open reads it '
            'back. Reads the capture held, taking one when there is none.',
        inputSchema: ObjectSchema(
          properties: <String, Schema>{
            'vmService': vmService,
            'path': StringSchema(description: 'where to write the .json file'),
            'fresh': fresh,
            'thumbnail': IntegerSchema(
              description: 'the longer side of each thumbnail; default 128',
              minimum: 1,
            ),
            'images': BooleanSchema(
              description: 'true to keep every image whole as well',
            ),
            'floats': BooleanSchema(
              description: 'true to keep float targets\' own values',
            ),
            'notes': StringSchema(
              description: 'what was happening, written into the file',
            ),
          },
          required: <String>['path'],
        ),
      ),
      (EditorSession session, Map<String, Object?> arguments) async {
        final address = at(session, arguments);
        if (address == null) {
          return (
            did: false,
            says: 'no game is running: call play first, or give vmService',
          );
        }
        final path = arguments['path'];
        if (path is! String || path.isEmpty) {
          return (did: false, says: 'path names the file to write');
        }
        final answer = await session.play.ask(
          address,
          'ext.flutter3d.render.capture',
          args: <String, String>{
            for (final MapEntry(:key, :value) in arguments.entries)
              if (key != 'vmService' && key != 'path' && value != null)
                key: '$value',
          },
        );
        return switch (answer) {
          (json: final Map<String, Object?> json, refused: null)
              when json['capture'] is Map<String, Object?> =>
            (
              did: true,
              says:
                  'wrote $path, '
                  '${saveCaptureFile(path, json['capture']! as Map<String, Object?>)}',
            ),
          (json: _, refused: final String? why) => (
            did: false,
            says: why ?? 'the game did not answer with a capture',
          ),
        };
      },
    ),
  ];
}

/// The capture file each session has open — `A5.23`, `capture.open`.
final Expando<OpenCapture> _openCaptures = Expando<OpenCapture>('open capture');

/// Capture files opened in the editor: a frame saved by
/// `render.saveCapture`, or attached to a bug report.
List<EditorTool> get _captureTools => <EditorTool>[
  EditorTool(
    mcpTool(
      name: 'capture_open',
      description:
          'Open a frame capture file (render.saveCapture writes one; a bug '
          'report carries one): its passes, what each drew and what each '
          'image kept, with a picture of the last pass that has one — or of '
          'the pass given. Held for capture.draw.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(description: 'the capture .json file'),
          'pass': StringSchema(
            description: 'a pass by index or name to picture; the last',
          ),
        },
        required: <String>['path'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) async {
      final path = arguments['path'];
      if (path is! String || path.isEmpty) {
        return (did: false, says: 'path names the file to open', png: null);
      }
      final (:open, :why) = openCaptureFile(path);
      if (open == null) return (did: false, says: why!, png: null);
      _openCaptures[session] = open;
      final which = arguments['pass'];
      final pass = which is String ? open.passOf(which) : null;
      if (which is String && pass == null) {
        return (
          did: false,
          says: 'opened $path, but it has no pass "$which"',
          png: null,
        );
      }
      return (
        did: true,
        says: const JsonEncoder.withIndent('  ').convert(open.summary()),
        png: open.picture(pass: pass),
      );
    },
  ),
  _told(
    mcpTool(
      name: 'capture_draw',
      description:
          'One draw of the capture capture.open holds: its pass, mesh, '
          'material, pipeline state and every uniform, decoded by shape.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the draw\'s index', minimum: 0),
        },
        required: <String>['index'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final open = _openCaptures[session];
      if (open == null) {
        return (did: false, says: 'no capture is open: call capture_open');
      }
      final index = arguments['index'];
      final draw = index is int ? open.draw(index) : null;
      if (draw == null) {
        return (
          did: false,
          says:
              'the capture has ${open.capture.draws.length} draws; '
              '$index is not one of them',
        );
      }
      return (
        did: true,
        says: const JsonEncoder.withIndent('  ').convert(draw),
      );
    },
  ),
];

/// `HR5`: the game the level belongs to, run and driven — the editor
/// application's Play toolbar, as tools.
List<EditorTool> get _playTools => <EditorTool>[
  _told(
    mcpTool(
      name: 'play',
      description:
          'Run the game this level belongs to (the Flutter project above the '
          'level file) with flutter run, and wait until it is up or has '
          'failed; answers with where it runs and the last lines it printed. '
          'Once it runs, every save of this level is sent to it and the game '
          'takes it without starting over. Does nothing if it is already '
          'running on that device.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'device': StringSchema(
            description:
                'an id play.devices lists; leave out for the tool\'s own choice',
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final device = arguments['device'];
      return session.play.start(device: device is String ? device : null);
    },
  ),
  _told(
    mcpTool(
      name: 'play_status',
      description:
          'Where the game started by play is — starting, running, stopped — '
          'and the last lines of its console: what the game printed, build '
          'errors, what the last play.swap said.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'lines': IntegerSchema(
            description: 'how many console lines; default 40',
            minimum: 0,
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final lines = arguments['lines'];
      return (
        did: true,
        says: session.play.status(lines: lines is int ? lines : 40),
      );
    },
  ),
  _told(
    mcpTool(
      name: 'play_events',
      description:
          'What the game started by play has posted about itself — a level '
          'loaded, the player died or came back, a pickup taken, the way out '
          'reached — in order, each with its sequence number, kind, time and '
          'data. Pass since the next this answered last time (0 the first '
          'time) and nothing is seen twice or skipped, through a play.stop '
          'and a play as well; kinds keeps only the kinds named. Answers JSON: '
          'events, next, and missed when the game posted more than was kept '
          'before it was asked. A game posts these with flutter3d_game\'s '
          'postToolEvent; what it prints is play.status.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'since': IntegerSchema(
            description:
                'the next from the last play.events; 0 for everything kept',
            minimum: 0,
          ),
          'kinds': ListSchema(
            description:
                'only these kinds, as the game names them: level.loaded, '
                'player.died; leave out for every kind',
            items: StringSchema(),
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final since = arguments['since'];
      final kinds = arguments['kinds'];
      return session.play.events(
        since: since is int ? since : 0,
        kinds: kinds is List ? kinds.whereType<String>().toSet() : null,
      );
    },
  ),
  _told(
    mcpTool(
      // `play.swap` and not the word flutter itself uses for it: CONTRIBUTING
      // keeps that word out of the packages for a weapon's, and `HotSwap` is
      // what the engine calls the same thing on the game's side.
      name: 'play_swap',
      description:
          'Swap the running game\'s code after it changed, the way flutter '
          'run does on r: the game keeps its state and picks up the new code, '
          'shaders and models. With restart, a hot restart from main instead. '
          'Answers with what the tool said, including why it refused.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'restart': BooleanSchema(
            description: 'true for a hot restart; default false',
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.play.swap(restart: arguments['restart'] == true),
  ),
  _told(
    mcpTool(
      name: 'play_send_level',
      description:
          'Send the level as it stands now, unsaved changes included, to the '
          'game started by play, which takes it without starting over; the '
          'file on disk is not written. What save does for the running game, '
          'for trying a change before keeping it, or for putting the level '
          'back after a hot restart. Answers with what the game did with it.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.play.sendLevel(session.editing.write()),
  ),
  _told(
    mcpTool(
      name: 'play_build',
      description:
          'Build the game this level belongs to with flutter build, without '
          'running it: whether its code compiles for a target, and the error '
          'lines when it does not. Refused while play runs the game; stop it '
          'first.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'target': UntitledSingleSelectEnumSchema(
            description: 'what to build; leave out for this computer\'s own',
            values: buildTargets.toList(),
          ),
          'release': BooleanSchema(
            description: 'true for a release build; default debug',
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.play.build(
          target: arguments['target'] as String?,
          release: arguments['release'] == true,
        ),
  ),
  _told(
    mcpTool(
      name: 'play_keep_tape',
      description:
          'Keep the last seconds the running game recorded as a .f3drun in '
          'its project\'s test/tapes/, under a name: the run that just went '
          'wrong, where replay tests and the sim server\'s verify and bisect '
          'read tapes from.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(
            description: 'lowercase letters, digits and underscores',
          ),
        },
        required: <String>['name'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.play.keepTape(arguments['name']! as String),
  ),
  _told(
    mcpTool(
      name: 'play_stop',
      description:
          'Stop the game started by play, and the flutter run with it.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.play.stop(),
  ),
  _told(
    mcpTool(
      name: 'play_devices',
      description:
          'The devices play can run the game on — this computer, a browser, '
          'a phone on the cable — one per line with the id play takes.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.play.listDevices(),
  ),
];

/// The ten document commands, one tool each, under the names they already have.
///
/// **Named from [editorCommandNames] and nowhere else.** That list lives beside
/// the sealed hierarchy it describes, and its own doc gives the reason: a server
/// keeping its own copy is a server that silently cannot call the eleventh
/// command, with nothing to say so until somebody asks for it. `test/tools_test.dart`
/// holds this file to that list, both ways round.
List<EditorTool> get _commandTools => <EditorTool>[
  _told(
    mcpTool(
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
    mcpTool(
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
    mcpTool(
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
    mcpTool(
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
    mcpTool(
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
    mcpTool(
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
    mcpTool(
      name: 'delete',
      description:
          'Remove the selection. Every index after it in that list moves down '
          'by one, so call list again before selecting anything else.',
      inputSchema: ObjectSchema(),
    ),
    _command('delete'),
  ),
  _told(
    mcpTool(
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
    mcpTool(
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
    mcpTool(
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
    mcpTool(
      name: 'setLights',
      description:
          'Replace every light in the level with the ones given, as one '
          'change that one undo takes back. Each light is written the way the '
          'level file spells one: type, at, direction, color, intensity, '
          'range, castsShadow, name. light.optimize uses this to apply what '
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
  ..._prefabTools,
];

/// What a value of an override or a template row may be: anything JSON.
Schema _anyValue(String about) => Schema.combined(
  description: about,
  anyOf: <Schema>[
    StringSchema(),
    NumberSchema(),
    BooleanSchema(),
    ListSchema(),
    ObjectSchema(),
    NullSchema(),
  ],
);

/// The path of an entity inside a prefab, as `prefab.list` prints it.
StringSchema _prefabPath(String about) => StringSchema(description: about);

/// The seven prefab commands, in [editorCommandNames]' order.
List<EditorTool> get _prefabTools => <EditorTool>[
  _told(
    mcpTool(
      name: 'createPrefab',
      description:
          'Turn the selected entities into a prefab — a template placed as '
          'one thing — and put one instance of it where they were. The first '
          'selected is the prefab\'s origin; a selected instance goes in as '
          'a nested prefab. Pick several with select and also: true.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'prefab': StringSchema(description: 'the new prefab\'s id'),
        },
        required: <String>['prefab'],
      ),
    ),
    _command('createPrefab'),
  ),
  _told(
    mcpTool(
      name: 'placePrefab',
      description:
          'Put an instance of one of the level\'s prefabs down and select '
          'it. Its entities are named after it — name/entity — when it has a '
          'name. Call prefabs to see the ids.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'prefab': StringSchema(description: 'which prefab'),
          'at': _vector('where its origin goes'),
          'name': StringSchema(description: 'what to call the instance'),
          'yaw': NumberSchema(description: 'its facing, radians'),
        },
        required: <String>['prefab', 'at'],
      ),
    ),
    _command('placePrefab'),
  ),
  _told(
    mcpTool(
      name: 'setOverride',
      description:
          'Change one key of one entity in the selected prefab instance only. '
          'The path is the entity\'s path in the prefab as prefabs prints it '
          '(top/bulb for the bulb of the nested instance top); a dotted key '
          'reaches one field of an object property (glow.strength). The '
          'instance\'s override beats the prefab\'s, which beats a nested '
          'prefab\'s. A null value takes the key away in this instance.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': _prefabPath('the entity, by its path in the prefab'),
          'key': StringSchema(description: 'the key, dotted for a field'),
          'value': _anyValue('what it says in this instance'),
        },
        required: <String>['path', 'key'],
      ),
    ),
    _command('setOverride'),
  ),
  _told(
    mcpTool(
      name: 'applyOverrides',
      description:
          'Write the selected instance\'s overrides into its prefab, so every '
          'instance gets them, and drop them from this one. Leave path out '
          'for all of them.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': _prefabPath('only the overrides of this entity'),
        },
      ),
    ),
    _command('applyOverrides'),
  ),
  _told(
    mcpTool(
      name: 'revertOverrides',
      description:
          'Drop the selected instance\'s overrides, so it shows its prefab '
          'again: all of them, those of one path, or one key there.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': _prefabPath('only the overrides of this entity'),
          'key': StringSchema(description: 'only this key, with a path'),
        },
      ),
    ),
    _command('revertOverrides'),
  ),
  _told(
    mcpTool(
      name: 'unpackPrefab',
      description:
          'Break the selected instance\'s link: the entities it stands for '
          'become the level\'s own and later edits of the prefab no longer '
          'reach them. One level down — a nested instance stays an instance. '
          'Renumbers the entities after it.',
      inputSchema: ObjectSchema(),
    ),
    _command('unpackPrefab'),
  ),
  _told(
    mcpTool(
      name: 'setPrefabField',
      description:
          'Change one key of one entity in a prefab\'s template — the edit '
          'every instance sees, except those that override that key. A null '
          'value takes the key away. Refused when the prefab would contain '
          'itself.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'prefab': StringSchema(description: 'which prefab'),
          'path': _prefabPath(
            'the entity: its name in the template, or #index',
          ),
          'key': StringSchema(description: 'the key, as the file spells it'),
          'value': _anyValue('what to write; leave it out to remove the key'),
        },
        required: <String>['prefab', 'path', 'key'],
      ),
    ),
    _command('setPrefabField'),
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
/// at it — `view.screenshot` and `view.report`.
///
/// **The two that are not commands are the two the plan was missing**, and they
/// are missing in the same way. `level.list` is how a program with no screen finds out
/// what is in the level — every other verb works on "the selection", and a
/// selection is a kind and an index nobody can guess. `level.validate` is how it finds
/// out whether what it just built is a level at all; without it the first news
/// of a broken document is a diff somebody reads later.
List<EditorTool> get editorTools => <EditorTool>[
  _told(
    mcpTool(
      name: 'command.run',
      description:
          'Run any command the editor knows by its name, with its own '
          'arguments: the built-in ones (moveBy, addBrush, …) and every one '
          'the project\'s plugins added, named `<plugin id>.<name>`.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(
            description:
                'the command\'s name, as the editor lists it: `selection.move`, or '
                '`boats.sink` for the boats plugin\'s sink',
          ),
          'arguments': ObjectSchema(
            description: 'the command\'s own arguments, by name',
          ),
        },
        required: <String>['name'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final name = arguments['name']! as String;
      final given = switch (arguments['arguments']) {
        final Map<Object?, Object?> map => map.cast<String, Object?>(),
        _ => const <String, Object?>{},
      };
      if (!session.pieces.commandNames.contains(name)) {
        return (
          did: false,
          says:
              'no command is called "$name": the editor knows '
              '${session.pieces.commandNames.join(', ')}',
        );
      }
      final command = session.pieces.readCommand(<String, Object?>{
        ...given,
        'command': name,
      });
      if (command == null) {
        return (did: false, says: '$name cannot be read from those arguments');
      }
      return session.run(command);
    },
  ),
  _told(
    mcpTool(
      name: 'prefabs',
      description:
          'The level\'s prefabs: each id, how many instances it has, and every '
          'entity of its template with the path prefab.setOverride and '
          'setPrefabField address it by, nested prefabs included.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        (did: true, says: prefabListing(session.editing.level)),
  ),
  _told(
    mcpTool(
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
    mcpTool(
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
          'also': BooleanSchema(
            description:
                'true adds it to the selection, or takes it out, rather than '
                'replacing what is selected',
          ),
        },
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) {
      final index = arguments['index'];
      return session.select(
        _piece(arguments['kind']),
        index is int ? index : null,
        also: arguments['also'] == true,
      );
    },
  ),
  ..._commandTools,
  _told(
    mcpTool(
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
    mcpTool(
      name: 'redo',
      description:
          'Put back the change undo took away. Making a new change clears the '
          'way forward, because a new change is a new future.',
      inputSchema: ObjectSchema(),
    ),
    (EditorSession session, Map<String, Object?> arguments) => session.redo(),
  ),
  _told(
    mcpTool(
      name: 'generate_level',
      description:
          'Replace the open level with a whole one made from a seed: rooms '
          'laid out by wave function collapse on a grid of cells, corridors '
          'where two rooms face each other through a doorway, a light in '
          'each room, the player in one and the exit in the room farthest '
          'from it — refused unless a body can walk from the start to the '
          'exit. The same seed and rules make the same level; the answer '
          'names the seed that made it, which may be a later one when a seed '
          'makes no level. Undoable. rules: columns, rows (cells; 4 by 3), '
          'cell (16 m), room (10 m), height (4 m), corridor (3 m), density '
          '(0.7, how likely a cell is a room), clutter (boxes per room), '
          'materials {name: row}, perRoom [{entity: row, count}] for what '
          'stands in every room but the first.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'seed': IntegerSchema(description: 'what its chances are drawn from'),
          'rules': ObjectSchema(
            description: 'the level\'s rules; all optional',
          ),
        },
        required: <String>['seed'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.generateLevel(
          LevelRules.fromJson(
            (arguments['rules'] as Map?)?.cast<String, Object?>() ??
                const <String, Object?>{},
          ),
          seed: arguments['seed']! as int,
        ),
  ),
  _told(
    mcpTool(
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
    mcpTool(
      name: 'setBehaviour',
      description:
          'Write a behaviour tree into the level under a name; an entity runs '
          'it by naming it in its behaviour property (selection.setField). The tree is '
          'the document BehaviourTree reads: a node is {kind, ...}, where '
          'kind is a composite — sequence {children}, selector {children}, '
          'utility {options: [{name, weight, considerations, do}], inertia}, '
          'invert {child}, alwaysSucceed {child}, cooldown {seconds, child} — '
          'or a leaf: goToFocus {within}, goTo {key, within} (a point on '
          'the board), wait {seconds}, seesFocus, focusWithin {distance}, '
          'check {key, above, below}, set {key, value}, markFocus {key}, '
          'jump, and whatever the game adds. A utility option scores weight '
          'times its considerations: constant {value}, focusDistance {from, '
          'to}, health {from, to}, blackboard {key, from, to}, since {key, '
          'from, to}. A tree that does not read is refused with every problem '
          'and where it is, and nothing is written. Undoable.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(description: 'what the level calls it'),
          'tree': ObjectSchema(description: 'the root node'),
        },
        required: <String>['name', 'tree'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.setBehavior(
          arguments['name']! as String,
          (arguments['tree']! as Map).cast<String, Object?>(),
        ),
  ),
  _told(
    mcpTool(
      name: 'removeBehaviour',
      description:
          'Take a behaviour tree out of the level. An entity still naming it '
          'is left naming it, and validate says so. Undoable.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(description: 'the tree to take out'),
        },
        required: <String>['name'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.removeBehavior(arguments['name']! as String),
  ),
  _told(
    mcpTool(
      name: 'setCutscene',
      description:
          'Write a cutscene into the level under a name: a cutscene entity '
          'holding the sequence, which a trigger, button or relay whose '
          'target is the name starts. The sequence is {seconds, camera: '
          '{keys: [{t, at, look, fov}], ease}, subtitles: [{from, to, text}], '
          'fade: [{t, value}], signals: [{t, name, data}], actors: [{t, '
          'actor, do, at, clip}]} — times in seconds, at and look three '
          'numbers, fov vertical degrees (45 unless given); do is goTo or '
          'face with at, stand, release, or play with clip. Every part but '
          'seconds may be left out. A sequence that does not read is refused '
          'with every problem and where it is. Undoable.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(description: 'what triggers name it by'),
          'sequence': ObjectSchema(description: 'the cutscene'),
          'at': _vector('where a new cutscene entity stands'),
        },
        required: <String>['name', 'sequence'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.setCutscene(
          arguments['name']! as String,
          (arguments['sequence']! as Map).cast<String, Object?>(),
          _point(arguments, 'at'),
        ),
  ),
  _told(
    mcpTool(
      name: 'removeCutscene',
      description:
          'Take a cutscene out of the level. A trigger that started it is '
          'left naming it, and validate says so. Undoable.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(description: 'the cutscene to take out'),
        },
        required: <String>['name'],
      ),
    ),
    (EditorSession session, Map<String, Object?> arguments) =>
        session.removeCutscene(arguments['name']! as String),
  ),
  _told(
    mcpTool(
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
    mcpTool(
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
  ..._playTools,
  ..._renderTools,
  ..._captureTools,
  EditorTool(
    mcpTool(
      name: 'screenshot',
      description:
          'A picture of the level as it stands, drawn in software: every '
          'brush in its material\'s colour (no textures), lit by the level\'s '
          'own lights, with a small yellow box at each light and a blue one at '
          'each entity so things that have no shape can still be seen. Take '
          'one before and after a change. With debugView, each surface is '
          'drawn as one of its numbers instead: albedo, normal, roughness, '
          'metallic, occlusion, emissive, uv, nonFinite to find NaNs, the '
          'geometry views (tangent, uvChecker, faceOrientation, vertexColor), '
          'objectIdentity and materialIdentity, or the checks albedoRange, '
          'metalBinary and missingTangents.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          ..._cameraProperties,
          'debugView': StringSchema(
            description: 'off unless given: albedo, normal, roughness, ...',
          ),
        },
      ),
    ),
    // **It used to be declared and refused**, because every renderer reached a
    // device whose finished frame was a Flutter widget. That stopped being
    // true when the device registry replaced `present`, and the level's scene
    // moved to `LevelScene` in the editor core, so this draws for real.
    (EditorSession session, Map<String, Object?> arguments) =>
        session.screenshot(
          _point(arguments, 'from'),
          _point(arguments, 'at'),
          debugView: arguments['debugView'] as String?,
        ),
  ),
  _told(
    mcpTool(
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
    mcpTool(
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
