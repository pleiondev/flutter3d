import 'package:dart_mcp/server.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'sim_session.dart';

/// One tool: what an agent is offered, and what calling it does — see
/// `flutter3d_mcp_kit`'s [OfferedTool].
typedef SimTool = OfferedTool<SimSession, PictureAnswer>;

double _number(
  Map<String, Object?> args,
  String key, [
  double fallback = 0.0,
]) => (args[key] as num?)?.toDouble() ?? fallback;

/// The arguments `step` and `expect` share: one intent, held for every step.
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

/// The six verbs `ai-00` asks for, with `step` offering [game]'s own buttons
/// as its own arguments — `fire` for the shooter, whatever another game names —
/// and the two that turn a claim about a run into a file that proves it.
List<SimTool> simToolsFor(HeadlessGame game) => <SimTool>[
  SimTool(
    Tool(
      name: 'open',
      description:
          'Open a ${game.name} level (a .json level document) and stand the '
          'player up at its spawn. Replaces whatever run this process had '
          'going — call writeRun first if it is worth keeping.',
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
    Tool(
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
  SimTool(
    Tool(
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
    Tool(
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
    Tool(
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
    Tool(
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
    Tool(
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
    Tool(
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
