import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

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
/// Fourteen extensions — each named `ext.flutter3d.timeline.<verb>`, callable the way
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
/// * `status` — no parameters; returns `{"paused": true, "step": 600,
///   "oldest": 0, "scrubbedAt": null}` — what a panel polls to draw its own
///   pause/play button correctly on first connecting, rather than assuming
///   the timeline was already running, and the two ends of its scrubber.
/// * `returnToPresent` — no parameters; returns `{"returned": true}`, false
///   when there was no scrub to leave.
/// * `branchHere` — no parameters; returns `{"moved": true, "step": 118}`,
///   or `{"moved": false, "refusal": "..."}` at the present.
/// * `scrubTo` — `step`, an integer as a string; the same answer as
///   `branchHere`. `N4`'s scrubber.
/// * `tracks` — answers only when [entityLayout] is given, read from the
///   part [trackedPart] of the loop's capture (the whole capture when null);
///   `every`, steps between reads (one when absent); returns
///   [EntityTracks.toJson] over the steps the buffer holds, or
///   `{"reached": false}` before the first keyframe.
/// * `frameTimes` — answers only when [frameTimes] is given; no
///   parameters, returns that [StepTimeTrace]'s own [StepTimeTrace.toJson] —
///   `rp-06`'s strip, read from wherever the caller is already timing its
///   own step.
/// * `bugReport` — answers only when [bugReport] is given; no parameters,
///   returns whatever that callback hands back, or a VM service error if it
///   throws — `rp-04`'s "send this run", called remotely rather than from a
///   button the game itself draws. The keys `api/flutter3d_game.vm` lists
///   are the bug report the games build (`version`, `level`, `levelHash`,
///   `start`, `tape`, `buildStamp`, `checkpoints`, `platform`), which the
///   editor reads back as a `.f3drun`; a game that answers otherwise is
///   answering a tool of its own.
/// * `replayUnderNewCode` — `seconds`, a number as a string (three when
///   absent); returns
///   [CodeReplay.toJson], or `{"reached": false}` when the buffer does not
///   reach that far. `HR4`: called after a hot reload, it lives the last
///   seconds again under the new code and names where that run parts from
///   the old one.
///
/// **Several timelines, one set of names.** The VM service has one
/// `ext.flutter3d.timeline.pause` per isolate, so a second screen, a test
/// that builds a fresh game, or a game that starts a new run each register
/// their timeline in turn, and the extensions answer for the one registered
/// most recently that is still on: cancelling its [Registration] hands them
/// back to the one before, and cancelling the last switches them off (they
/// answer an error saying so until a timeline is registered again).
/// Registering a timeline that is already on throws an [ArgumentError].
///
/// The extensions that need something only some timelines were given —
/// `frameTimes`, `tracks`, `bugReport` — are always on the service and
/// answer an error naming what is missing when the current timeline was
/// registered without it, so a tool lists the same names whichever game it
/// is attached to.
Registration registerTimelineExtensions(
  RunTimeline timeline, {
  StepTimeTrace? frameTimes,
  Map<String, Object?> Function()? bugReport,
  EntityLayout? entityLayout,
  String? trackedPart,
}) {
  if (_onService.any((_OnService on) => identical(on.timeline, timeline))) {
    throw ArgumentError.value(
      timeline,
      'timeline',
      'is already on the VM service; cancel its Registration first',
    );
  }
  final entry = _OnService(
    timeline,
    frameTimes: frameTimes,
    bugReport: bugReport,
    entityLayout: entityLayout,
    trackedPart: trackedPart,
  );
  _onService.add(entry);
  if (_onService.length == 1) _timelineExtensions = _registerTimeline();
  return Registration(() {
    _onService.remove(entry);
    if (_onService.isNotEmpty) return;
    for (final registration in _timelineExtensions) {
      registration.cancel();
    }
    _timelineExtensions = const <Registration>[];
  });
}

/// A timeline on the VM service, with what it was registered with.
final class _OnService {
  const _OnService(
    this.timeline, {
    required this.frameTimes,
    required this.bugReport,
    required this.entityLayout,
    required this.trackedPart,
  });

  final RunTimeline timeline;
  final StepTimeTrace? frameTimes;
  final Map<String, Object?> Function()? bugReport;
  final EntityLayout? entityLayout;
  final String? trackedPart;
}

/// Every timeline registered and still on, oldest first; the extensions
/// answer for the last.
final List<_OnService> _onService = <_OnService>[];

/// The extensions' own registrations, while any timeline is on.
List<Registration> _timelineExtensions = const <Registration>[];

/// The answer for an extension the current timeline was registered without
/// [what] for.
developer.ServiceExtensionResponse _without(String what) =>
    developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      'the timeline on the VM service was registered without $what',
    );

/// Puts every `ext.flutter3d.timeline.*` name on the service, each answering
/// for the last of [_onService].
List<Registration> _registerTimeline() => <Registration>[
  registerFlutter3dExtension('ext.flutter3d.timeline.pause', (
    method,
    parameters,
  ) async {
    _onService.last.timeline.pause();
    return developer.ServiceExtensionResponse.result('{}');
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.resume', (
    method,
    parameters,
  ) async {
    _onService.last.timeline.resume();
    return developer.ServiceExtensionResponse.result('{}');
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.stepOnce', (
    method,
    parameters,
  ) async {
    final timeline = _onService.last.timeline;
    if (!timeline.isPaused) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'the timeline is not paused',
      );
    }
    timeline.stepOnce();
    return developer.ServiceExtensionResponse.result('{}');
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.preview', (
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
    final point = _onService.last.timeline.preview(secondsAgo);
    return developer.ServiceExtensionResponse.result(
      jsonEncode(
        point == null
            ? <String, Object?>{'found': false}
            : <String, Object?>{'found': true, 'step': point.step},
      ),
    );
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.releaseAtStep', (
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
    final released = _onService.last.timeline.releaseAtStep(step);
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'released': released}),
    );
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.history', (
    method,
    parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{
        'commands': <String>[
          for (final command in _onService.last.timeline.history)
            _describe(command),
        ],
      }),
    );
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.status', (
    method,
    parameters,
  ) async {
    final timeline = _onService.last.timeline;
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{
        'paused': timeline.isPaused,
        'step': timeline.rewind.step,
        'oldest': timeline.rewind.oldestStep,
        'scrubbedAt': timeline.scrubbedAt,
      }),
    );
  }),

  registerFlutter3dExtension('ext.flutter3d.timeline.returnToPresent', (
    method,
    parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{
        'returned': _onService.last.timeline.returnToPresent(),
      }),
    );
  }),

  registerFlutter3dExtension(
    'ext.flutter3d.timeline.branchHere',
    (method, parameters) async => developer.ServiceExtensionResponse.result(
      jsonEncode(_onService.last.timeline.branchHere().toJson()),
    ),
    answers: const <String>{'moved', 'step', 'refusal'},
  ),

  registerFlutter3dExtension('ext.flutter3d.timeline.frameTimes', (
    method,
    parameters,
  ) async {
    final frameTimes = _onService.last.frameTimes;
    if (frameTimes == null) return _without('frameTimes');
    return developer.ServiceExtensionResponse.result(
      jsonEncode(frameTimes.toJson()),
    );
  }, answers: const <String>{'every', 'steps', 'millis'}),

  registerFlutter3dExtension('ext.flutter3d.timeline.scrubTo', (
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
    return developer.ServiceExtensionResponse.result(
      jsonEncode(_onService.last.timeline.scrubTo(step).toJson()),
    );
  }, answers: const <String>{'moved', 'step', 'refusal'}),

  registerFlutter3dExtension('ext.flutter3d.timeline.tracks', (
    method,
    parameters,
  ) async {
    final on = _onService.last;
    final layout = on.entityLayout;
    if (layout == null) return _without('an entityLayout');
    final every = int.tryParse(parameters['every'] ?? '') ?? 1;
    if (every < 1) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'every must be a whole number of steps, one or more',
      );
    }
    final tracks = on.timeline.tracks(
      layout: layout,
      part: on.trackedPart,
      every: every,
    );
    return developer.ServiceExtensionResponse.result(
      jsonEncode(tracks?.toJson() ?? const <String, Object?>{'reached': false}),
    );
  }, answers: const <String>{'first', 'last', 'entities', 'reached'}),

  registerFlutter3dExtension('ext.flutter3d.timeline.replayUnderNewCode', (
    method,
    parameters,
  ) async {
    final seconds = double.tryParse(parameters['seconds'] ?? '') ?? 3.0;
    final replay = _onService.last.timeline.replayUnderNewCode(
      seconds: seconds,
    );
    return developer.ServiceExtensionResponse.result(
      jsonEncode(replay?.toJson() ?? const <String, Object?>{'reached': false}),
    );
  }, answers: const <String>{'fromStep', 'toStep', 'divergence', 'reached'}),

  registerFlutter3dExtension(
    'ext.flutter3d.timeline.bugReport',
    (method, parameters) async {
      final bugReport = _onService.last.bugReport;
      if (bugReport == null) return _without('a bugReport');
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
    },
    // The bug report the games build, `bugReportTape` and the run around
    // it, which the editor's `save_tape` reads back as a `.f3drun`.
    answers: const <String>{
      'version',
      'level',
      'levelHash',
      'start',
      'tape',
      'buildStamp',
      'checkpoints',
      'platform',
    },
  ),
];

String _describe(TimelineCommand command) => switch (command) {
  TimelinePaused() => 'paused',
  TimelineResumed() => 'resumed',
  TimelineStepped() => 'stepped',
  TimelineBranched(:final step) => 'branched:$step',
  TimelineLevelSwapped(:final step, :final levelDigest) =>
    'level:$step:$levelDigest',
  TimelineReplayed(:final fromStep) => 'replayed:$fromStep',
  TimelineScrubbed(:final step) => 'scrubbed:$step',
  TimelineReturned() => 'returned',
};

/// Puts [tunables] on the VM service, so an inspector can change them while
/// the game runs: `ext.flutter3d.cvar.set {name, value}` tunes one through
/// [input] — so the change is on the tape with the step that takes it — and
/// `ext.flutter3d.cvar.list` answers `{"tunables": {name: {"value",
/// "default"}}}`, every tunable with its value and its default. Under one
/// key rather than at the top, so the answer's shape is the same whatever a
/// game names its tunables, and the snapshot can hold it.
///
/// A name the table does not declare, or a value that is not a number, is
/// refused rather than dropped, so the inspector that sent it hears why.
void registerTuningExtensions(InputState input, Tunables tunables) {
  registerFlutter3dExtension('ext.flutter3d.cvar.set', (
    method,
    parameters,
  ) async {
    final name = parameters['name'];
    final value = double.tryParse(parameters['value'] ?? '');
    if (name == null || value == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'cvar.set takes a name and a numeric value',
      );
    }
    if (!tunables.defaults.containsKey(name)) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'no tunable is called $name; there are '
        '${tunables.defaults.keys.join(', ')}',
      );
    }
    input.tune(name, value);
    return developer.ServiceExtensionResponse.result('{}');
  });
  registerFlutter3dExtension('ext.flutter3d.cvar.list', (
    method,
    parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{
        'tunables': <String, Object?>{
          for (final MapEntry(key: name, :value) in tunables.values.entries)
            name: <String, Object?>{
              'value': value,
              'default': tunables.defaults[name],
            },
        },
      }),
    );
  });
}
