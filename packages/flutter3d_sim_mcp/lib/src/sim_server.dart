import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'sim_session.dart';
import 'sim_tools.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved on, since "kept beside the pubspec's" was a
/// comment and nothing checked it; `server_version_test.dart` does now.
const String simMcpVersion = '0.7.0';

/// A level of whatever game [SimSession.game] is, offered to an agent as a
/// table of tools — `ai-00`.
///
/// **One level, one process, no window** — the same shape every server here
/// settled on, and the same [ToolTableServer] underneath. The tools and the
/// instructions are built from the game the session was given, so the words an
/// agent reads name that game's own buttons rather than one genre's.
base class SimMcpServer extends ToolTableServer<SimSession, PictureAnswer> {
  SimMcpServer(super.channel, {required super.session})
    : super(
        name: 'flutter3d_sim_mcp',
        version: simMcpVersion,
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
in pixels. `snapshot` is the tool worth calling most: it says the player's
position and health, and the same for every actor the level spawned. `frame`
draws an actual picture when that is worth the time; most of the time it is
not.

`digest` and `writeRun` are for handing a run to something else: `digest` is
what `net-04`'s divergence check compares, and `writeRun` writes a `.f3drun`
that `apps/flutter3d_editor`'s timeline opens like any other recorded run.

Work in this order: `open` a level, `step` it forward in the direction you
mean, `snapshot` to see what happened, and repeat. `writeRun` once, at the end,
if the run is worth keeping.
''';
