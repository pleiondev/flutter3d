import 'dart:async';

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart' show Answer;

/// Makes a run of [projectRoot] on [device]. A parameter of [PlaySession] so
/// a test hands it a run over a tool of its own making.
typedef NewRun = FlutterRun Function(String projectRoot, String? device);

FlutterRun _newRun(String projectRoot, String? device) =>
    FlutterRun(projectRoot: projectRoot, device: device);

/// `HR5` for an agent: the game the open level belongs to, run, reloaded,
/// stopped and sent the level when it is saved — the editor application's
/// Play, through the same [FlutterRun].
///
/// **One run per process**, as there is one document: the level belongs to
/// one project, and a second run of it would be a second window of the same
/// game that nothing here could tell apart from the first.
final class PlaySession {
  PlaySession({
    required this.levelPath,
    this.projectRootOf = projectRootOnDisk,
    this.newRun = _newRun,
    this.devices = flutterDevices,
    this.push = pushLevel,
    this.waitFor = const Duration(minutes: 3),
  });

  /// The level being edited; its project is what [start] runs.
  final String levelPath;

  final String? Function(String levelPath) projectRootOf;
  final NewRun newRun;
  final Future<List<FlutterDevice>> Function() devices;
  final Future<Map<String, Object?>> Function(String vmService, String level)
  push;

  /// How long [start] waits for the game to be up before answering that it
  /// is still starting. A first build of a desktop game takes a minute.
  final Duration waitFor;

  FlutterRun? _run;

  /// Runs the project, on [device] or the tool's own choice, and waits until
  /// it is up, has failed, or [waitFor] has passed.
  Future<Answer> start({String? device}) async {
    final root = projectRootOf(levelPath);
    if (root == null) {
      return (
        did: false,
        says:
            '$levelPath is not inside a Flutter project, so there is nothing '
            'to run',
      );
    }
    final running = _run;
    if (running != null && _going(running.state.value)) {
      if (device == null || device == running.device) {
        return (did: true, says: 'already ${_describe(running)}');
      }
      return (
        did: false,
        says:
            'the game is running on ${running.device ?? 'the default device'}; '
            'call play_stop first to run it on $device',
      );
    }
    unawaited(running?.dispose());
    final run = _run = newRun(root, device);
    await run.start();
    await _settled(run);
    return (
      did: run.state.value is! PlayStopped,
      says: '${_describe(run)}\n${_tail(run, 12)}'.trim(),
    );
  }

  /// Where the run is and the last [lines] of its console.
  String status({int lines = 40}) {
    final run = _run;
    if (run == null) return 'not running; call play to start the game';
    return '${_describe(run)}\n${_tail(run, lines)}'.trim();
  }

  /// A hot reload, or a hot restart when [restart], and what the tool said.
  Future<Answer> swap({bool restart = false}) async {
    final run = _run;
    if (run == null || run.state.value is! PlayRunning) {
      return (did: false, says: 'nothing is running; call play first');
    }
    try {
      final said = restart ? await run.hotRestart() : await run.hotSwap();
      final what = restart ? 'hot restart' : 'hot swap';
      return (
        did: true,
        says: said == null || said.isEmpty ? '$what done' : '$what: $said',
      );
    } on StateError catch (error) {
      return (did: false, says: error.message);
    }
  }

  /// Stops the game.
  Future<Answer> stop() async {
    final run = _run;
    if (run == null || !_going(run.state.value)) {
      return (did: false, says: 'nothing is running');
    }
    await run.stop();
    return (did: true, says: 'asked the game to stop');
  }

  /// What `play` can be pointed at, one line each, with the id it takes.
  Future<Answer> listDevices() async {
    try {
      final found = await devices();
      if (found.isEmpty) return (did: true, says: 'no devices');
      return (did: true, says: found.map((it) => '$it').join('\n'));
    } on Object catch (error) {
      return (did: false, says: '$error');
    }
  }

  /// Sends [document], just saved, to the game when it is running, and says
  /// what the game did with it; null when nothing is running to send it to.
  Future<String?> sendSaved(String document) async {
    if (_run?.state.value case PlayRunning(:final vmService)) {
      try {
        return describeLevelApplied(await push(vmService, document));
      } on Object catch (error) {
        return 'the running game did not take it: $error';
      }
    }
    return null;
  }

  Future<void> dispose() async => _run?.dispose();

  Future<void> _settled(FlutterRun run) async {
    if (_settledState(run.state.value)) return;
    try {
      await run.state.changes.firstWhere(_settledState).timeout(waitFor);
    } on TimeoutException {
      // Still starting; the answer says so and `play_status` follows it.
    } on StateError {
      // The run closed its state before it settled.
    }
  }

  static bool _settledState(PlayState state) =>
      state is PlayRunning || state is PlayStopped;

  static bool _going(PlayState state) =>
      state is PlayStarting || state is PlayRunning;

  static String _describe(FlutterRun run) => switch (run.state.value) {
    PlayIdle() => 'not started',
    PlayStarting(:final message) => 'still starting: $message',
    PlayRunning(:final vmService) =>
      'running ${run.projectRoot} on ${run.device ?? 'the default device'}, '
          'VM service $vmService',
    PlayStopped(:final exitCode) => 'stopped (exit code $exitCode)',
  };

  static String _tail(FlutterRun run, int lines) {
    final console = run.console.value;
    return console
        .skip(console.length > lines ? console.length - lines : 0)
        .join('\n');
  }
}
