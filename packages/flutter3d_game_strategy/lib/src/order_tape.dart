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

import 'package:flutter3d_game/flutter3d_game.dart';

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
final class MatchDemo {
  /// A match played in [level], starting at [start], and everything asked for
  /// after that in [tape].
  const MatchDemo({
    required this.level,
    required this.start,
    required this.tape,
  });

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  /// The asset path of the map the match was played on.
  ///
  /// Stored and checked for the reason a save file gives: a tape played into
  /// the wrong map sends a crowd to coordinates that are real numbers there and
  /// mean nothing, and the run that follows looks like a broken simulation
  /// rather than like the wrong file.
  final String level;

  /// The state the tape starts from, dice and fog included.
  ///
  /// A snapshot rather than a seed alone, because a recording may begin in the
  /// middle of a match — after a save was loaded, or after a player asked for
  /// one — and what it begins from is whatever the map was in at that moment.
  final Snapshot start;

  /// What was asked for, one entry per step.
  final OrderTape tape;

  /// How many steps the match lasted.
  int get steps => tape.steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': formatVersion,
    'level': level,
    'run': start.toJson(),
    'tape': tape.toJson(),
  };

  /// Reads a demo, or throws a [DemoFormatException] that says why not.
  ///
  /// Throws rather than answering null, because every reason is worth a
  /// sentence: a file from a newer build can still be opened by the build that
  /// wrote it, and a file with no tape in it was cut short by whatever wrote
  /// it, and whoever is holding it deserves to be told which of the two they
  /// have.
  factory MatchDemo.fromJson(Map<String, Object?> json) {
    final Object? version = json['version'];
    if (version is! num) {
      throw const DemoFormatException('the document has no version in it');
    }
    if (version > formatVersion) {
      throw DemoFormatException(
        'the match was recorded by a newer build (format $version, this build '
        'reads $formatVersion)',
      );
    }
    final Object? level = json['level'];
    if (level is! String || level.isEmpty) {
      throw const DemoFormatException('the recording names no map');
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
    final Snapshot start;
    try {
      start = Snapshot.fromJson(run.cast<String, Object?>());
    } on SnapshotFormatException catch (error) {
      throw DemoFormatException('the starting state: ${error.message}');
    }
    return MatchDemo(
      level: level,
      start: start,
      tape: OrderTape.fromJson(tape.cast<String, Object?>()),
    );
  }
}
