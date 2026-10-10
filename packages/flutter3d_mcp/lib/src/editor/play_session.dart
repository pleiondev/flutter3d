import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_mcp/kit.dart' show Answer;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show Demo, DemoFormatException;

/// Makes a run of [projectRoot] on [device]. A parameter of [PlaySession] so
/// a test hands it a run over a tool of its own making.
typedef NewRun = FlutterRun Function(String projectRoot, String? device);

/// Asks a running game for one of its `ext.flutter3d.*` extensions — see
/// [callGameExtension], which is what a session asks with unless a test
/// hands in its own.
typedef GameAsk =
    Future<({Map<String, Object?>? json, String? refused})> Function(
      String vmService,
      String method, {
      Map<String, String> args,
    });

FlutterRun _newRun(String projectRoot, String? device) =>
    FlutterRun(projectRoot: projectRoot, device: device);

/// Runs `flutter` with [arguments] in [workingDirectory] to the end — what
/// [PlaySession.build] builds with. A parameter so a test answers for the
/// tool.
typedef RunFlutterIn =
    Future<ProcessResult> Function(
      List<String> arguments,
      String workingDirectory,
    );

Future<ProcessResult> _runFlutterIn(
  List<String> arguments,
  String workingDirectory,
) => Process.run(
  'flutter',
  arguments,
  workingDirectory: workingDirectory,
  runInShell: Platform.isWindows,
);

/// What `flutter build` is asked to make, by the word an agent gives it.
const Set<String> buildTargets = <String>{
  'macos',
  'linux',
  'windows',
  'web',
  'apk',
  'appbundle',
  'ios',
};

/// The desktop this process runs on, which is what a build makes unless told
/// otherwise: the target `play` would run on with no device named.
String get _hostTarget => Platform.isMacOS
    ? 'macos'
    : Platform.isWindows
    ? 'windows'
    : 'linux';

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
    this.ask = callGameExtension,
    this.runFlutter = _runFlutterIn,
  });

  /// How the running game is asked for what it registered.
  final GameAsk ask;

  /// How [build] runs `flutter build`.
  final RunFlutterIn runFlutter;

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

  /// The events every run before this one posted, so [events]' cursor goes
  /// on counting through a `play_stop` and a `play` rather than starting
  /// again at 1 under an agent still holding the old run's number.
  int _postedBefore = 0;

  /// Runs the project, on [device] or the tool's own choice, and waits until
  /// it is up, has failed, or [waitFor] has passed.
  Future<Answer> start({String? device}) async {
    // Refused here, before a running game is let go of: on Windows the id
    // is an argument to `cmd.exe` (`isFlutterDeviceId` says why).
    if (device != null && !isFlutterDeviceId(device)) {
      return (
        did: false,
        says:
            '"$device" is not a device id: call play_devices for the ids '
            'flutter run -d takes',
      );
    }
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
    _postedBefore += running?.events.value.lastOrNull?.sequence ?? 0;
    unawaited(running?.dispose());
    final run = _run = newRun(root, device);
    await run.start();
    await _settled(run);
    return (
      did: run.state.value is! PlayStopped,
      says: '${_describe(run)}\n${_tail(run, 12)}'.trim(),
    );
  }

  /// Builds the project for [target] (this computer's desktop when null),
  /// debug unless [release], and answers whether it built and, when it did
  /// not, the lines the tool printed about why.
  ///
  /// **Refused while the game runs.** `flutter run` holds the project's
  /// `build` directory and rebuilds into it on every swap; a second tool
  /// building there at the same time can leave either with half of the
  /// other's output. A change to a running game is `play_swap`'s.
  ///
  /// The errors and not the whole log: a failed build prints hundreds of
  /// lines of progress and a handful that say what is wrong, and those are
  /// what an agent fixes from.
  Future<Answer> build({String? target, bool release = false}) async {
    final root = projectRootOf(levelPath);
    if (root == null) {
      return (
        did: false,
        says:
            '$levelPath is not inside a Flutter project, so there is nothing '
            'to build',
      );
    }
    if (_run case final FlutterRun running when _going(running.state.value)) {
      return (
        did: false,
        says:
            'the game is running from this project; call play_stop before '
            'building it, or play_swap to take a change into the running game',
      );
    }
    final what = target ?? _hostTarget;
    if (!buildTargets.contains(what)) {
      return (
        did: false,
        says: 'cannot build for $what; one of ${buildTargets.join(', ')}',
      );
    }
    final mode = release ? 'release' : 'debug';
    final arguments = <String>[
      'build',
      what,
      '--$mode',
      if (what == 'ios') '--no-codesign',
    ];
    final ProcessResult result;
    try {
      result = await runFlutter(arguments, root);
    } on ProcessException catch (error) {
      return (did: false, says: 'could not start flutter: ${error.message}');
    }
    final printed = <String>[
      ...const LineSplitter().convert('${result.stdout}'),
      ...const LineSplitter().convert('${result.stderr}'),
    ].where((String line) => line.trim().isNotEmpty).toList();
    if (result.exitCode == 0) {
      final built = printed.lastWhere(
        (String line) => line.contains('Built '),
        orElse: () => '',
      );
      return (
        did: true,
        says:
            'built $root for $what ($mode)${built.isEmpty ? '' : ': ${built.trim()}'}',
      );
    }
    final errors = printed
        .where((String line) => line.toLowerCase().contains('error'))
        .toList();
    final shown = errors.isEmpty ? printed : errors;
    return (
      did: false,
      says:
          'flutter build $what failed (exit code ${result.exitCode}):\n'
          '${shown.skip(shown.length > 30 ? shown.length - 30 : 0).join('\n')}',
    );
  }

  /// Sends [document] to the running game whether or not it was saved — the
  /// level as the agent has it now — and says what the game did with it.
  Future<Answer> sendLevel(String document) async {
    final said = await sendSaved(document);
    return said == null
        ? (did: false, says: 'no game is running: call play first')
        : (did: !said.startsWith('the running game did not'), says: said);
  }

  /// Where the run is and the last [lines] of its console.
  String status({int lines = 40}) {
    final run = _run;
    if (run == null) return 'not running; call play to start the game';
    return '${_describe(run)}\n${_tail(run, lines)}'.trim();
  }

  /// What the game posted after the cursor [since], of [kinds] only when
  /// given, as JSON: the events in order, `next` to pass as [since] on the
  /// next call, `missed` when more were posted than were kept since the
  /// cursor, and `restarted` when the cursor is past anything posted — one
  /// from another server — and the answer starts from the first.
  Answer events({int since = 0, Set<String>? kinds}) {
    final run = _run;
    if (run == null) {
      return (did: false, says: 'not running; call play to start the game');
    }
    final before = _postedBefore;
    final read = eventsSince(
      run.events.value,
      since > before ? since - before : 0,
      kinds: kinds,
    );
    // A cursor into a run that has since been replaced: whatever that run
    // posted after it went with the run.
    final lost = since < before && !read.restarted ? before - since : 0;
    return (
      did: true,
      says: jsonEncode(<String, Object?>{
        'next': read.next + before,
        if (read.missed + lost > 0) 'missed': read.missed + lost,
        if (read.restarted) 'restarted': true,
        'events': <Object?>[
          for (final event in read.events)
            <String, Object?>{
              ...event.toJson(),
              'sequence': event.sequence + before,
            },
        ],
      }),
    );
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

  /// The last seconds the running game kept, as a `.f3drun` in its
  /// project's `test/tapes/` under [name] — the run an agent just watched
  /// go wrong, where `testReplay` and the sim server's `verify` and
  /// `bisect` read tapes from.
  ///
  Future<Answer> keepTape(String name) async {
    final address = vmService;
    final root = projectRootOf(levelPath);
    if (address == null || root == null) {
      return (did: false, says: 'no game is running: call play first');
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
      return (
        did: false,
        says: 'a tape is named in lowercase letters, digits and underscores',
      );
    }
    final answer = await ask(address, 'ext.flutter3d.timeline.bugReport');
    final json = answer.json;
    if (json == null) {
      return (did: false, says: answer.refused ?? 'the game kept nothing');
    }
    final Demo demo;
    try {
      // A bug report names its starting state `start`, which the editor's
      // timeline reads it by; a `.f3drun` names it `run`.
      demo = Demo.fromJson(<String, Object?>{
        ...json,
        if (!json.containsKey('run')) 'run': json['start'],
      });
    } on DemoFormatException catch (error) {
      return (
        did: false,
        says: 'the game\'s run is not a .f3drun: ${error.message}',
      );
    }
    final file = File('$root/test/tapes/$name${Demo.fileExtension}');
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(demo.toJson()));
    return (
      did: true,
      says:
          'kept ${demo.steps} steps of ${demo.level} as ${file.path}, '
          'played on the ${demo.physics ?? 'unrecorded'} physics',
    );
  }

  /// Where the running game's VM service is, or null while nothing runs.
  String? get vmService => switch (_run?.state.value) {
    PlayRunning(:final vmService) => vmService,
    _ => null,
  };

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
