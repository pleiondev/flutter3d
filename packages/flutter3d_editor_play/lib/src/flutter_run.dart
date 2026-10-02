/// `HR5`: the project a level belongs to, run from the editor.
///
/// `flutter run --machine` and not a game built into the editor: the level
/// belongs to another application, with its own code, packages and entry
/// point, and the only thing that runs it the way its author does is the
/// author's own `flutter run`. `--machine` makes it a daemon the editor talks
/// to in JSON lines — the same protocol an IDE uses — so a hot reload from the
/// toolbar is the same hot reload the terminal would have done, and the game
/// answers it through `HotSwap` the same way.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'play_state.dart';
import 'watched.dart';

/// Starts `flutter` with [arguments] in [workingDirectory]. A parameter of
/// [FlutterRun] so a test hands it a process of its own making.
typedef StartFlutter =
    Future<Process> Function(List<String> arguments, String workingDirectory);

Future<Process> _startFlutter(
  List<String> arguments,
  String workingDirectory,
) => Process.start(
  'flutter',
  arguments,
  workingDirectory: workingDirectory,
  runInShell: Platform.isWindows,
);

/// One `flutter run --machine`, from start to exit.
///
/// **Its console is the tool's, line for line.** What the game prints, what
/// the tool reports and any line that is not the protocol at all — a build
/// error comes out as plain text before the daemon has said anything — all
/// go to [console] in the order they arrived, because the moment somebody
/// needs this panel is the moment something went wrong, and a filtered
/// console hides exactly that.
final class FlutterRun implements PlayedGame {
  FlutterRun({
    required this.projectRoot,
    this.device,
    this._start = _startFlutter,
  });

  /// The directory with the project's `pubspec.yaml`.
  final String projectRoot;

  /// `-d` for `flutter run`; the tool's own choice when null. Read by the
  /// next [start], so a picker sets it between runs.
  String? device;

  final StartFlutter _start;

  @override
  String get title => projectRoot;

  @override
  bool get ownsTheGame => true;

  /// Where the run is; a panel rebuilds from it.
  @override
  final Watched<PlayState> state = Watched<PlayState>(const PlayIdle());

  /// Every line the run has printed, oldest first. Capped at [consoleLimit],
  /// dropping the oldest, so a game that logs every frame costs a bounded
  /// list and not the editor's memory.
  @override
  final Watched<List<String>> console = Watched<List<String>>(const <String>[]);

  static const int consoleLimit = 2000;

  Process? _process;
  String? _appId;
  var _nextId = 0;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};

  /// Starts the run. Does nothing while one is already going.
  @override
  Future<void> start() async {
    if (_process != null) return;
    state.value = const PlayStarting('Starting flutter run…');
    final Process process;
    try {
      process = await _start(<String>[
        'run',
        '--machine',
        if (device case final String id) ...<String>['-d', id],
      ], projectRoot);
    } on ProcessException catch (error) {
      _print('could not start flutter: ${error.message}');
      state.value = const PlayStopped(-1);
      return;
    }
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_line);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_print);
    unawaited(
      process.exitCode.then((int code) {
        _process = null;
        _appId = null;
        for (final pending in _pending.values) {
          pending.completeError(StateError('flutter run exited ($code)'));
        }
        _pending.clear();
        state.value = PlayStopped(code);
      }),
    );
  }

  /// A hot reload: the game keeps its state, and `HotSwap` relinks shaders
  /// and swaps changed models from `reassemble`. What the tool said about it,
  /// "Reloaded 3 of 812 libraries" or why it refused, or null when nothing is
  /// running.
  @override
  Future<String?> hotSwap() => _restart(fullRestart: false);

  /// A hot restart: the game starts over from `main`, with the new code.
  @override
  Future<String?> hotRestart() => _restart(fullRestart: true);

  /// Asks the game to stop, and the tool with it.
  @override
  Future<void> stop() async {
    final appId = _appId;
    if (appId == null) {
      _process?.kill();
      return;
    }
    try {
      await _send('app.stop', <String, Object?>{'appId': appId});
    } on StateError {
      // Already gone.
    }
  }

  /// Stops the run if there is one and lets go of the process.
  @override
  Future<void> dispose() async {
    await stop();
    await state.close();
    await console.close();
  }

  Future<String?> _restart({required bool fullRestart}) async {
    final appId = _appId;
    if (appId == null) return null;
    final result = await _send('app.restart', <String, Object?>{
      'appId': appId,
      'fullRestart': fullRestart,
      'pause': false,
      'reason': 'manual',
    });
    // "Reloaded 3 of 812 libraries" as well as a refusal: after a press of
    // the button, the console is where somebody looks to see it happened.
    if (result case {'message': final String message} when message.isNotEmpty) {
      _print(message);
      return message;
    }
    return '';
  }

  Future<Object?> _send(String method, Map<String, Object?> params) {
    final process = _process;
    if (process == null) {
      return Future<Object?>.error(StateError('nothing is running'));
    }
    final id = _nextId++;
    final reply = Completer<Object?>();
    _pending[id] = reply;
    process.stdin.writeln(
      jsonEncode(<Object?>[
        <String, Object?>{'id': id, 'method': method, 'params': params},
      ]),
    );
    return reply.future;
  }

  void _line(String line) {
    // The protocol wraps each message in a one-element list; anything else
    // on stdout is the tool talking before or around the daemon.
    final Object? decoded;
    try {
      decoded = line.startsWith('[{') ? jsonDecode(line) : null;
    } on FormatException {
      _print(line);
      return;
    }
    switch (decoded) {
      case [final Map<String, Object?> message]:
        _message(message);
      default:
        _print(line);
    }
  }

  void _message(Map<String, Object?> message) {
    switch (message) {
      case {'id': final int id, 'error': final Object? error}:
        _pending.remove(id)?.completeError(StateError('$error'));
      case {'id': final int id}:
        _pending.remove(id)?.complete(message['result']);
      case {'event': 'app.start', 'params': {'appId': final String appId}}:
        _appId = appId;
      case {
        'event': 'app.debugPort',
        'params': {'appId': final String appId, 'wsUri': final String uri},
      }:
        _appId = appId;
        state.value = PlayRunning(appId: appId, vmService: uri);
      case {'event': 'app.log', 'params': {'log': final String log}}:
        _print(log);
      case {
        'event': 'daemon.logMessage',
        'params': {'message': final String m},
      }:
        _print(m);
      case {
        'event': 'app.progress',
        'params': {'message': final String progress},
      }:
        _print(progress);
        if (state.value is PlayStarting) {
          state.value = PlayStarting(progress);
        }
      default:
        // `app.started`, `app.stop`, `daemon.connected`, `device.*` and
        // whatever a later tool adds: nothing the panel shows.
        break;
    }
  }

  void _print(String line) {
    console.value = appendLine(console.value, line, consoleLimit);
  }
}

/// The directory of the nearest `pubspec.yaml` above [levelPath], or null
/// when the level is not inside a project at all.
///
/// [hasPubspec] answers for a directory; injected, like
/// `Documents.assetRootFor`'s own check, so this is tested with no disk.
String? projectRootFor(
  String levelPath, {
  required bool Function(String directory) hasPubspec,
}) => _nearest(File(levelPath).parent, hasPubspec);

String? _nearest(Directory directory, bool Function(String) hasPubspec) =>
    switch (directory.parent) {
      _ when hasPubspec(directory.path) => directory.path,
      final parent when parent.path == directory.path => null,
      final parent => _nearest(parent, hasPubspec),
    };

/// [projectRootFor], asking the disk.
String? projectRootOnDisk(String levelPath) => projectRootFor(
  levelPath,
  hasPubspec: (String directory) =>
      File('$directory${Platform.pathSeparator}pubspec.yaml').existsSync(),
);
