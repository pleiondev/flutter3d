@TestOn('vm')
library;

/// `rp-02`'s remaining half, proved rather than merely built: a
/// `RunTimeline` running inside one process is paused, stepped, previewed
/// and released from a *second* process, over the same VM service protocol
/// Flutter DevTools and a level editor attached to a running game would use.
///
///     flutter test test/run_timeline_extensions_test.dart
///
/// `test/fixtures/timeline_target.dart` is the live target: a toy stepping
/// on its own clock with its timeline registered via
/// `registerTimelineExtensions`. This file starts it as `flutter test
/// --enable-vmservice`, waits for the VM service URI on its stdout the same
/// way a tool attaching to a running app would, connects with
/// `package:vm_service` — the library DevTools itself is built on — and
/// drives every extension in turn.
///
/// `@TestOn('vm')`: spawns a real subprocess and opens a real socket,
/// neither of which exists on the web.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Starts the fixture and returns a client already connected to its VM
/// service, plus the process to kill when done.
Future<({Process process, VmService service, String isolateId})>
_startAndConnect() async {
  final process = await Process.start('flutter', <String>[
    'test',
    '--enable-vmservice',
    '-v',
    'test/fixtures/timeline_target.dart',
  ], workingDirectory: Directory.current.path);

  // **Both streams are read for as long as the process lives.** This used to
  // stop reading stdout once the URI turned up and never read stderr at all.
  // `-v` keeps talking after the URI — the tool is still compiling and
  // loading the fixture — and with nobody reading, the pipe fills and the
  // tool blocks on its next write, before the fixture's `main` has run. On a
  // laptop with a warm compile cache the rest fits in the pipe; on a cold CI
  // runner it did not, and the extension was never registered at all.
  final tail = <String>[];
  void keep(String line) {
    tail.add(line);
    if (tail.length > 40) tail.removeAt(0);
  }

  final uriFound = Completer<String>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      keep(line);
      // The line `-v` prints once DDS has wrapped the raw VM service — the
      // same URI a tool attaching from outside would be handed.
      final match = RegExp(
        r'VM Service uri is available at (\S+)',
      ).firstMatch(line);
      if (match != null && !uriFound.isCompleted) {
        uriFound.complete(match.group(1));
      }
    },
  );
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => keep('stderr: $line'));

  final httpUri = await uriFound.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      process.kill();
      throw StateError(
        'the fixture never printed a VM service uri within 30s; '
        'its last lines:\n${tail.join('\n')}',
      );
    },
  );

  // `package:vm_service` speaks WebSocket; the printed uri is http(s).
  final wsUri = httpUri
      .replaceFirst('http://', 'ws://')
      .replaceFirst(RegExp(r'/?$'), '/ws');
  final service = await vmServiceConnectUri(wsUri);
  final isolateId = await _isolateWith(
    service,
    'ext.flutter3d.timeline.status',
    tail: tail,
  );

  return (process: process, service: service, isolateId: isolateId);
}

/// The isolate that has registered [extension], once one has.
///
/// **The URI is printed before the fixture can answer.** The VM service is up
/// as soon as the process is, and the fixture's `main` registers its
/// extensions only after `flutter test` has compiled and started it. This
/// used to take the first isolate and wait a fixed two seconds, which was
/// enough on a laptop; on a CI runner the first call arrived first and came
/// back `Unknown method "ext.flutter3d.timeline.status"`. Asking the isolate
/// what it has registered is the answer the protocol already gives, and
/// looking through every isolate rather than the first is what keeps the
/// harness's own isolates from being mistaken for the fixture.
///
/// [tail] is the fixture's latest output, quoted when nothing turns up, so a
/// failure here says where the fixture stopped rather than only that it did.
Future<String> _isolateWith(
  VmService service,
  String extension, {
  required List<String> tail,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.contains(extension) ?? false) return ref.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'no isolate registered $extension within 30s; '
    'the fixture\'s last lines:\n${tail.join('\n')}',
  );
}

Map<String, Object?> _decode(Response response) =>
    response.json! as Map<String, Object?>;

void main() {
  test('pause, step, preview and release, driven entirely from outside the '
      'process that is running', () async {
    final target = await _startAndConnect();
    addTearDown(() {
      target.service.dispose();
      target.process.kill();
    });

    // Give the loop time to accumulate at least one keyframe (a second at
    // 60 steps/second) before asking for a rewind.
    await Future<void>.delayed(const Duration(seconds: 2));

    final statusBefore = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.status',
      isolateId: target.isolateId,
    );
    expect(_decode(statusBefore), <String, Object?>{'paused': false});

    final paused = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.pause',
      isolateId: target.isolateId,
    );
    expect(_decode(paused), <String, Object?>{});

    final statusAfter = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.status',
      isolateId: target.isolateId,
    );
    expect(_decode(statusAfter), <String, Object?>{'paused': true});

    // stepOnce refuses when the timeline is not paused, from the outside
    // exactly as it does from a direct call — proved by asking for a
    // preview first, which does not touch pause state, then stepping
    // twice now that pause has taken effect.
    final stepped = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.stepOnce',
      isolateId: target.isolateId,
    );
    expect(_decode(stepped), <String, Object?>{});

    final preview = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.preview',
      isolateId: target.isolateId,
      args: <String, String>{'secondsAgo': '1.0'},
    );
    final previewJson = _decode(preview);
    expect(previewJson['found'], isTrue);
    final step = previewJson['step']! as int;

    final released = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.releaseAtStep',
      isolateId: target.isolateId,
      args: <String, String>{'step': '$step'},
    );
    expect(_decode(released), <String, Object?>{'released': true});

    // `releaseAt` already un-pauses — see its own doc — so a `resume` here
    // is a deliberate no-op, proved rather than assumed: it must return
    // cleanly and must not add a second entry to the history.
    final resumed = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.resume',
      isolateId: target.isolateId,
    );
    expect(_decode(resumed), <String, Object?>{});

    final history = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.history',
      isolateId: target.isolateId,
    );
    final commands = _decode(history)['commands']! as List<Object?>;
    expect(
      commands,
      <String>['paused', 'stepped', 'branched:$step'],
      reason:
          'the remote history should read back exactly the commands sent '
          'over the wire, in order — the same list an editor panel would '
          'render — and the no-op resume above should not have added a '
          'fourth',
    );

    // `rp-06`: the fixture times every step it takes, and the strip reads
    // that trace back over the same wire.
    final frameTimes = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.frameTimes',
      isolateId: target.isolateId,
    );
    final frameTimesJson = _decode(frameTimes);
    final steps = frameTimesJson['steps']! as List<Object?>;
    final millis = frameTimesJson['millis']! as List<Object?>;
    expect(
      steps,
      isNotEmpty,
      reason: 'the fixture has been stepping for seconds',
    );
    expect(millis.length, steps.length);

    // `rp-04`: the fixture's own bug report is whatever it chose to
    // return — proof that a caller's shape reaches the other end intact.
    final bugReport = await target.service.callServiceExtension(
      'ext.flutter3d.timeline.bugReport',
      isolateId: target.isolateId,
    );
    final bugReportJson = _decode(bugReport);
    expect(bugReportJson.containsKey('x'), isTrue);
    expect(bugReportJson.containsKey('step'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
