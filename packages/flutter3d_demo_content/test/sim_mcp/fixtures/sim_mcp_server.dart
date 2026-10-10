/// A live `flutter3d_sim_mcp` server, reachable over a socket rather than
/// over stdio — see `pubspec.yaml`'s own doc for why literal stdio does not
/// survive being hosted inside `flutter test`.
///
///     flutter test --reporter=silent test/sim_mcp/fixtures/sim_mcp_server.dart
///
/// **Not named `*_test.dart` on purpose**, the same reason
/// `flutter3d_game/test/fixtures/timeline_target.dart` gives for itself:
/// `flutter test` run over the whole package should never pick this up on
/// its own, since alone it does nothing but wait for a client that never
/// connects. `test/sim_mcp/sim_mcp_test.dart` is what starts it, named explicitly,
/// and kills it when done.
///
/// **Any of the four genres**, picked by `F3D_SIM_GAME` in the environment:
/// `shooter` (the default, which the suite plays), `platformer`, `racing`
/// (with `F3D_SIM_TRACK` naming a track document, since a racing level alone
/// carries no circuit) or `strategy`. The game is the one the genre's own
/// plugin hands a tool, and the plugin is installed into an engine whose
/// `McpTools` the server takes as `projectTools` — the composition a game
/// that runs this server makes, so a plugin's own tools are offered beside
/// the simulation's.
///
/// `--reporter=silent` is required, not a preference: any other reporter
/// writes its own lines to the same `stdout` a client would otherwise be
/// tempted to read the port announcement from, and this file's one
/// diagnostic print already goes through `flutter test`'s "Shell: " prefix
/// — a second, competing writer would make that line harder to find, not
/// easier.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_demo_content/shooter_staging.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart'
    show PlatformerPlugin;
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart'
    show RacingHeadlessGame, RacingPlugin, TrackDocument;
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart'
    show ShooterPlugin;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart'
    show StrategyPlugin;
import 'package:flutter3d_mcp/kit.dart' show McpTools, ProjectRoot;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/src/sim_server.dart';
import 'package:flutter3d_sim_mcp/src/sim_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The genre [name] names, as its plugin, with the game it hands a tool.
({Flutter3dPlugin plugin, HeadlessGame game}) _genre(String name) {
  // Every genre is asked the same question; a genre handed no blind game
  // has none to give.
  ({Flutter3dPlugin plugin, HeadlessGame game}) blind(GenrePlugin plugin) => (
    plugin: plugin,
    game:
        plugin.headless ??
        (throw StateError('$name was given no headless game')),
  );
  switch (name) {
    case 'shooter':
      // The crypt names a `widget_surface` entity (`wg-02`) the shooter's own
      // vocabulary does not know without this.
      const game = ShooterHeadlessGame(
        extra: <EntityKind>[WidgetSurfaceKind()],
      );
      return blind(ShooterPlugin(headless: game));
    case 'platformer':
      return blind(PlatformerPlugin());
    case 'racing':
      final track = Platform.environment['F3D_SIM_TRACK'];
      if (track == null) {
        throw StateError('racing needs F3D_SIM_TRACK, a track document');
      }
      final document = TrackDocument.fromJson(
        (jsonDecode(File(track).readAsStringSync()) as Map)
            .cast<String, Object?>(),
      );
      final game = RacingHeadlessGame(track: document.track);
      return blind(RacingPlugin(headless: game));
    case 'strategy':
      return blind(StrategyPlugin());
    default:
      throw StateError(
        'F3D_SIM_GAME is shooter, platformer, racing or strategy, not "$name"',
      );
  }
}

void main() {
  test('a live flutter3d_sim_mcp server, reachable over a socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // Read by `test/sim_mcp/sim_mcp_test.dart` off this process's own stdout, the
    // same way `run_timeline_extensions_test.dart` reads a VM service URI
    // off `flutter test -v`'s.
    // ignore: avoid_print
    print('flutter3d_sim_mcp listening on ${server.port}');

    final genre = _genre(Platform.environment['F3D_SIM_GAME'] ?? 'shooter');
    // The project's tools, filled by whatever the installed plugins bring.
    final tools = McpTools();
    EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[tools],
      plugins: <Flutter3dPlugin>[genre.plugin],
    );

    server.listen((socket) {
      SimMcpServer(
        stdioChannel(input: socket, output: socket),
        // The host decides what is played; this suite plays the crypt. Its
        // root is the repository, which holds the crypt (in an app beside
        // this package) and the runs the suite writes (in this package's
        // `.dart_tool`).
        session: SimSession(game: genre.game, root: ProjectRoot('../..')),
        projectTools: tools,
      );
    });

    // Long enough for a client to connect, open a level, step it and hang
    // up; the test that started this process kills it well before this
    // runs out rather than waiting for it.
    await Future<void>.delayed(const Duration(seconds: 60));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
