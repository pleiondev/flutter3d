import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter3d_game/flutter3d_game.dart';

import 'run_timeline.dart';

/// Puts a [RunTimeline] on the VM service, so a running game can be paused,
/// stepped, scrubbed and branched from outside the process it is playing in
/// — a level editor attached over the same channel Flutter DevTools already
/// uses, rather than a simulation embedded inside the editor itself.
///
/// **Why this, and not a simulation inside the editor.** `apps/flutter3d_editor`
/// edits a `Level` and does not know a single `EntityKind` — it has no
/// registry, no genre, nothing to build a `PlatformerSimulation` or a
/// `GameSimulation` out of. Only a running *game* has that, already loaded,
/// already playing. `ROADMAP.md`'s own plan for "the editors reach the
/// running game" is to reach it — hot reload and restart through the VM
/// service, a device already running the project — not to rebuild it a
/// second time inside a tool that was never going to carry every genre's
/// vocabulary. This is the timeline's own door onto that channel:
/// `dart:developer`'s [developer.registerExtension] is the same mechanism
/// `flutter_driver` and DevTools use to reach into a running app, and a
/// [RunTimeline] registered here answers exactly the commands `rp-02`'s
/// still-unbuilt panel would send — pause, step, preview a rewind, release
/// at a step — whether that panel ends up being a Flutter widget, an MCP
/// tool, or something else that speaks the VM service protocol.
///
/// ## What a caller on the other end sees
///
/// Seven extensions always, and up to two more depending on what the caller
/// hands over — each named `ext.flutter3d.timeline.<verb>`, callable the way
/// any `package:vm_service` client calls one —
/// `service.callServiceExtension(isolateId, method: name, args: params)` —
/// with string-keyed, string-valued parameters, because that is the one
/// shape the VM service protocol allows for them:
///
/// * `pause`, `resume`, `stepOnce` — no parameters, mirror the timeline's own
///   methods of the same name.
/// * `preview` — `secondsAgo`, a number as a string; returns `{"found":
///   true, "step": 118}` or `{"found": false}`.
/// * `releaseAtStep` — `step`, an integer as a string; returns `{"released":
///   true}` or `{"released": false}` when the buffer no longer reaches it.
/// * `history` — no parameters; returns `{"commands": [...]}`, one short
///   string per [TimelineCommand] — `"paused"`, `"resumed"`, `"stepped"`, or
///   `"branched:118"` naming the step a branch landed at.
/// * `status` — no parameters; returns `{"paused": true}` — what a panel
///   polls to draw its own pause/play button correctly on first connecting,
///   rather than assuming the timeline was already running.
/// * `frameTimes` — registered only when [frameTimes] is given; no
///   parameters, returns that [StepTimeTrace]'s own [StepTimeTrace.toJson] —
///   `rp-06`'s strip, read from wherever the caller is already timing its
///   own step.
/// * `bugReport` — registered only when [bugReport] is given; no parameters,
///   returns whatever that callback hands back, or a VM service error if it
///   throws — `rp-04`'s "send this run", called remotely rather than from a
///   button the game itself draws. What the callback returns is the
///   caller's business; a `Demo.toJson()` is the obvious shape, and this
///   does not require it.
///
/// Registered once per [RunTimeline]; registering the same [timeline] twice
/// throws, the same way [developer.registerExtension] itself refuses a
/// method name it has already seen.
void registerTimelineExtensions(
  RunTimeline timeline, {
  StepTimeTrace? frameTimes,
  Map<String, Object?> Function()? bugReport,
}) {
  developer.registerExtension('ext.flutter3d.timeline.pause', (
    method,
    parameters,
  ) async {
    timeline.pause();
    return developer.ServiceExtensionResponse.result('{}');
  });

  developer.registerExtension('ext.flutter3d.timeline.resume', (
    method,
    parameters,
  ) async {
    timeline.resume();
    return developer.ServiceExtensionResponse.result('{}');
  });

  developer.registerExtension('ext.flutter3d.timeline.stepOnce', (
    method,
    parameters,
  ) async {
    if (!timeline.isPaused) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'the timeline is not paused',
      );
    }
    timeline.stepOnce();
    return developer.ServiceExtensionResponse.result('{}');
  });

  developer.registerExtension('ext.flutter3d.timeline.preview', (
    method,
    parameters,
  ) async {
    final secondsAgo = double.tryParse(parameters['secondsAgo'] ?? '');
    if (secondsAgo == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'secondsAgo must be a number',
      );
    }
    final point = timeline.preview(secondsAgo);
    return developer.ServiceExtensionResponse.result(
      jsonEncode(
        point == null
            ? <String, Object?>{'found': false}
            : <String, Object?>{'found': true, 'step': point.step},
      ),
    );
  });

  developer.registerExtension('ext.flutter3d.timeline.releaseAtStep', (
    method,
    parameters,
  ) async {
    final step = int.tryParse(parameters['step'] ?? '');
    if (step == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'step must be an integer',
      );
    }
    final released = timeline.releaseAtStep(step);
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'released': released}),
    );
  });

  developer.registerExtension('ext.flutter3d.timeline.history', (
    method,
    parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{
        'commands': <String>[
          for (final command in timeline.history) _describe(command),
        ],
      }),
    );
  });

  developer.registerExtension('ext.flutter3d.timeline.status', (
    method,
    parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'paused': timeline.isPaused}),
    );
  });

  if (frameTimes != null) {
    developer.registerExtension('ext.flutter3d.timeline.frameTimes', (
      method,
      parameters,
    ) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(frameTimes.toJson()),
      );
    });
  }

  if (bugReport != null) {
    developer.registerExtension('ext.flutter3d.timeline.bugReport', (
      method,
      parameters,
    ) async {
      try {
        return developer.ServiceExtensionResponse.result(
          jsonEncode(bugReport()),
        );
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$error',
        );
      }
    });
  }
}

String _describe(TimelineCommand command) => switch (command) {
  TimelinePaused() => 'paused',
  TimelineResumed() => 'resumed',
  TimelineStepped() => 'stepped',
  TimelineBranched(:final step) => 'branched:$step',
};
