/// A `flutter run --machine` a test controls, for anything that drives a
/// [FlutterRun] and wants to say what the tool answers, and a game's VM
/// service a test controls, for an [AttachedRun].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';

import 'flutter3d_editor_play.dart';

/// A running game's VM service, answering over [service] as the real one
/// answers over a socket, and recording every call it is sent.
///
/// The game has one isolate, `main`, whose extensions are [extensions]. A
/// flutter tool attached to it is [registered]: its services by name, and
/// what each answers in [toolAnswers], `null` for success or an
/// [RPCError] to refuse.
final class FakeGame {
  FakeGame({
    Map<String, String>? registered,
    this.extensions = const <String>[],
  }) : registered = registered ?? <String, String>{};

  /// The flutter tool `flutter run` attaches, as DevTools finds it.
  static Map<String, String> flutterTool() => <String, String>{
    'reloadSources': 's0.reloadSources',
    'hotRestart': 's0.hotRestart',
  };

  final Map<String, String> registered;
  final List<String> extensions;

  /// What a registered method answers, by its registered name.
  final Map<String, RPCError?> toolAnswers = <String, RPCError?>{};

  /// What an extension answers, by its name.
  final Map<String, Map<String, Object?>> extensionAnswers =
      <String, Map<String, Object?>>{};

  /// Every call, as `{'method': …, 'params': …}`, in order.
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  final StreamController<String> _out = StreamController<String>();
  late final VmService service = VmService(_out.stream, _receive);

  static const String isolateId = 'isolates/1';

  /// The game printing [text] to stdout.
  void prints(String text) => _event('Stdout', <String, Object?>{
    'kind': 'WriteEvent',
    'bytes': base64.encode(utf8.encode(text)),
  });

  /// The game calling `dart:developer`'s `log` with [message].
  void logs(String message) => _event('Logging', <String, Object?>{
    'kind': 'Logging',
    'logRecord': <String, Object?>{
      'type': 'LogRecord',
      'message': <String, Object?>{
        'type': '@Instance',
        'id': 'objects/1',
        'kind': 'String',
        'valueAsString': message,
      },
      'time': 0,
      'level': 800,
      'sequenceNumber': 0,
      'loggerName': <String, Object?>{
        'type': '@Instance',
        'id': 'objects/2',
        'kind': 'String',
        'valueAsString': '',
      },
      'zone': <String, Object?>{'type': '@Instance', 'kind': 'Null'},
      'error': <String, Object?>{'type': '@Instance', 'kind': 'Null'},
      'stackTrace': <String, Object?>{'type': '@Instance', 'kind': 'Null'},
    },
  });

  /// The game calling `dart:developer`'s `postEvent` with [kind] and
  /// [data] — `flutter3d_game`'s `postToolEvent` posts `flutter3d.<kind>` —
  /// at [time], milliseconds since the epoch as the VM stamps it.
  void posts(
    String kind, [
    Map<String, Object?> data = const <String, Object?>{},
    int time = 0,
  ]) => _event('Extension', <String, Object?>{
    'kind': 'Extension',
    'extensionKind': kind,
    'extensionData': data,
    'timestamp': time,
    'isolate': <String, Object?>{
      'type': '@Isolate',
      'id': isolateId,
      'name': 'main',
      'number': '1',
      'isSystemIsolate': false,
    },
  });

  /// The game exiting, which closes the socket.
  Future<void> exits() => _out.close();

  void _receive(String message) {
    final request = jsonDecode(message) as Map<String, Object?>;
    final method = request['method']! as String;
    final params = request['params'] as Map<String, Object?>? ?? const {};
    calls.add(<String, Object?>{'method': method, 'params': params});
    final id = request['id'];
    void reply(Map<String, Object?> result) =>
        _send(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result});
    switch (method) {
      case 'getVM':
        reply(<String, Object?>{
          'type': 'VM',
          'name': 'game',
          'isolates': <Object?>[
            <String, Object?>{
              'type': '@Isolate',
              'id': isolateId,
              'name': 'main',
              'number': '1',
              'isSystemIsolate': false,
            },
          ],
        });
      case 'getIsolate':
        reply(<String, Object?>{
          'type': 'Isolate',
          'id': isolateId,
          'name': 'main',
          'number': '1',
          'isSystemIsolate': false,
          'extensionRPCs': extensions,
        });
      case 'streamListen':
        reply(const <String, Object?>{'type': 'Success'});
        if (params['streamId'] == 'Service') {
          for (final MapEntry(key: name, value: registeredAs)
              in registered.entries) {
            _event('Service', <String, Object?>{
              'kind': 'ServiceRegistered',
              'service': name,
              'method': registeredAs,
              'alias': 'Flutter Tools',
            });
          }
        }
      case final String name when name.startsWith('ext.'):
        reply(extensionAnswers[name] ?? const <String, Object?>{});
      case final String name when registered.containsValue(name):
        switch (toolAnswers[name]) {
          case final RPCError error:
            _send(<String, Object?>{
              'jsonrpc': '2.0',
              'id': id,
              'error': error.toMap(),
            });
          case null:
            reply(const <String, Object?>{'type': 'Success'});
        }
      default:
        _send(<String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, Object?>{
            'code': -32601,
            'message': 'Method not found',
          },
        });
    }
  }

  void _event(String stream, Map<String, Object?> event) =>
      _send(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'streamNotify',
        'params': <String, Object?>{
          'streamId': stream,
          'event': <String, Object?>{'type': 'Event', 'timestamp': 0, ...event},
        },
      });

  void _send(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add(jsonEncode(message));
  }
}

/// An [AttachedRun] to [game].
AttachedRun fakeAttachedRun(FakeGame game, {String uri = 'ws://game/ws'}) =>
    AttachedRun(uri, connect: (String _) async => game.service);

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
///
/// [game] is the VM service the run finds at the address the tool reports,
/// for a test that has the game post events; one that posts nothing when
/// left out.
({FlutterRun run, FakeFlutterTool tool, List<List<String>> started})
fakeFlutterRun({
  String projectRoot = '/game',
  String? device = 'macos',
  FakeGame? game,
}) {
  final tool = FakeFlutterTool();
  final started = <List<String>>[];
  final reached = game ?? FakeGame();
  return (
    run: FlutterRun(
      projectRoot: projectRoot,
      device: device,
      start: (List<String> arguments, String directory) async {
        started.add(<String>[directory, ...arguments]);
        return tool;
      },
      connect: (String _) async => reached.service,
    ),
    tool: tool,
    started: started,
  );
}
