/// A `flutter run --machine` a test controls, for anything that drives a
/// [FlutterRun] and wants to say what the tool answers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'flutter3d_editor_play.dart';

/// A `flutter run --machine` that says what [say] is given and records what
/// it is sent.
final class FakeFlutterTool implements Process {
  final StreamController<List<int>> _out = StreamController<List<int>>();
  final StreamController<List<int>> _err = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();

  /// Every message sent to the tool, in order.
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  late final IOSink _in = IOSink(_Sent(this));

  /// A line on the tool's stdout.
  void say(String line) => _out.add(utf8.encode('$line\n'));

  /// A daemon event.
  void event(String event, Map<String, Object?> params) => say(
    jsonEncode(<Object?>[
      <String, Object?>{'event': event, 'params': params},
    ]),
  );

  /// The answer to request [id].
  void answer(int id, Object? result) => say(
    jsonEncode(<Object?>[
      <String, Object?>{'id': id, 'result': result},
    ]),
  );

  /// The tool announcing a game running with its VM service at [wsUri].
  void running({String appId = 'a1', String wsUri = 'ws://game'}) =>
      event('app.debugPort', <String, Object?>{'appId': appId, 'wsUri': wsUri});

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _out.stream;

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  IOSink get stdin => _in;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    exit(-15);
    return true;
  }
}

final class _Sent implements StreamConsumer<List<int>> {
  _Sent(this.tool);

  final FakeFlutterTool tool;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((String line) {
        final [Object? message] = jsonDecode(line) as List<Object?>;
        tool.sent.add(message! as Map<String, Object?>);
      });

  @override
  Future<void> close() async {}
}

/// A [FlutterRun] over a [FakeFlutterTool], and the arguments each start
/// was given, the working directory first.
({FlutterRun run, FakeFlutterTool tool, List<List<String>> started})
fakeFlutterRun({String projectRoot = '/game', String? device = 'macos'}) {
  final tool = FakeFlutterTool();
  final started = <List<String>>[];
  return (
    run: FlutterRun(
      projectRoot: projectRoot,
      device: device,
      start: (List<String> arguments, String directory) async {
        started.add(<String>[directory, ...arguments]);
        return tool;
      },
    ),
    tool: tool,
    started: started,
  );
}
