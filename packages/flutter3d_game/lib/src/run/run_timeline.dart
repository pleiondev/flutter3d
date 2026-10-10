import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'run_part.dart';

/// One action taken on a [RunTimeline], kept so a caller can show a history:
/// every command is visible in it, and it is the same log an MCP command
/// stream would replay.
///
/// **Sealed on purpose: it is a protocol.** The timeline, its VM service
/// extensions and a history view each answer every command, exhaustively; a
/// command one of them did not know would be a step of history that could
/// not be shown or replayed. A new command is a new version of the
/// protocol, and waits for a major.
sealed class TimelineCommand {
  const TimelineCommand();
}

/// The run was paused.
final class TimelinePaused extends TimelineCommand {
  const TimelinePaused();
}

/// The run was resumed from a pause.
final class TimelineResumed extends TimelineCommand {
  const TimelineResumed();
}

/// One fixed step was taken while paused.
final class TimelineStepped extends TimelineCommand {
  const TimelineStepped();
}

/// The run was rewound to [step] and released — everything after [step] in
/// the buffer was cut, and the run continues from there.
final class TimelineBranched extends TimelineCommand {
  const TimelineBranched(this.step);
  final int step;

  @override
  bool operator ==(Object other) =>
      other is TimelineBranched && other.step == step;

  @override
  int get hashCode => step.hashCode;
}

/// The live state was moved to the state before [step] to be looked at; the
/// tape and the present are kept, and nothing has branched yet.
final class TimelineScrubbed extends TimelineCommand {
  const TimelineScrubbed(this.step);
  final int step;

  @override
  bool operator ==(Object other) =>
      other is TimelineScrubbed && other.step == step;

  @override
  int get hashCode => step.hashCode;
}

/// A scrub was left, and the present put back as it was.
final class TimelineReturned extends TimelineCommand {
  const TimelineReturned();
}

/// The level under the run was replaced, taking effect before [step]: the
/// run was replayed from there under the level whose document digests to
/// [levelDigest] (`Level.digestHex`).
///
/// **What makes a run with an edit in it reproducible.** A tape replayed
/// against the old level from the start would part from this run at [step];
/// with this command in hand, a replay swaps the level at the same step and
/// arrives where the run did.
final class TimelineLevelSwapped extends TimelineCommand {
  const TimelineLevelSwapped(this.step, this.levelDigest);
  final int step;
  final String levelDigest;

  @override
  bool operator ==(Object other) =>
      other is TimelineLevelSwapped &&
      other.step == step &&
      other.levelDigest == levelDigest;

  @override
  int get hashCode => Object.hash(step, levelDigest);
}

/// The last seconds were lived again under new code, from [fromStep] to the
/// present — `RunTimeline.replayUnderNewCode`.
final class TimelineReplayed extends TimelineCommand {
  const TimelineReplayed(this.fromStep);
  final int fromStep;

  @override
  bool operator ==(Object other) =>
      other is TimelineReplayed && other.fromStep == fromStep;

  @override
  int get hashCode => fromStep.hashCode;
}

/// Where the run new code makes first parts from the one old code made.
///
/// **Between two keyframes, not at one step.** The old run is held as a
/// snapshot a keyframe interval apart and the tape between; what it was at
/// the steps between keyframes is gone. So this names the last step the two
/// runs were seen to agree ([agreedAt]) and the first they were seen to differ
/// ([step]), and the first field that differed there. Closer keyframes narrow
/// it; `RewindBuffer.keyframeEvery` is the dial.
final class ReplayDivergence {
  const ReplayDivergence({
    required this.agreedAt,
    required this.step,
    required this.path,
    required this.before,
    required this.after,
  });

  /// The last step both runs were compared at and agreed.
  final int agreedAt;

  /// The first step they were compared at and differed.
  final int step;

  /// Where in the snapshot, as `firstDifferingPath` spells it.
  final String path;

  /// The value under the old code.
  final Object? before;

  /// The value under the new code.
  final Object? after;

  Map<String, Object?> toJson() => <String, Object?>{
    'agreedAt': agreedAt,
    'step': step,
    'path': path,
    'before': before,
    'after': after,
  };

  @override
  String toString() =>
      'between step $agreedAt and $step, `$path` went from $before to $after';
}

/// What `RunTimeline.replayUnderNewCode` did.
final class CodeReplay {
  const CodeReplay({
    required this.fromStep,
    required this.toStep,
    this.divergence,
  });

  final int fromStep;
  final int toStep;

  /// Null when the new code made the same run as the old.
  final ReplayDivergence? divergence;

  Map<String, Object?> toJson() => <String, Object?>{
    'fromStep': fromStep,
    'toStep': toStep,
    'divergence': divergence?.toJson(),
  };
}

/// What [RunTimeline.scrubTo] and [RunTimeline.branchHere] answered.
///
/// **Sealed on purpose**: a result, every case of which a caller has to
/// handle — a scrub that landed and one that was refused say different
/// things to the person holding the slider.
sealed class ScrubAnswer {
  const ScrubAnswer();

  Map<String, Object?> toJson();
}

/// The live state is now the state before [step].
final class ScrubMoved extends ScrubAnswer {
  const ScrubMoved(this.step);
  final int step;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'moved': true,
    'step': step,
  };
}

/// Nothing moved, and [reason] says why and what to do instead.
final class ScrubRefused extends ScrubAnswer {
  const ScrubRefused(this.reason);
  final String reason;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'moved': false,
    'refusal': reason,
  };

  @override
  String toString() => reason;
}

/// Pause, step, rewind and branch, built on a live [RewindBuffer] and the
/// [EngineLoop] it is attached to.
///
/// **What `rp-02`'s editor panel is a face for, not the panel itself.** The
/// scrubber, the checkpoint marks and the buttons above `RunPlaying` are
/// `apps/flutter3d_editor`'s to draw; this is the part underneath that a
/// panel calls into and that a test can drive without one — the same split
/// `WidgetSurfacePipeline` drew for `wg-00`, mechanism proven before the
/// widget that shows it.
///
/// ## Through the loop's snapshots, the one path
///
/// The buffer is attached to the loop (`RewindBuffer.attach`), so each of its
/// keyframes is the loop's own capture — the world, the genre's run, every
/// part a plugin added — and this restores one through `EngineLoop.rewindTo`
/// and plays the recorded input on through `EngineLoop.runSteps`, with the
/// tape as the loop's `playback`, the live devices muted, and each replayed
/// step marked resimulated, so it is neither recorded again nor heard twice.
/// Before 1.0 a timeline was handed a step function and a restore function of
/// the game's own, which restored the genre's run and left everything beside
/// it — the elements, a plugin's state, the loop's step count — where it was.
///
/// **Two counts, kept in step.** The buffer counts the steps it recorded, the
/// loop the steps it ran; they move together while the run is live, and the
/// difference between them is taken when a rewind starts, so every keyframe
/// is restored at the loop step it was captured at and the loop's count is
/// where the buffer's says after a release, a scrub, a return or a swap.
///
/// ## The kill camera, generalised
///
/// `apps/flutter3d_demo_dungeon/lib/main.dart`'s kill camera already does
/// exactly this — restore a keyframe, mute the devices, play the tape forward
/// through the ordinary step, unmute — for one fixed distance (three seconds)
/// and one purpose (a camera that does not take over play). [releaseAt] is
/// that with the distance and the purpose both handed to the caller: after it
/// returns, the live state *is* the rewound moment and the run goes on from
/// there rather than snapping back, which is what turns a kill camera into a
/// branch.
///
/// ## What this does not do
///
/// It does not write a `.f3drun`. [RewindBuffer.cut] leaves its own recorder
/// holding exactly the frames from the branch point onward, the same
/// `InputTapeRecorder` a `DemoRecording` already knows how to turn into a
/// [Demo] — a second way to do that would be a second thing to keep right.
/// It does not scrub across a *loaded* `.f3drun`'s whole length either — that
/// is `rewindBufferFromDemo`, which builds a buffer this can then scrub.
final class RunTimeline {
  /// A timeline over [rewind], which must be attached to [loop]
  /// (`rewind.attach(loop)`): its recorder writes the loop's live steps and
  /// its keyframes are the loop's captures.
  RunTimeline({required this.rewind, required this.loop});

  /// Where the recent past is kept, and what [releaseAt] cuts.
  final RewindBuffer rewind;

  /// The loop the run is stepped in, whose snapshots every rewind restores
  /// and whose steps every replay runs.
  final EngineLoop loop;

  /// The live devices — the loop's — muted while a replay plays.
  InputState get input => loop.input;

  /// The fixed step, in seconds: the loop's.
  double get stepSeconds => loop.stepSeconds;

  bool _paused = false;

  /// Whether [stepOnce] may be called — the transport is paused rather than
  /// running live.
  bool get isPaused => _paused;

  final List<TimelineCommand> _history = <TimelineCommand>[];

  /// Every command this timeline has carried out, oldest first.
  List<TimelineCommand> get history =>
      List<TimelineCommand>.unmodifiable(_history);

  void pause() {
    if (_paused) return;
    _paused = true;
    _history.add(const TimelinePaused());
  }

  /// Lets the run go on. From a scrub, the present is put back first: the
  /// run resumes where it was paused, and going on from the scrubbed moment
  /// instead is [branchHere], asked for by name.
  void resume() {
    if (!_paused) return;
    returnToPresent();
    _paused = false;
    _history.add(const TimelineResumed());
  }

  /// Runs one fixed step of the loop. Only while [isPaused] — a step taken on
  /// a running timeline would be a second step nobody asked for, on top of
  /// whatever is driving the loop already.
  ///
  /// At the present it is a live step, recorded into the buffer like any
  /// other. From a scrub it moves the scrub one step along the tape rather
  /// than stepping the simulation off it, so "step" in a debugger walks the
  /// recorded run; at the present the scrub ends.
  void stepOnce() {
    if (!_paused) {
      throw StateError('stepOnce is only valid while the timeline is paused');
    }
    final at = _scrubbedAt;
    if (at != null) {
      _scrubForward(at + 1);
      _history.add(const TimelineStepped());
      return;
    }
    loop.runSteps(1);
    _history.add(const TimelineStepped());
  }

  /// Where a scrub to [secondsAgo] would land, without moving anything —
  /// what a scrubber previews as a person drags it, before they let go.
  RewindPoint? preview(double secondsAgo) => rewind.rewindBy(secondsAgo);

  /// Rewinds the live state to [point] and lets the run continue from there:
  /// what a person asked for by dragging the scrubber to [point] and letting
  /// go.
  ///
  /// Restores [point]'s keyframe through the loop, replays the frames from
  /// there to [point] with the live devices muted — so a key held during the
  /// drag does not leak into the replay — then [RewindBuffer.cut]s the buffer
  /// at [point]. The timeline is left running (not paused): a release is
  /// asking to keep playing from here, not to pause on arrival — call [pause]
  /// afterwards for that.
  void releaseAt(RewindPoint point) {
    final offset = _offset;
    _forgetScrub();
    _restoreKeyframe(point, offset);
    _play(point.frames.sublist(0, point.replayed), point.seed);
    rewind.cut(point);
    _paused = false;
    _history.add(TimelineBranched(point.step));
  }

  /// Replaces the level under the run without the run jumping: [swap] puts
  /// the new level in place, and the steps since the last keyframe are lived
  /// again under it, so the present is one the new level could have led to.
  ///
  /// **For the half of an edit the simulation reads** — brushes, entities,
  /// the ground (`LevelDiff.simulation`). Swapped in place, a crate moved in
  /// the editor would teleport mid-run, and nothing replaying the tape could
  /// reach that state. Swapped here, the keyframe is restored, [swap] runs,
  /// and the recorded input plays forward with the live devices muted, as
  /// [releaseAt] plays it; at most one keyframe interval is replayed. The
  /// buffer is then rebased on that keyframe (`RewindBuffer.rebaseAt`),
  /// since nothing held on either side of it belongs to the new level.
  ///
  /// [swap] must replace only what the snapshots do not carry — the level,
  /// its colliders, what it spawned at load — and leave what they do carry to
  /// the restore. With no keyframe yet held, [swap] runs at once, as at the
  /// first step of a run.
  ///
  /// Returns the step the new level took effect before, which is what
  /// [TimelineLevelSwapped] records.
  int swapLevel(void Function() swap, {required String levelDigest}) {
    returnToPresent();
    final point = rewind.rewindTo(rewind.step);
    if (point == null) {
      swap();
      _history.add(TimelineLevelSwapped(rewind.step, levelDigest));
      return rewind.step;
    }
    _restoreKeyframe(point, _offset);
    swap();
    _play(point.frames.sublist(0, point.replayed), point.seed);
    rewind.rebaseAt(point);
    final at = point.step - point.replayed;
    _history.add(TimelineLevelSwapped(at, levelDigest));
    return at;
  }

  /// Lives the last [seconds] again under the code running now, and says
  /// where that run parts from the one the old code made.
  ///
  /// **What a code reload is worth to a simulation.** A hot reload swaps the
  /// step function and keeps the state, so the run carries on under new code
  /// from a present the old code made. That is enough to see the new code
  /// running and not enough to see what it changes. This goes back to the
  /// keyframe at or before [seconds] ago, replays the recorded input to the
  /// present under the new code with the devices muted, and compares the
  /// loop's capture at each keyframe the old run left — and at the present,
  /// captured before anything moves — against what the replay reaches there.
  /// The first that differs is the [ReplayDivergence], its path into the
  /// capture prefixed by the part it is in (`world.data.…`, a genre's id);
  /// none differing means the change did not touch these seconds.
  ///
  /// The replay is kept: the present is the new code's afterwards, and the
  /// buffer is rebased on the keyframe it started from, since the keyframes
  /// after it are the old code's. Null when the buffer does not reach back.
  CodeReplay? replayUnderNewCode({required double seconds}) {
    returnToPresent();
    final now = rewind.step;
    final point = rewind.rewindBy(seconds);
    if (point == null) return null;
    final offset = _offset;
    final from = point.step - point.replayed;
    final before = <int, Snapshot>{
      ...rewind.keyframesAfter(from),
      now: loop.capture(),
    };

    _restoreKeyframe(point, offset);
    var agreed = from;
    ReplayDivergence? divergence;
    void compare(int step) {
      final old = before[step];
      if (old == null || divergence != null) return;
      final differs = firstDifferingPath(old.data, loop.capture().data);
      if (differs == null) {
        agreed = step;
      } else {
        divergence = ReplayDivergence(
          agreedAt: agreed,
          step: step,
          path: differs.path,
          before: differs.a,
          after: differs.b,
        );
      }
    }

    var step = from;
    _playEach(
      point.frames,
      point.seed,
      each: () {
        if (step != from) compare(step);
        step++;
      },
    );
    compare(now);
    rewind.rebaseAt(point);
    _history.add(TimelineReplayed(from));
    return CodeReplay(fromStep: from, toStep: now, divergence: divergence);
  }

  /// [releaseAt], given the step directly rather than a [RewindPoint] —
  /// what a caller across a wire has, since a step number survives being
  /// sent as a string and a [RewindPoint] does not. Returns whether the
  /// buffer still reached that far back; false leaves the timeline
  /// untouched, the same as [preview] returning null.
  bool releaseAtStep(int step) {
    final point = rewind.rewindTo(step);
    if (point == null) return false;
    releaseAt(point);
    return true;
  }

  /// The present, captured when a scrub began; null while not scrubbed.
  Snapshot? _present;

  int? _scrubbedAt;

  /// The buffer's count less the loop's, taken when a scrub began.
  int? _scrubOffset;

  /// The buffer's count less the loop's: constant while the run is live, and
  /// held from the start of a scrub until it ends.
  int get _offset => _scrubOffset ?? rewind.step - loop.step;

  /// The step the live state is scrubbed to, or null at the present.
  int? get scrubbedAt => _scrubbedAt;

  /// Puts the live state where the run was before [step], to be looked at,
  /// keeping the tape and the present: the scrubber of a time-travel
  /// debugger.
  ///
  /// **Not [releaseAt].** A release cuts the buffer, so dragging back and
  /// forth through it would forget the future on the first drag. A scrub
  /// keeps everything: the loop's capture of the present is taken once, on
  /// the first scrub, and [returnToPresent] restores it exactly; going on
  /// from the scrubbed moment is [branchHere]. Scrubbing forward from a
  /// scrubbed step plays on from there instead of from the keyframe, so a
  /// drag to the right costs the distance dragged.
  ///
  /// Only while paused, since the loop would step the scrubbed state as if it
  /// were the present. A scrub to the present is [returnToPresent].
  ScrubAnswer scrubTo(int step) {
    if (!_paused) {
      return const ScrubRefused(
        'the run is live, so a scrub would be stepped on by the loop; pause '
        'it first',
      );
    }
    if (step == rewind.step) {
      returnToPresent();
      return ScrubMoved(step);
    }
    final point = rewind.rewindTo(step);
    if (point == null) {
      return ScrubRefused(switch (rewind.oldestStep) {
        null =>
          'nothing is held yet to scrub through; let the run play a '
              'keyframe interval first',
        final oldest =>
          'step $step is not held; the buffer reaches from step '
              '$oldest to ${rewind.step}',
      });
    }
    if (_present == null) {
      _scrubOffset = rewind.step - loop.step;
      _present = loop.capture();
    }
    _scrubTo(point);
    _history.add(TimelineScrubbed(step));
    return ScrubMoved(step);
  }

  /// Puts the present back after a scrub. Does nothing at the present, and
  /// answers whether there was a scrub to leave.
  bool returnToPresent() {
    final present = _present;
    if (present == null) return false;
    loop.rewindTo(rewind.step - _offset, state: present);
    _forgetScrub();
    _history.add(const TimelineReturned());
    return true;
  }

  /// Makes the scrubbed moment the present: the tape after it is cut, as
  /// [releaseAt] cuts it, and the run goes on from here when resumed.
  ///
  /// **Stays paused**, unlike [releaseAt]: the person branching is looking
  /// at the moment they chose, and the first step of the new branch is
  /// theirs to take.
  ScrubAnswer branchHere() {
    final at = _scrubbedAt;
    final point = at == null ? null : rewind.rewindTo(at);
    if (at == null || point == null) {
      return const ScrubRefused(
        'the run is at the present, which is already where it goes on '
        'from; scrub to a step first',
      );
    }
    rewind.cut(point);
    _forgetScrub();
    _history.add(TimelineBranched(at));
    return ScrubMoved(at);
  }

  /// What every entity did over the steps the buffer holds, read through
  /// [layout] from the loop's capture at each step — or, given [part], from
  /// that part's own data in it: a genre's run under its plugin id, whose
  /// layout is the run's `save()`.
  ///
  /// The steps are lived again from the oldest keyframe with the devices
  /// muted and the live state is put back afterwards — at the present or at
  /// the scrub, wherever it was — so asking costs a replay of the buffer and
  /// changes nothing. [every] reads one step in so many, for a buffer whose
  /// snapshots are too large to take sixty times a second of history. Null
  /// before the first keyframe.
  EntityTracks? tracks({
    required EntityLayout layout,
    String? part,
    int every = 1,
  }) {
    final oldest = rewind.oldestStep;
    final point = oldest == null ? null : rewind.rewindTo(oldest);
    if (oldest == null || point == null) return null;
    Snapshot read(Snapshot state) =>
        part == null ? state : runStateIn(state, part);
    final offset = _offset;
    final hereStep = loop.step;
    final here = loop.capture();
    final tracks = EntityTracks(layout);
    _restoreKeyframe(point, offset);
    tracks.observe(oldest, read(loop.capture()));
    var step = oldest;
    _playEach(
      point.frames,
      point.seed,
      each: () {
        step++;
        if (step % every == 0 || step == rewind.step) {
          tracks.observe(step, read(loop.capture()));
        }
      },
      observeAfter: true,
    );
    loop.rewindTo(hereStep, state: here);
    return tracks;
  }

  void _scrubTo(RewindPoint point) {
    final base = point.step - point.replayed;
    final at = _scrubbedAt;
    final from = at != null && at >= base && at <= point.step ? at : base;
    if (from != at) _restoreKeyframe(point, _offset);
    _play(point.frames.sublist(from - base, point.replayed), point.seed);
    _scrubbedAt = point.step;
  }

  /// [stepOnce] from a scrub: one step further along the tape, which ends the
  /// scrub when it reaches the present.
  void _scrubForward(int step) {
    final point = rewind.rewindTo(step);
    if (step >= rewind.step || point == null) {
      returnToPresent();
      return;
    }
    _scrubTo(point);
  }

  void _forgetScrub() {
    _present = null;
    _scrubbedAt = null;
    _scrubOffset = null;
  }

  /// Puts the loop at [point]'s keyframe: the loop step it was captured at,
  /// the buffer's step less [offset].
  void _restoreKeyframe(RewindPoint point, int offset) {
    final base = point.step - point.replayed;
    loop.rewindTo(base - offset, state: point.snapshot);
  }

  void _play(List<InputFrame> frames, int seed) => _playEach(frames, seed);

  /// Plays [frames] through the loop, one resimulated step each, with the
  /// devices muted and the tape as the loop's playback; [each] is called
  /// before every step, or after it with [observeAfter].
  void _playEach(
    List<InputFrame> frames,
    int seed, {
    void Function()? each,
    bool observeAfter = false,
  }) {
    final playback = InputTapePlayback(InputTape(seed: seed, frames: frames));
    final previous = loop.playback;
    final wasMuted = input.muted;
    loop.playback = playback;
    input.muted = true;
    try {
      while (!playback.isFinished) {
        if (!observeAfter) each?.call();
        loop.runSteps(1, resimulated: true);
        if (observeAfter) each?.call();
      }
    } finally {
      loop.playback = previous;
      input.muted = wasMuted;
    }
  }
}
