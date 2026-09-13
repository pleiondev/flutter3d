import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'sim_session.dart';

/// One tool: what an agent is offered, and what calling it does — the same
/// pair-not-a-table shape `flutter3d_editor_mcp`'s own `EditorTool` is, and
/// the same reason: a tool `tools/list` offers and a tool `tools/call` can
/// actually run are one object, so neither can name one the other forgot.
final class SimTool {
  const SimTool(this.tool, this.run);

  final Tool tool;
  final FutureOr<Answer> Function(SimSession session, Map<String, Object?> arguments)
  run;

  String get name => tool.name;
}

double _number(Map<String, Object?> args, String key, [double fallback = 0.0]) =>
    (args[key] as num?)?.toDouble() ?? fallback;

/// The six verbs `ai-00` asks for.
List<SimTool> get simTools => <SimTool>[
  SimTool(
    Tool(
      name: 'open',
      description:
          'Open a shooter level (a .json level document, e.g. a crypt) and '
          'stand the player up at its spawn. Replaces whatever run this '
          'process had going — call writeRun first if it is worth keeping.',
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
          'that mouse motion would. fire is held down for the whole call when '
          'true.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'steps': IntegerSchema(description: 'how many fixed steps, at least 1'),
          'moveX': NumberSchema(description: 'strafe, -1..1, default 0'),
          'moveY': NumberSchema(description: 'forward/back, -1..1, default 0'),
          'lookX': NumberSchema(description: 'look delta per step, default 0'),
          'lookY': NumberSchema(description: 'look delta per step, default 0'),
          'fire': BooleanSchema(description: 'held for the whole call, default false'),
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
      fire: (args['fire'] as bool?) ?? false,
    ),
  ),
  SimTool(
    Tool(
      name: 'snapshot',
      description:
          'Where things stand right now, in words: the player\'s position, '
          'facing, and health, and the same for every actor the level spawned '
          '(a monster, most often) — position, health, and whether it is still '
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
