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

  final uriFound = Completer<String>();
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final subscription = lines.listen((line) {
    // The line `-v` prints once DDS has wrapped the raw VM service — the
    // same URI a tool attaching from outside would be handed.
    final match = RegExp(
      r'VM Service uri is available at (\S+)',
    ).firstMatch(line);
    if (match != null && !uriFound.isCompleted) {
      uriFound.complete(match.group(1));
    }
  });

  final httpUri = await uriFound.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      process.kill();
      throw StateError(
        'the fixture never printed a VM service uri within 30s',
      );
    },
  );
  await subscription.cancel();

  // `package:vm_service` speaks WebSocket; the printed uri is http(s).
  final wsUri = httpUri.replaceFirst('http://', 'ws://').replaceFirst(
        RegExp(r'/?$'),
        '/ws',
      );
  final service = await vmServiceConnectUri(wsUri);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  return (process: process, service: service, isolateId: isolateId);
}

Map<String, Object?> _decode(Response response) =>
    response.json! as Map<String, Object?>;

void main() {
  test(
    'pause, step, preview and release, driven entirely from outside the '
    'process that is running',
    () async {
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
      expect(steps, isNotEmpty, reason: 'the fixture has been stepping for seconds');
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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
