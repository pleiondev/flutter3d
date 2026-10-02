/// `HR5` in a browser: a game somebody else started, attached to by its VM
/// service address.
///
/// The web editor has no process to start, so it cannot run the project the
/// way the desktop one does. What it can do is open the same WebSocket
/// DevTools opens, and everything the desktop Play panel does once the game
/// is running goes over that socket anyway, except the hot reload itself,
/// which the flutter tool that started the game offers on it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart';

import 'play_state.dart';
import 'vm_connect.dart';
import 'watched.dart';

/// A running game, attached to at [vmService] rather than started.
///
/// **The reload is the flutter tool's, found on the socket.** A Flutter game
/// cannot recompile itself: the kernel for a hot reload is built by the
/// `flutter run` (or `flutter attach`) that is connected to it, and that tool
/// registers `reloadSources` and `hotRestart` on the game's VM service for
/// exactly this, which is how DevTools' own reload button works. So the
/// buttons call what the tool registered, and when no tool is connected they
/// say so rather than calling the VM's bare `reloadSources`, which would
/// answer that nothing changed.
///
/// **Its console starts with what the game printed before.** The service a
/// flutter tool puts in front of the VM (DDS) keeps the game's stdout and its
/// `log` calls and replays them to whoever listens, so an editor attaching
/// late still sees the start-up — seen on a real macOS run, ticks from before
/// the attach arriving first. The replay comes a stream at a time, so prints
/// and logs from before the attach are not interleaved as they happened. A
/// VM with no DDS in front gives only what follows.
final class AttachedRun implements PlayedGame {
  AttachedRun(this.vmService, {this._connect = connectVmService});

  /// The address a person gave, in any spelling `vmServiceWebSocket` reads.
  final String vmService;

  final ConnectVmService _connect;

  @override
  String get title => vmService;

  @override
  bool get ownsTheGame => false;

  @override
  final Watched<PlayState> state = Watched<PlayState>(const PlayIdle());

  @override
  final Watched<List<String>> console = Watched<List<String>>(const <String>[]);

  static const int consoleLimit = 2000;

  /// The names the flutter tool registered its services under, by service:
  /// `reloadSources` → `s0.reloadSources`.
  final Map<String, String> _services = <String, String>{};

  VmService? _service;
  bool _lettingGo = false;

  /// What each output stream has written since its last newline.
  final Map<String, String> _partial = <String, String>{};
  final List<StreamSubscription<Event>> _listening =
      <StreamSubscription<Event>>[];

  /// The services a flutter tool registers on the game it runs, by the
  /// protocol's names.
  static const String swapService = 'reloadSources';
  static const String restartService = 'hotRestart';

  @override
  Future<void> start() async {
    if (_service != null) return;
    state.value = PlayStarting('Attaching to $vmService…');
    final VmService service;
    try {
      service = await _connect(vmService);
    } on Object catch (error) {
      _print('could not attach to $vmService: $error');
      state.value = const PlayStopped(
        -1,
        reason:
            'Could not attach: is the game running, and is this the '
            'address it printed?',
      );
      return;
    }
    final VM vm;
    try {
      vm = await service.getVM();
    } on Object catch (error) {
      await service.dispose();
      _print('$vmService answered, but not as a VM service: $error');
      state.value = const PlayStopped(
        -1,
        reason:
            'Could not attach: is the game running, and is this the '
            'address it printed?',
      );
      return;
    }
    _service = service;
    _lettingGo = false;
    _listening.addAll(<StreamSubscription<Event>>[
      service.onStdoutEvent.listen((Event it) => _printed('stdout', it)),
      service.onStderrEvent.listen((Event it) => _printed('stderr', it)),
      service.onLoggingEvent.listen(_logged),
      service.onServiceEvent.listen(_registered),
    ]);
    // Subscribing to `Service` replays what is already registered, so a tool
    // that connected long before the editor is still found.
    for (final stream in const <String>[
      EventStreams.kStdout,
      EventStreams.kStderr,
      EventStreams.kLogging,
      EventStreams.kService,
    ]) {
      try {
        await service.streamListen(stream);
      } on RPCError {
        // Already listened to on this connection, or a VM without the
        // stream: the console is then a stream shorter, nothing more.
      }
    }
    unawaited(service.onDone.then((_) => _gone()));
    state.value = PlayRunning(appId: vm.name ?? 'vm', vmService: vmService);
  }

  @override
  Future<String?> hotSwap() => _tool(
    swapService,
    isolate: true,
    doing: 'swap new code into',
    done: 'Swapped in the new code',
  );

  @override
  Future<String?> hotRestart() => _tool(
    restartService,
    isolate: false,
    doing: 'restart',
    done: 'Restarted with the new code',
  );

  /// Lets go of the game, which keeps running.
  @override
  Future<void> stop() async {
    final service = _service;
    if (service == null) return;
    _lettingGo = true;
    await service.dispose();
    await _gone();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await state.close();
    await console.close();
  }

  /// Calls the flutter tool's service [name]; [doing] and [done] are what
  /// the console says of it.
  Future<String?> _tool(
    String name, {
    required bool isolate,
    required String doing,
    required String done,
  }) async {
    final service = _service;
    if (service == null) return null;
    final method = _services[name];
    if (method == null) {
      return _say(
        'nothing attached to this game can $doing it: the new code is '
        'compiled by the flutter tool that runs the game, and none has '
        'registered $name here. Start the game with `flutter run`, or '
        '`flutter attach` to it, and attach to the address that prints',
      );
    }
    try {
      final response = await service.callMethod(
        method,
        isolateId: isolate ? await _mainIsolate(service) : null,
        args: <String, Object?>{'pause': false, 'force': false},
      );
      return _say(switch (response.json) {
        {'type': 'Success'} || null => done,
        final Map<String, Object?> other => '${other['type'] ?? other}',
      });
    } on RPCError catch (error) {
      // A compile error is printed by the tool in its own terminal; what
      // comes back here is only that the new code did not go in.
      final details = error.details ?? '';
      return _say(
        'the tool refused to $doing the game: ${error.message}'
        '${details.isEmpty ? '' : ': $details'}',
      );
    } on Object catch (error) {
      return _say('could not ask for $name: $error');
    }
  }

  /// The isolate the game runs in: the one called `main` when there is one,
  /// since a game may have spawned others, and the first otherwise.
  Future<String> _mainIsolate(VmService service) async {
    final isolates = (await service.getVM()).isolates ?? const <IsolateRef>[];
    if (isolates.isEmpty) {
      throw StateError('the VM at $vmService reports no isolates');
    }
    return (isolates.where((it) => it.name == 'main').firstOrNull ??
            isolates.first)
        .id!;
  }

  void _registered(Event event) {
    switch (event) {
      case Event(
        kind: EventKind.kServiceRegistered,
        :final String service,
        :final String method,
      ):
        _services[service] = method;
      case Event(kind: EventKind.kServiceUnregistered, :final String service):
        _services.remove(service);
      default:
        break;
    }
  }

  /// **A line is printed when its newline arrives, not with each write.** The
  /// engine sends a `print` as two writes, the text and then `\n` — seen on a
  /// real macOS run — so a write is not a line, and taking it for one put an
  /// empty line after everything the game printed.
  void _printed(String stream, Event event) {
    if (event.bytes case final String bytes) {
      final lines =
          ((_partial[stream] ?? '') +
                  utf8.decode(base64.decode(bytes), allowMalformed: true))
              .split('\n');
      _partial[stream] = lines.last;
      lines
          .take(lines.length - 1)
          .map((line) => line.replaceFirst(RegExp(r'\r$'), ''))
          .forEach(_print);
    }
  }

  void _logged(Event event) {
    if (event.logRecord?.message?.valueAsString case final String message) {
      _print(message);
    }
  }

  Future<void> _gone() async {
    if (_service == null) return;
    _service = null;
    _services.clear();
    // A last line the game never ended is still a line it printed.
    _partial.values.where((it) => it.isNotEmpty).forEach(_print);
    _partial.clear();
    for (final listening in _listening) {
      await listening.cancel();
    }
    _listening.clear();
    state.value = PlayStopped(
      0,
      reason: _lettingGo
          ? 'Detached; the game keeps running'
          : 'The game closed the connection',
    );
  }

  String _say(String line) {
    _print(line);
    return line;
  }

  void _print(String line) {
    console.value = appendLine(console.value, line, consoleLimit);
  }
}
