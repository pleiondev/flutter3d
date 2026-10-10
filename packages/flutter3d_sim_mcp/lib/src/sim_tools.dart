import 'package:dart_mcp/server.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'mcp_tool.dart';
import 'sim_session.dart';

/// One tool: what an agent is offered, and what calling it does — see
/// `flutter3d_mcp/kit.dart`'s [OfferedTool].
typedef SimTool = OfferedTool<SimSession, PictureAnswer>;

double _number(
  Map<String, Object?> args,
  String key, [

  /// The answer when [key] is absent, in that argument's own units.
  double fallback = 0.0,
]) => (args[key] as num?)?.toDouble() ?? fallback;

/// The arguments `run.step` and `run.expect` share: one intent, held for every step.
Map<String, Schema> _intentProperties(HeadlessGame game) => <String, Schema>{
  'moveX': NumberSchema(description: 'strafe, -1..1, default 0'),
  'moveY': NumberSchema(description: 'forward/back, -1..1, default 0'),
  'lookX': NumberSchema(description: 'look delta per step, default 0'),
  'lookY': NumberSchema(description: 'look delta per step, default 0'),
  for (final String button in game.buttons.keys)
    button: BooleanSchema(
      description: 'held for the whole call, default false',
    ),
};

Map<String, bool> _held(HeadlessGame game, Map<String, Object?> args) =>
    <String, bool>{
      for (final String button in game.buttons.keys)
        if (args[button] case final bool down) button: down,
    };

/// What a claim looks like to an agent — `ReadingPredicate.fromJson`'s shape.
Schema _predicateSchema(String description) => ObjectSchema(
  description: description,
  properties: <String, Schema>{
    'kind': UntitledSingleSelectEnumSchema(
      values: <String>['near', 'inside', 'alive', 'health'],
      description:
          'near: within `within` metres of `point`; inside: inside the box '
          '`min`..`max`; alive: up when `is` is true (the default), down when '
          'false; health: under `below` and/or at least `atLeast`',
    ),
    'who': StringSchema(
      description:
          '"player" (the default) or an actor\'s name as snapshot gives it',
    ),
    'point': ListSchema(items: NumberSchema(), description: 'x, y, z'),
    'within': NumberSchema(description: 'metres, for near'),
    'min': ListSchema(items: NumberSchema(), description: 'x, y, z'),
    'max': ListSchema(items: NumberSchema(), description: 'x, y, z'),
    'is': BooleanSchema(description: 'for alive, default true'),
    'below': NumberSchema(description: 'for health'),
    'atLeast': NumberSchema(description: 'for health'),
  },
  required: <String>['kind'],
);

/// The [EntityLayout] a `run.bisect` call's `entities` names: null for none, and
/// a refusal for one that names both shapes or neither, since guessing which
/// was meant would answer about entities the save does not have.
({EntityLayout? layout, String? refused}) _entityLayout(Object? spec) =>
    switch (spec) {
      null => (layout: null, refused: null),
      {'ecs': final List<Object?> at} when !spec.containsKey('rows') => (
        layout: EntityLayout.ecs(<String>[for (final key in at) '$key']),
        refused: null,
      ),
      {'rows': final String key} when !spec.containsKey('ecs') => (
        layout: EntityLayout.rows(key),
        refused: null,
      ),
      _ => (
        layout: null,
        refused: 'entities is {"ecs": [keys]} or {"rows": key}, one of the two',
      ),
    };

/// `game.order`, offered only to a game played by orders: one verb of [game]'s,
/// its numbers, and how many steps to run after giving it.
///
/// Every argument any verb reads is offered as a number; the session refuses
/// one the named verb does not read.
SimTool _orderTool(OrderedGame game) => SimTool(
  mcpTool(
    name: 'order',
    description:
        'Give the ${game.name} an order, then step it forward with the stick '
        'at rest. The order is written on the run\'s tape with the step that '
        'takes it, so run.write, verify and bisect replay it. The orders: '
        '${<String>[for (final MapEntry(:key, :value) in game.orders.entries) '$key — ${value.description}'].join(' ')}',
    inputSchema: ObjectSchema(
      properties: <String, Schema>{
        'verb': UntitledSingleSelectEnumSchema(
          values: game.orders.keys.toList(),
          description: 'which order',
        ),
        'steps': IntegerSchema(
          description: 'how many fixed steps to run after it, default 1',
        ),
        for (final MapEntry(:key, :value) in <String, String>{
          for (final verb in game.orders.entries)
            for (final argument in verb.value.arguments.entries)
              argument.key: '${verb.key}: ${argument.value}',
        }.entries)
          key: NumberSchema(description: value),
      },
      required: <String>['verb'],
    ),
  ),
  (session, args) => session.order(
    verb: args['verb']! as String,
    steps: (args['steps'] as num?)?.toInt() ?? 1,
    arguments: <String, Object?>{
      for (final MapEntry(:key, :value) in args.entries)
        if (key != 'verb' && key != 'steps') key: value,
    },
  ),
);

/// The six verbs `ai-00` asks for, with `run.step` offering [game]'s own buttons
/// as its own arguments — `fire` for the shooter, whatever another game names —
/// and the two that turn a claim about a run into a file that proves it.
List<SimTool> simToolsFor(HeadlessGame game) => <SimTool>[
  SimTool(
    mcpTool(
      name: 'open',
      description:
          'Open a ${game.name} level (a .json level document) and stand the '
          'player up at its spawn. Replaces whatever run this process had '
          'going — call run.write first if it is worth keeping.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(description: 'a level document on disk'),
        },
        required: <String>['path'],
      ),
    ),
    (session, args) => session.open(args['path']! as String),
  ),
  SimTool(
    mcpTool(
      name: 'step',
      description:
          'Run the level forward, holding one intent for every step. moveX/moveY '
          'is a stick (forward/back, strafe); lookX/lookY is a look delta, added '
          'once per step — asking for ten steps with a look of 0.02 turns ten '
          'times as far as asking for one does, the same as ten real frames of '
          'that mouse motion would.'
          '${game.buttons.isEmpty ? '' : ' ${game.buttons.keys.join(', ')}: held down for the whole call when true.'}',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'steps': IntegerSchema(
            description: 'how many fixed steps, at least 1',
          ),
          ..._intentProperties(game),
        },
        required: <String>['steps'],
      ),
    ),
    (session, args) => session.step(
      steps: (args['steps']! as num).toInt(),
      moveX: _number(args, 'moveX'),
      moveY: _number(args, 'moveY'),
      lookX: _number(args, 'lookX'),
      lookY: _number(args, 'lookY'),
      held: _held(game, args),
    ),
  ),
  if (game case final OrderedGame ordered) _orderTool(ordered),
  SimTool(
    mcpTool(
      name: 'expect',
      description:
          'Back a claim with a replay: step forward holding one intent (the '
          'same arguments as step) until the predicate holds or `limit` steps '
          'pass, then write the whole run so far to `path` as a .f3drun. '
          'Answers with the step the claim held at and the state digest '
          'there; verify on the file replays to the same step and digest. '
          'A claim is about what snapshot reads — near a point, inside a '
          'box, alive or dead, health above or below — and not about what '
          'touched what: contacts and hits are game events, events are not '
          'saved in a run, and a replay cannot back a claim about them.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'predicate': _predicateSchema('the claim to step until'),
          'limit': IntegerSchema(
            description: 'the most steps to try, at least 1',
          ),
          'path': StringSchema(description: 'where to write the .f3drun'),
          ..._intentProperties(game),
        },
        required: <String>['predicate', 'limit', 'path'],
      ),
    ),
    (session, args) => session.expect(
      predicate: (args['predicate']! as Map).cast<String, Object?>(),
      limit: (args['limit']! as num).toInt(),
      path: args['path']! as String,
      moveX: _number(args, 'moveX'),
      moveY: _number(args, 'moveY'),
      lookX: _number(args, 'lookX'),
      lookY: _number(args, 'lookY'),
      held: _held(game, args),
    ),
  ),
  SimTool(
    mcpTool(
      name: 'verify',
      description:
          'Replay a .f3drun into a fresh run of its own level, apart from the '
          'run this session has open, and say whether it retraces the digest '
          'checkpoints it was written with — or the first checkpoint where it '
          'does not. Given a predicate, also says whether that claim holds '
          'where the replay ends. Contacts are out of reach here too: events '
          'are not in the file.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(description: 'the .f3drun to replay'),
          'predicate': _predicateSchema(
            'optional: a claim to check at the end of the replay',
          ),
        },
        required: <String>['path'],
      ),
    ),
    (session, args) => session.verify(
      args['path']! as String,
      predicate: (args['predicate'] as Map?)?.cast<String, Object?>(),
    ),
  ),
  SimTool(
    mcpTool(
      name: 'bisect',
      description:
          'Play two .f3drun files of the same level side by side, each in a '
          'fresh world of its own, and say the first step at which they '
          'differ and the first field that does, as a path into the state '
          '(players.0.health). Every step is compared, not only the '
          'checkpoints. Two runs on different physics or in different '
          'versions of the level are refused.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'a': StringSchema(description: 'one .f3drun'),
          'b': StringSchema(description: 'the other'),
          'entities': ObjectSchema(
            description:
                'where the save keeps its entities, to name the entity and '
                'component the runs part on: {"ecs": ["entities"]} for an '
                'entity world saved under that key ([] for the save itself), '
                'or {"rows": "actors"} for one row per entity; leave out '
                'for the server\'s own',
            properties: <String, Schema>{
              'ecs': ListSchema(items: StringSchema()),
              'rows': StringSchema(),
            },
          ),
        },
        required: <String>['a', 'b'],
      ),
    ),
    (session, args) => switch (_entityLayout(args['entities'])) {
      (layout: final layout, refused: null) => session.bisect(
        args['a']! as String,
        args['b']! as String,
        layout: layout,
      ),
      (layout: _, refused: final String why) => (
        did: false,
        says: why,
        png: null,
      ),
    },
  ),
  SimTool(
    mcpTool(
      name: 'snapshot',
      description:
          'Where things stand right now, as JSON: the step, and what the game '
          'reads out — for the player, position, facing and health; for every '
          'actor the level spawned, position, health, and whether it is still '
          'up. Call this rather than guessing from how many steps you asked for.',
      inputSchema: ObjectSchema(),
    ),
    (session, args) => session.snapshot(),
  ),
  SimTool(
    mcpTool(
      name: 'digest',
      description:
          'The most recent checkpoint digest and the step it was taken at — '
          'one every 25 steps. Two runs of the same level and the same input '
          'that answer with the same digest at the same step took the same '
          'run, bit for bit; this is what `net-04`\'s divergence check '
          'compares.',
      inputSchema: ObjectSchema(),
    ),
    (session, args) => session.digest(),
  ),
  SimTool(
    mcpTool(
      name: 'writeRun',
      description:
          'Write everything stepped so far as a .f3drun — the level, its '
          'hash, the starting snapshot, every step\'s input, and the digest '
          'trace. Opens in `apps/flutter3d_editor`\'s timeline the same way '
          'a person\'s own recorded run would.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(description: 'where to write the .f3drun'),
        },
        required: <String>['path'],
      ),
    ),
    (session, args) => session.writeRun(args['path']! as String),
  ),
  SimTool(
    mcpTool(
      name: 'frame',
      description:
          'A picture of the room, from the player\'s own eye, rendered with '
          'no GPU. Slower than the other tools and rarely needed step by '
          'step — snapshot already says where everything is; call this when '
          'seeing the room actually matters.',
      inputSchema: ObjectSchema(),
    ),
    (session, args) => session.frame(),
  ),
];
