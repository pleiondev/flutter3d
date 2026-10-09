/// A match, as the orders that produced it: a seed, an entry per step, and the
/// state the first step began from.
///
/// **The same shape as `InputTape`, and not the same type — which was a
/// reading rather than a guess.** `Demo` in `flutter3d_sim` is exactly the
/// arithmetic wanted here: a level, a starting [Snapshot], and a tape. Its
/// `tape` field is typed `InputTape`, though, and its `fromJson` calls
/// `InputTape.fromJson` by name; there is no seam in either for a different
/// kind of tape. Making it generic would change a class three shipped genres
/// read, to let a fourth put something in it that none of them can play. So
/// the arithmetic is written out again here and the *exception* is shared:
/// [DemoFormatException] says the same three sentences about the same three
/// broken documents, and a reader that opens files of both kinds catches one
/// type.
///
/// What that leaves is a document with the same promise as the crypt's: fed to
/// the same simulation, from the same starting state, the tape produces the
/// same match — not approximately, to the bit that single precision has.
/// `match_test.dart` measures it on the game that ships rather than on a toy.
///
/// **It is a tape of orders, not of positions.** A recording of where everybody
/// walked would still play back after the crowd's separation changed
/// underneath it, and would therefore be a recording of nothing. This must
/// break when the step does; that is what it is for.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'orders.dart';

/// A match, as the orders that produced it.
final class OrderTape {
  /// A tape starting from dice at [seed], holding [frames] if it already has
  /// any.
  OrderTape({required this.seed, List<List<StrategyOrder>>? frames})
    : frames = frames ?? <List<StrategyOrder>>[];

  /// The generator state the match started from.
  ///
  /// Nothing in this simulation rolls a die yet — see
  /// `StrategySimulation.random` for why it is required anyway — and the seed
  /// is written down for the same reason the generator exists: the day a fight
  /// or a scattered spawn rolls one, a tape without it replays a different
  /// match and the divergence looks like a broken engine rather than like a
  /// missing number.
  final int seed;

  /// One entry per step, in order, each holding what was asked for on that
  /// step. **The index is the step number**, so an empty step is an empty list
  /// rather than a gap.
  ///
  /// A list of lists rather than a class per frame: a frame here has nothing in
  /// it but its orders, where an `InputFrame` has eight fields and a rule about
  /// which of them are transitions.
  final List<List<StrategyOrder>> frames;

  /// How many steps the match lasted.
  int get steps => frames.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'seed': seed,
    'frames': <List<Object?>>[
      for (final List<StrategyOrder> frame in frames)
        <Object?>[for (final StrategyOrder order in frame) order.toJson()],
    ],
  };

  /// A tape read back from [toJson].
  factory OrderTape.fromJson(Map<String, Object?> json) {
    final Object? frames = json['frames'];
    return OrderTape(
      seed: json.integer('seed'),
      frames: <List<StrategyOrder>>[
        if (frames is List)
          for (final Object? frame in frames)
            <StrategyOrder>[
              if (frame is List)
                for (final Object? order in frame)
                  if (order is Map)
                    orderFromJson(order.cast<String, Object?>()),
            ],
      ],
    );
  }
}

/// Writes down what was asked for, one entry per step.
///
/// Attached to a queue — `StrategySimulation.orders.recorder` — rather than
/// called by whoever runs the match, because the orders it has to catch are
/// given inside the step by policies the caller never sees. The queue calls
/// this once as it empties, which is once per step by construction.
final class OrderTapeRecorder {
  /// Starts a tape from dice at [seed].
  OrderTapeRecorder({required int seed}) : tape = OrderTape(seed: seed);

  /// What has been written so far.
  final OrderTape tape;

  /// Writes one step down. Copied rather than kept, because the list handed
  /// over is the queue's own and the queue is about to empty it.
  void record(List<StrategyOrder> given) =>
      tape.frames.add(List<StrategyOrder>.of(given));
}

/// Plays a tape back into a queue, one step at a time.
///
/// Call [applyTo] once per step, **before** the step runs and in place of
/// whatever gave the orders the first time — which for this genre means in
/// place of the policies. A replay that left the bots running would be a replay
/// in which the tape was never read: the match would come out right, and would
/// come out right with an empty tape too.
///
/// **Runs out rather than looping**, the same way an input tape does: a match
/// stepped past the end of its tape carries on with nobody giving it orders,
/// which is what happens when a player takes over from a replay.
final class OrderTapePlayback {
  /// Plays [tape].
  OrderTapePlayback(this.tape);

  /// What is being played.
  final OrderTape tape;

  int _step = 0;

  /// Which step it is about to hand over.
  int get step => _step;

  /// Whether the tape has run out.
  bool get isFinished => _step >= tape.frames.length;

  /// Hands the next step's orders to [queue].
  void applyTo(OrderQueue queue) {
    if (isFinished) return;
    queue.addAll(tape.frames[_step++]);
  }
}

/// A match, as a file somebody can send: where it started and what was asked
/// for after.
///
/// A save is a level and a [Snapshot] — where a match got to. This is the same
/// two things and an [OrderTape] — where it began and every order since. What
/// that buys is three uses of one document, which is why there is one and not
/// three: a replay at a few bytes a step rather than a crowd's poses; a match
/// that went wrong once in four thousand steps, re-run from the file rather
/// than from a description of it; and a test that plays the shipped game and
/// asserts where it ended.
///
/// ## Versioning
///
/// The same shape as the level, the snapshot and the crypt's demo: a document
/// from a newer build is refused with a sentence rather than misread, and a
/// missing field is refused rather than defaulted — a demo with no tape is not
/// a demo of a match in which nobody did anything, it is a file that was not
/// written all the way.
///
/// ## `rp-01`, written out a second time for the reason this file gives
/// itself
///
/// [levelHash], [buildStamp] and [checkpoints] are `Demo`'s own answer to "is
/// this still the match it claims to be, and can a replay of it be checked
/// rather than only watched" — see `flutter3d_sim`'s `Demo` for the fuller
/// argument. All three are required, the same strictness [tape] already had.
/// [platform] and [recordedBy] are optional, the same as there.
final class MatchDemo {
  /// A match played in [level], starting at [start], and everything asked for
  /// after that in [tape].
  const MatchDemo({
    required this.level,
    required this.levelHash,
    required this.start,
    required this.tape,
    required this.buildStamp,
    required this.checkpoints,
    this.platform,
    this.recordedBy,
    this.simulation,
    this.poses,
    this.unknown = const <String, Object?>{},
  });

  /// Bumped when an existing field changes meaning.
  ///
  /// **Two since the map's world rode in the simulation's save.** A start
  /// and the checkpoints of a version-one recording were taken of a match
  /// whose water and fires were nowhere in its state, and whose waders were
  /// held back after the step rather than in it; played now, the same tape
  /// walks the crowd differently and the checkpoints cannot agree.
  ///
  /// **That is a different simulation, not an unreadable file** (decisions 8
  /// and 9). A version-one file opens: its migration to two tags it with
  /// [preWaterSimulation], and [refusalOn] then refuses its tape with the
  /// sentence that says why, while its level, its stamp and its start are
  /// still there to be read.
  static const int formatVersion = 2;

  /// The strategy simulation a version-one match was recorded on: the one
  /// from before the map's water and fires rode in the match, which no 1.x
  /// build runs.
  static const SimulationVersion preWaterSimulation = SimulationVersion(
    genre: 'strategy',
    genreVersion: 0,
  );

  /// One step per version, `_upgrades[n - 1]` taking `n` to `n + 1`.
  ///
  /// 1 → 2 changes no field's shape; what changed is the simulation under
  /// the tape, so the step writes that down — [preWaterSimulation] — where a
  /// file that names none would otherwise be read as the current one.
  static Map<String, Object?> _toPreWater(Map<String, Object?> v1) =>
      <String, Object?>{
        ...v1,
        'simulation': v1['simulation'] ?? preWaterSimulation.toJson(),
      };

  /// A strategy match in the registry: `f3d.match`.
  ///
  /// **`.match.f3drun`**: a match is a `.f3drun` like a `Demo`, and the
  /// registry gives `.f3drun` to `f3d.run`; the longer suffix wins in
  /// `FormatRegistry.forPath`, and the envelope's `format` is what tells
  /// the two apart once a file named either way is open. The envelope is
  /// additive at version 2 — a build from before it ignores the keys.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.match',
    suffixes: <String>['.match.f3drun'],
    version: formatVersion,
    fixture: 'test/fixtures/v<N>/match.f3drun',
    migrations: <FormatMigration>[_toPreWater],
  );

  static const Set<String> _known = <String>{
    'level',
    'levelHash',
    'run',
    'tape',
    'buildStamp',
    'checkpoints',
    'platform',
    'recordedBy',
    'simulation',
    'poses',
  };

  /// The top-level keys of the file this match was read from that this
  /// build did not understand, written back as they were.
  final Map<String, Object?> unknown;

  /// The extension a match is written under — the same one `Demo` uses,
  /// because both are read the same way once opened: a `.f3drun` on disk, its
  /// contents deciding which tape type reads it back.
  static const String fileExtension = '.f3drun';

  /// The asset path of the map the match was played on.
  ///
  /// Stored and checked for the reason a save file gives: a tape played into
  /// the wrong map sends a crowd to coordinates that are real numbers there and
  /// mean nothing, and the run that follows looks like a broken simulation
  /// rather than like the wrong file.
  final String level;

  /// `contentDigestHex` of the map document this was recorded against.
  final String levelHash;

  /// The state the tape starts from, dice and fog included.
  ///
  /// A snapshot rather than a seed alone, because a recording may begin in the
  /// middle of a match — after a save was loaded, or after a player asked for
  /// one — and what it begins from is whatever the map was in at that moment.
  final Snapshot start;

  /// What was asked for, one entry per step.
  final OrderTape tape;

  /// Which build wrote this file, free text — see `Demo.buildStamp`.
  final String buildStamp;

  /// A digest every so many steps, taken while this match was recorded.
  final DigestTrace checkpoints;

  /// Which platform recorded this, free text, or null when unknown.
  final String? platform;

  /// Who recorded it, or null for anonymous.
  final String? recordedBy;

  /// Which simulation the tape was recorded in, or null for a match written
  /// before simulations had numbers — read as the first ([refusalOn]).
  final SimulationVersion? simulation;

  /// Where the match's bodies were every few steps, beside [tape] — what a
  /// viewer plays when the tape cannot be replayed. Null when none was kept.
  final PoseRecord? poses;

  /// How many steps the match lasted.
  int get steps => tape.steps;

  /// Why this match's tape will not be replayed on [running] — the
  /// `strategySimulationVersion` of this build — or null when it will.
  String? refusalOn(SimulationVersion running) =>
      (simulation ?? SimulationVersion.firstOf(running)).refusalOn(running);

  /// Throws [ReplayException], carrying [poses], when [refusalOn] has a reason.
  void checkSimulation(SimulationVersion running) {
    final String? reason = refusalOn(running);
    if (reason != null) throw ReplayException(reason, poses: poses);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(),
    'level': level,
    'levelHash': levelHash,
    'run': start.toJson(),
    'tape': tape.toJson(),
    'buildStamp': buildStamp,
    'checkpoints': checkpoints.toJson(),
    if (platform != null) 'platform': platform,
    if (recordedBy != null) 'recordedBy': recordedBy,
    if (simulation != null) 'simulation': simulation!.toJson(),
    if (poses != null) 'poses': poses!.toJson(),
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!_known.contains(key)) key: value,
  };

  /// Reads a demo, or throws a [DemoFormatException] that says why not.
  ///
  /// Throws rather than answering null, because every reason is worth a
  /// sentence: a file from a newer build can still be opened by the build that
  /// wrote it, and a file with no tape in it was cut short by whatever wrote
  /// it, and whoever is holding it deserves to be told which of the two they
  /// have.
  factory MatchDemo.fromJson(Map<String, Object?> json) =>
      _read(json, json['version']);

  static MatchDemo _read(Map<String, Object?> written, Object? version) {
    if (version is! num) {
      throw const DemoFormatException('the document has no version in it');
    }
    if (version < 1 || version != version.truncate()) {
      throw DemoFormatException('the recording names format $version');
    }
    // A newer match, a `Demo` or anything else that is not one, or a
    // `requires` this build does not know, is refused by the spec; an older
    // match is lifted through the chain.
    final Map<String, Object?> json = format.open(
      written,
      refuse: DemoFormatException.new,
    );
    final Object? level = json['level'];
    if (level is! String || level.isEmpty) {
      throw const DemoFormatException('the recording names no map');
    }
    final Object? levelHash = json['levelHash'];
    if (levelHash is! String || levelHash.isEmpty) {
      throw const DemoFormatException(
        'the recording names no map hash, so it cannot say whether the map '
        'has changed since it was recorded',
      );
    }
    final Object? run = json['run'];
    if (run is! Map) {
      throw const DemoFormatException('the recording has no starting state');
    }
    final Object? tape = json['tape'];
    if (tape is! Map) {
      throw const DemoFormatException(
        'the recording has no tape, so it was not written all the way',
      );
    }
    final Object? buildStamp = json['buildStamp'];
    if (buildStamp is! String || buildStamp.isEmpty) {
      throw const DemoFormatException('the recording names no build stamp');
    }
    final Object? checkpoints = json['checkpoints'];
    if (checkpoints is! Map) {
      throw const DemoFormatException(
        'the recording has no checkpoints, so a replay of it cannot be '
        'verified',
      );
    }
    final Snapshot start;
    try {
      start = Snapshot.fromJson(run.cast<String, Object?>());
    } on SnapshotFormatException catch (error) {
      throw DemoFormatException('the starting state: ${error.message}');
    }
    final DigestTrace trace;
    try {
      trace = DigestTrace.fromJson(checkpoints.cast<String, Object?>());
    } on DigestTraceFormatException catch (error) {
      throw DemoFormatException('the checkpoints: ${error.message}');
    }
    final Object? platform = json['platform'];
    final Object? recordedBy = json['recordedBy'];
    final SimulationVersion? simulation;
    final PoseRecord? poses;
    try {
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
    return MatchDemo(
      level: level,
      levelHash: levelHash,
      start: start,
      tape: OrderTape.fromJson(tape.cast<String, Object?>()),
      buildStamp: buildStamp,
      checkpoints: trace,
      platform: platform is String ? platform : null,
      recordedBy: recordedBy is String ? recordedBy : null,
      simulation: simulation,
      poses: poses,
      unknown: FormatDocument.unknownIn(json, known: _known),
    );
  }
}
