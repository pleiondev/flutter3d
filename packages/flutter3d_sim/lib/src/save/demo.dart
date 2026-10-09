import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        Flutter3dFormatException,
        FormatDocument,
        FormatMigration,
        FormatSpec,
        SimulationVersion;

import '../input/input_tape.dart';
import '../level/level.dart';
import '../loop/loop_change.dart';
import 'data_source_trace.dart';
import 'event_trace.dart';
import 'pose_record.dart';
import 'simulation_version.dart';
import 'snapshot.dart';
import 'state_digest.dart';

/// A run, as a file somebody can send: where it started and what they did.
///
/// **A save plus a tape, and that arithmetic is the design.** A save is a level
/// and a [Snapshot] — where the player got to. A demo is the same two things
/// and an [InputTape] — where they started and everything they did after. Fed
/// to the same simulation the tape produces the same run, exactly, which is
/// what ARCHITECTURE.md §9.3 promises and `input_tape_test.dart` measures.
///
/// One document rather than two mechanisms, for the reason `snapshot.dart`
/// gives for itself: a replay, the input to a determinism test and the file
/// attached to a bug report are the same bytes in three uses, and keeping
/// three of those right costs three times what keeping one right costs.
///
/// **What it is for**, in the order the games will use it:
///
/// * a bug that happens once in a thousand steps, reproduced from the file the
///   player attached rather than from their description of it;
/// * a test that plays a whole level and asserts where it ended, written by
///   playing the level once;
/// * a replay, at a few bytes a step rather than a pose per body per step.
///
/// **It is not a recording of positions.** The racing game's ghost is that,
/// and is right to be — it has to survive the physics changing underneath it.
/// This must not: a demo that still reached the exit after the collision
/// changed would be a recording of nothing.
///
/// ## Versioning
///
/// The same shape as the level and the snapshot: a document from a newer
/// build is refused with a sentence rather than misread, and a missing field
/// is refused rather than defaulted, because a demo with no tape is not a
/// demo with an empty tape — it is a file that was not written all the way.
///
/// ## `rp-01`: what a run needs to be verified, not only replayed
///
/// [levelHash] and [buildStamp] answer "is this still the run it claims to
/// be" — a tape played into a level that has since been edited walks into
/// geometry that is not there any more, and a bug reproduced on a different
/// build may be reproducing a bug that was already fixed. [checkpoints] is
/// what turns "replayed to the end" into "replayed to the bit": the same
/// [DigestTrace] `rp-00`'s parity files compare platforms with, taken while
/// this run was recorded, so that a replay's own trace can be checked
/// against it rather than merely watched. All three are required, the same
/// strictness [tape] already had — a run nobody can verify is a run that
/// silently degrades to a video. [platform] and [recordedBy] are the
/// genuinely optional half: worth keeping when known, meaningless to invent
/// when not.
///
/// ## `HR3`: a level edited under the run
///
/// [levelSwaps] are the edits the editor sent into the game while this run
/// was recorded, each with the whole document and the step it took effect
/// before. Without them a run with an edit in it parts from its own replay at
/// the edit, and the checkpoints say so without saying why.
///
/// ## Decision 9: the simulation, and the poses beside the tape
///
/// [simulation] says which simulation the tape was recorded in, and
/// [refusalOn] compares it with the one a build runs: a tape of intents
/// from another simulation is refused before a step is played, with the
/// sentence that says so, rather than replayed into a divergence that reads
/// like a bug. [poses] is the record written beside the tape — where the
/// bodies were every few steps — which means the same thing on every build,
/// so a viewer draws it whenever the tape cannot be replayed.
///
/// Both are additive, like [platform]: an older reader ignores them, and a
/// run without [simulation] was written before simulations had numbers and
/// is read as version 1, the simulation 1.0.0 shipped
/// ([SimulationVersion.firstOf]).
final class Demo {
  const Demo({
    required this.level,
    required this.levelHash,
    required this.start,
    required this.tape,
    required this.buildStamp,
    required this.checkpoints,
    this.platform,
    this.recordedBy,
    this.dataSources,
    this.levelSwaps = const <DemoLevelSwap>[],
    this.physics,
    this.loopChanges = const <LoopChange>[],
    this.events,
    this.simulation,
    this.poses,
    this.unknown = const <String, Object?>{},
  });

  /// Bumped when an existing field changes meaning.
  ///
  /// **2 is written only by a run with [levelSwaps] in it.** A build that
  /// reads 1 would play such a file through the first level to the end and
  /// report a divergence nobody can explain; refusing it with "a newer build"
  /// is the honest answer. A run with no edit in it means exactly what it
  /// meant before, so it is still written as 1 and older builds still open
  /// it.
  ///
  /// **3 is written only by a run with a [loopChanges] entry that changes
  /// the simulation** — a simulation plugin switched mid-run, a step rate
  /// changed — for the same reason: an older build would play through it
  /// as if nothing had changed. A run whose loop changes only pace or
  /// decorate it (a time scale, a view plugin), and a run with an [events]
  /// trace, is written at the version it would have had without them; an
  /// older build ignores the fields and plays it correctly.
  ///
  /// **4 is written only by a run whose [tape] is at version 2** — one that
  /// recorded an [AxisAction] or a [DualAxisAction] beyond moving and
  /// looking (`InputTape.writtenVersion`). An older build would drop those
  /// values and replay the run with the axis at rest.
  static const int formatVersion = 4;

  /// The extension a run is written under — `.f3drun`, wherever it becomes an
  /// actual file: attached to a bug report, downloaded from the cloud, or
  /// dropped on an editor window.
  static const String fileExtension = '.f3drun';

  /// The run format in the registry: `f3d.run`.
  ///
  /// **The envelope is additive.** `format`, `requires` and `generator` are
  /// keys a build from before them ignores, so a run is still written at
  /// [writtenVersion] and opens wherever it opened before.
  ///
  /// The simulation the tape was recorded in is not this number: it is
  /// [SimulationVersion.engineVersion] (and a genre's own), written in the
  /// run's `simulation` field. This number is the file's shape; that one is
  /// whether the tape still plays.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.run',
    version: formatVersion,
    suffixes: <String>[fileExtension],
    fixture: 'test/fixtures/v<N>/run.f3drun',
    migrations: <FormatMigration>[_identity, _identity, _identity],
  );

  /// The keys this reader takes; everything else in a run is [unknown].
  static const Set<String> _known = <String>{
    'level',
    'levelHash',
    'run',
    'tape',
    'buildStamp',
    'checkpoints',
    'platform',
    'recordedBy',
    'physics',
    'dataSources',
    'levelSwaps',
    'loopChanges',
    'events',
    'simulation',
    'poses',
  };

  /// The top-level keys of the file this run was read from that this build
  /// did not understand, written back as they were — a run a later minor
  /// wrote survives being opened and attached again here.
  final Map<String, Object?> unknown;

  /// The asset path of the level the run was played in.
  ///
  /// Stored and checked for the reason `SaveFile` gives: a tape played into
  /// the wrong level walks the player into a wall, and the positions that
  /// follow are real numbers that mean nothing there.
  final String level;

  /// [Level.digestHex] of the level this was recorded against.
  ///
  /// Checked rather than assumed the moment a level might have changed
  /// underneath a tape — `rp-03`'s whole reason for existing. A path staying
  /// the same says nothing about the content behind it; this does.
  final String levelHash;

  /// The state the tape starts from, dice included.
  ///
  /// A snapshot rather than a seed alone: a demo may begin mid-run, after a
  /// save was restored, and the state it begins from is whatever the level was
  /// in at that moment — not a fresh level with a fresh generator.
  final Snapshot start;

  /// What the player did, one entry per fixed step.
  final InputTape tape;

  /// Which build wrote this file, free text.
  ///
  /// `sim` has no opinion on what a build number looks like on any platform
  /// it runs on — a package version, a git commit, a CI run id — the caller's
  /// own name for itself is whatever goes here.
  final String buildStamp;

  /// A digest every so many steps, taken while this run was recorded.
  final DigestTrace checkpoints;

  /// Which platform recorded this, free text — `'macos'`, `'chrome'`,
  /// `'android'` — or null when the caller does not know or does not say.
  final String? platform;

  /// Who recorded it — an account name, a player id — or null for anonymous.
  final String? recordedBy;

  /// The [PhysicsBackend] it was recorded on — `'native'` or `'dart'` — and
  /// so the one it replays on: the two are not promised to agree, each only
  /// with itself. Null for a run recorded before this was written, which a
  /// replay plays on whatever the run is on.
  final String? physics;

  /// `edu-05`: every `edu_data_source` this run read, one entry per fixed
  /// step it was read at — null for a run that bound none, the same
  /// genuinely-optional shape [platform]/[recordedBy] already have. Additive
  /// like they are: an older reader ignoring a field it never knew is a run
  /// with no recorded bindings, not a run misread.
  final DataSourceTrace? dataSources;

  /// The levels put under the run while it was recorded, in step order, no
  /// two at the same step. Empty for a run played in one level throughout.
  ///
  /// [level] and [levelHash] still name the level the run started in: that
  /// is the one a replay loads, and these are swapped in as the tape reaches
  /// them.
  final List<DemoLevelSwap> levelSwaps;

  /// What changed about the loop while the run was recorded — the time
  /// scale, the step rate, plugins switched or reordered — each at the step
  /// of this tape it was made before, in step order. A replay schedules them
  /// (`EngineLoop.schedule`) and makes them at the same steps.
  final List<LoopChange> loopChanges;

  /// Each step's event digest, taken live. Null for a run recorded without
  /// the bus. A replay compares its own and names the first step whose
  /// events differ.
  final EventTrace? events;

  /// Which simulation the tape was recorded in, or null for a run written
  /// before simulations had numbers — read as the first ([refusalOn]).
  final SimulationVersion? simulation;

  /// Where the run's bodies were every few steps, written beside [tape]: the
  /// part of the file that plays on any build. Null for a run recorded
  /// without one.
  final PoseRecord? poses;

  /// How many fixed steps the run lasted.
  int get steps => tape.steps;

  /// Why this run's tape will not be replayed on [running], or null when it
  /// will. A run that names no simulation is taken as the first of
  /// [running]'s genre.
  String? refusalOn(SimulationVersion running) =>
      (simulation ?? SimulationVersion.firstOf(running)).refusalOn(running);

  /// Throws [ReplayException] — carrying [poses] for a viewer to show instead
  /// — when this run's tape will not be replayed on [running].
  void checkSimulation(SimulationVersion running) {
    final reason = refusalOn(running);
    if (reason != null) throw ReplayException(reason, poses: poses);
  }

  /// The version this run is written at: the lowest that says what it
  /// holds, so an older build opens every run it can play correctly.
  int get writtenVersion => tape.writtenVersion > 1
      ? 4
      : loopChanges.any((c) => c.affectsSimulation)
      ? 3
      : levelSwaps.isEmpty
      ? 1
      : 2;

  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(version: writtenVersion),
    'level': level,
    'levelHash': levelHash,
    'run': start.toJson(),
    'tape': tape.toJson(),
    'buildStamp': buildStamp,
    'checkpoints': checkpoints.toJson(),
    if (platform != null) 'platform': platform,
    if (recordedBy != null) 'recordedBy': recordedBy,
    if (physics != null) 'physics': physics,
    if (dataSources != null) 'dataSources': dataSources!.toJson(),
    if (levelSwaps.isNotEmpty)
      'levelSwaps': <Map<String, Object?>>[
        for (final swap in levelSwaps) swap.toJson(),
      ],
    if (loopChanges.isNotEmpty)
      'loopChanges': <Map<String, Object?>>[
        for (final change in loopChanges) change.toJson(),
      ],
    if (events != null) 'events': events!.toJson(),
    if (simulation != null) 'simulation': simulation!.toJson(),
    if (poses != null) 'poses': poses!.toJson(),
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!_known.contains(key)) key: value,
  };

  /// One step per version, each taking a document of that version to the
  /// next: entry `n - 1` reads `n` and writes `n + 1`.
  ///
  /// **Identities, and kept as steps anyway.** 2 added the level swaps, 3
  /// the loop changes that change the simulation and 4 is the tape's own
  /// version 2, which the tape reads by itself; none changed what an older
  /// field means, so an older document already is a newer one. The chain is
  /// here so that the day a field does change meaning, its migration has a
  /// place to go and every older version reaches it through the steps after
  /// its own (decision 8).
  static Map<String, Object?> _identity(Map<String, Object?> document) =>
      document;

  /// Reads a demo, or throws a [DemoFormatException] that says why not.
  ///
  /// Throws rather than returning null, because every reason is worth a
  /// sentence: a demo from a newer build can still be opened by the build that
  /// wrote it, and a file with no tape in it was cut short by whatever wrote
  /// it, and the player who attached it deserves to be told which.
  factory Demo.fromJson(Map<String, Object?> json) =>
      _read(json, json['version']);

  static Demo _read(Map<String, Object?> written, Object? version) {
    if (version is! num) {
      throw const DemoFormatException('the document has no version in it');
    }
    if (version < 1 || version != version.truncate()) {
      throw DemoFormatException('the demo names format $version');
    }
    // Another format's document, a newer version or a `requires` this build
    // does not know is refused by the spec with the reason; an older version
    // is lifted through the chain.
    final json = format.open(written, refuse: DemoFormatException.new);
    final level = json['level'];
    if (level is! String || level.isEmpty) {
      throw const DemoFormatException('the demo names no level');
    }
    final levelHash = json['levelHash'];
    if (levelHash is! String || levelHash.isEmpty) {
      throw const DemoFormatException(
        'the demo names no level hash, so it cannot say whether the level '
        'has changed since it was recorded',
      );
    }
    final run = json['run'];
    if (run is! Map<String, Object?>) {
      throw const DemoFormatException('the demo has no starting state');
    }
    final tape = json['tape'];
    if (tape is! Map<String, Object?>) {
      throw const DemoFormatException(
        'the demo has no tape, so it was not written all the way',
      );
    }
    final buildStamp = json['buildStamp'];
    if (buildStamp is! String || buildStamp.isEmpty) {
      throw const DemoFormatException('the demo names no build stamp');
    }
    final checkpoints = json['checkpoints'];
    if (checkpoints is! Map<String, Object?>) {
      throw const DemoFormatException(
        'the demo has no checkpoints, so a replay of it cannot be verified',
      );
    }
    final Snapshot start;
    try {
      start = Snapshot.fromJson(run);
    } on SnapshotFormatException catch (error) {
      throw DemoFormatException('the starting state: ${error.message}');
    }
    final DigestTrace trace;
    try {
      trace = DigestTrace.fromJson(checkpoints);
    } on DigestTraceFormatException catch (error) {
      throw DemoFormatException('the checkpoints: ${error.message}');
    }
    final platform = json['platform'];
    final recordedBy = json['recordedBy'];
    final physics = json['physics'];
    final rawDataSources = json['dataSources'];
    DataSourceTrace? dataSources;
    if (rawDataSources is Map<String, Object?>) {
      try {
        dataSources = DataSourceTrace.fromJson(rawDataSources);
      } on DataSourceTraceFormatException catch (error) {
        throw DemoFormatException('the data sources: ${error.message}');
      }
    }
    final InputTape readTape;
    try {
      readTape = InputTape.fromJson(tape);
    } on Flutter3dFormatException catch (error) {
      throw DemoFormatException('the tape: ${error.message}');
    }
    final List<LoopChange> loopChanges;
    final EventTrace? events;
    final SimulationVersion? simulation;
    final PoseRecord? poses;
    try {
      loopChanges = _readLoopChanges(json['loopChanges']);
      events = switch (json['events']) {
        null => null,
        final Map<String, Object?> trace => EventTrace.fromJson(trace),
        _ => throw const DemoFormatException(
          'the event trace is not a document',
        ),
      };
      simulation = switch (json['simulation']) {
        null => null,
        final Map<String, Object?> named => SimulationVersion.fromJson(named),
        _ => throw const DemoFormatException(
          'the simulation is not a document',
        ),
      };
      poses = switch (json['poses']) {
        null => null,
        final Map<String, Object?> record => PoseRecord.fromJson(record),
        _ => throw const DemoFormatException(
          'the pose record is not a document',
        ),
      };
    } on Flutter3dFormatException catch (error) {
      throw DemoFormatException(error.message);
    }
    return Demo(
      level: level,
      levelHash: levelHash,
      start: start,
      tape: readTape,
      buildStamp: buildStamp,
      checkpoints: trace,
      platform: platform is String ? platform : null,
      recordedBy: recordedBy is String ? recordedBy : null,
      physics: physics is String ? physics : null,
      dataSources: dataSources,
      levelSwaps: _readSwaps(json['levelSwaps'], steps: readTape.steps),
      loopChanges: loopChanges,
      events: events,
      simulation: simulation,
      poses: poses,
      unknown: FormatDocument.unknownIn(json, known: _known),
    );
  }

  static List<LoopChange> _readLoopChanges(Object? raw) {
    if (raw == null) return const <LoopChange>[];
    if (raw is! List) {
      throw const DemoFormatException('the loop changes are not a list');
    }
    final changes = <LoopChange>[
      for (final entry in raw) LoopChange.fromJson(entry),
    ];
    for (var i = 1; i < changes.length; i++) {
      if (changes[i].step < changes[i - 1].step) {
        throw DemoFormatException(
          'the loop change at step ${changes[i].step} comes after the one at '
          'step ${changes[i - 1].step}; loop changes are written in step order',
        );
      }
    }
    return List<LoopChange>.unmodifiable(changes);
  }

  static List<DemoLevelSwap> _readSwaps(Object? raw, {required int steps}) {
    if (raw == null) return const <DemoLevelSwap>[];
    if (raw is! List) {
      throw const DemoFormatException('the level swaps are not a list');
    }
    final swaps = <DemoLevelSwap>[
      for (final entry in raw) DemoLevelSwap._fromJson(entry, steps: steps),
    ];
    for (var i = 1; i < swaps.length; i++) {
      if (swaps[i].step <= swaps[i - 1].step) {
        throw DemoFormatException(
          'the level swap at step ${swaps[i].step} comes after the one at '
          'step ${swaps[i - 1].step}; swaps are written in step order, one '
          'per step',
        );
      }
    }
    return List<DemoLevelSwap>.unmodifiable(swaps);
  }
}

/// One level put under a recorded run: [level] took effect before step
/// [step] of the tape, that is, after [step] of its frames had been played.
///
/// **The whole document, not only its digest.** The level a game was edited
/// into exists in the editor that sent it and nowhere a replay can look it
/// up — not in the game's assets, which still hold the level as shipped. A
/// digest alone would make the file unplayable everywhere but the machine
/// that recorded it, on the afternoon it was recorded.
final class DemoLevelSwap {
  const DemoLevelSwap({required this.step, required this.level});

  final int step;
  final Level level;

  /// [Level.digestHex] of [level], what the editor and the timeline call it.
  String get levelHash => level.digestHex;

  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    'levelHash': levelHash,
    'document': level.toJson(),
  };

  /// **The digest is checked against the document**, as
  /// `ext.flutter3d.level.apply` checks it: a document that no longer
  /// digests to what was written beside it is not the level the run was
  /// played in.
  factory DemoLevelSwap._fromJson(Object? json, {required int steps}) {
    if (json is! Map<String, Object?>) {
      throw const DemoFormatException('a level swap is not a document');
    }
    final step = json['step'];
    if (step is! int || step < 0 || step > steps) {
      throw DemoFormatException(
        'a level swap names step $step, and the tape has steps 0 to $steps',
      );
    }
    final hash = json['levelHash'];
    final document = json['document'];
    if (hash is! String || document is! Map<String, Object?>) {
      throw DemoFormatException(
        'the level swap at step $step has no level hash or no document',
      );
    }
    final Level level;
    try {
      level = Level.fromJson(document);
    } on LevelFormatException catch (error) {
      throw DemoFormatException(
        'the level swapped in at step $step: ${error.message}',
      );
    }
    if (level.digestHex != hash) {
      throw DemoFormatException(
        'the level swapped in at step $step digests to ${level.digestHex}, '
        'not $hash; the document changed after it was written',
      );
    }
    return DemoLevelSwap(step: step, level: level);
  }
}

/// Thrown when a demo cannot be read at all.
final class DemoFormatException extends Flutter3dFormatException {
  const DemoFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'DemoFormatException: $message';
}
