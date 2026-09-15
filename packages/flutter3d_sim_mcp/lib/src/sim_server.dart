import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'diagnostic_tools.dart';
import 'sim_session.dart';
import 'sim_tools.dart';

/// The version this server tells a client it is. Kept beside the pubspec's.
const String simMcpVersion = '0.1.0';

/// A level of whatever game [SimSession.game] is, offered to an agent as a
/// table of tools — `ai-00`, and, since the package-merge plan folded
/// `flutter3d_render_mcp` into this one, `par-02` beside it.
///
/// **One level, one process, no window** — the same shape every server here
/// settled on, and the same [ToolTableServer] underneath. The tools and the
/// instructions are built from the game the session was given, so the words an
/// agent reads name that game's own buttons rather than one genre's.
///
/// **Two agents' worth of tools rather than two processes.** An agent that
/// plays a level blind and then wants to know why a frame drew wrong used to
/// need a second stdio server for the second half of that sentence; both
/// questions now answer to the same connection. [SimSession.diagnostic]
/// holds the second half's state, kept apart from the first rather than
/// combined with it — see that field's own doc for why.
base class SimMcpServer extends ToolTableServer<SimSession, PictureAnswer> {
  SimMcpServer(super.channel, {required super.session})
    : super(
        name: 'flutter3d_sim_mcp',
        version: simMcpVersion,
        instructions: _instructionsFor(session.game),
        tools: <OfferedTool<SimSession, PictureAnswer>>[
          ...simToolsFor(session.game),
          ...diagnosticTools,
        ],
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

A second, independent level is open to `diagOpen` at the same time, for a
different question: why a frame drew wrong rather than how a level plays.
`diagFrame` draws it from a chosen eye and direction in one of four debug
views; `diagPixel`, `diagPasses` and `diagScanNaN` all read back the frame
`diagFrame` last drew. This half never touches whatever `open`/`step` has
running, and neither touches it back.
''';
