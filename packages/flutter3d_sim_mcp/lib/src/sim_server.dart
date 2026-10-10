import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'sim_session.dart';
import 'sim_tools.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved on, since "kept beside the pubspec's" was a
/// comment and nothing checked it; `server_version_test.dart` does now.
const String simMcpVersion = '1.0.0-rc.1';

/// The version of this server's tools — names and input schemas — as the
/// `initialize` result announces it beside [simMcpVersion].
///
/// It moves only when the `flutter3d_sim_mcp` server's half of
/// `api/flutter3d_sim_mcp.mcp` does: a minor for a new tool or optional
/// argument, a major for anything that breaks a caller.
///
/// **1.0.0 with the first stable release** (decided 2026-10-09, task F3 of
/// the architecture review): the minors it counted before were moves within
/// a surface nobody had been promised yet, and a host meeting 1.2.0 at a
/// first release would look for a 1.0 and 1.1 that never shipped.
const String simMcpSchemaVersion = '1.0.0';

/// What each of the simulation's tools is published as, `area.verb`, and
/// what it does to the run. The written name stays an alias until 2.0.
const Map<String, ToolName> simToolNames = <String, ToolName>{
  'bisect': ToolName('run.bisect', ToolHints.reads),
  'digest': ToolName('run.digest', ToolHints.reads),
  'expect': ToolName('run.expect', ToolHints.writes),
  'frame': ToolName('view.frame', ToolHints.reads),
  'open': ToolName('level.open', ToolHints.writes),
  'order': ToolName('game.order', ToolHints.writes),
  'snapshot': ToolName('state.snapshot', ToolHints.reads),
  'step': ToolName('run.step', ToolHints.writes),
  'verify': ToolName('run.verify', ToolHints.reads),
  'writeRun': ToolName('run.write', ToolHints.writes),
};

/// A level of whatever game [SimSession.game] is, offered to an agent as a
/// table of tools — `ai-00`.
///
/// **One level, one process, no window** — the same shape every server here
/// settled on, and the same [ToolTableServer] underneath. The tools and the
/// instructions are built from the game the session was given, so the words an
/// agent reads name that game's own buttons rather than one genre's.
base class SimMcpServer extends ToolTableServer<SimSession, PictureAnswer> {
  SimMcpServer(
    super.channel, {
    required super.session,
    super.projectTools,
    super.onProjectCall,
  }) : super(
         name: 'flutter3d.sim',
         version: simMcpVersion,
         schemaVersion: simMcpSchemaVersion,
         names: simToolNames,
         instructions: _instructionsFor(session.game),
         tools: simToolsFor(session.game),
         toResult: pictureResultOf,
       );
}

/// What the host puts in front of the model before it calls anything.
String _instructionsFor(HeadlessGame game) =>
    '''
A ${game.name} level, played blind — open a level, step it forward with an
intent (move, look${game.buttons.isEmpty ? '' : ', ${game.buttons.keys.join(', ')}'}), and read back where things stand in words rather than
in pixels. `state.snapshot` is the tool worth calling most: it says the player's
position and health, and the same for every actor the level spawned. `view.frame`
draws an actual picture when that is worth the time; most of the time it is
not.

`run.digest` and `run.write` are for handing a run to something else: `run.digest` is
what `net-04`'s divergence check compares, and `run.write` writes a `.f3drun`
that `apps/flutter3d_editor`'s timeline opens like any other recorded run.

`run.expect` and `run.verify` are for a claim somebody else should not have to take on
trust: `run.expect` steps until a predicate over what `state.snapshot` reads holds (near
a point, inside a box, alive, health) and writes the run that got there;
`run.verify` replays such a file in a world of its own and says whether it retraces
its digests. What touched what is not claimable — events are not saved in a
run.

Work in this order: `level.open` a level, `run.step` it forward in the direction you
mean, `state.snapshot` to see what happened, and repeat. `run.write` once, at the end,
if the run is worth keeping.
${switch (game) {
      final OrderedGame ordered => '''

A ${game.name} is played by orders rather than by the stick: `game.order` gives
one (${ordered.orders.keys.join(', ')}) and steps on, and `run.step` with no intent
lets the orders play out. Orders are on the run's tape like any input.
''',
      _ => '',
    }}''';
