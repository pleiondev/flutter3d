import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import '../ecs/ecs_world.dart';
import '../ecs/snapshots.dart';
import '../input/input_state.dart';
import '../input/input_tape.dart';
import '../save/snapshot.dart';
import '../save/state_digest.dart';
import 'determinism_check.dart';
import 'engine_time.dart';
import 'frame_cadence.dart';
import 'loop_change.dart';
import 'published_worlds.dart';
import 'sim_queries.dart';

part 'event_bus.dart';

/// The engine's frame: input, the fixed steps phase by phase, the
/// post-step, then the frame's phases — animate, audio, camera, render, ui.
///
/// **The engine owns the frame**, which the loop before it did not: it ran
/// the steps and each game wrote the rest of its frame by hand, three games
/// in the same order and two in their own. Here the order is the loop's and a game
/// or a plugin adds to it by phase.
///
/// ## A frame
///
/// 1. **Input.** The view movement since the last stepped frame is drained
///    and spread evenly over this frame's steps.
/// 2. **The steps.** As many as the clock owes, each:
///    * at its boundary, the changes due — plugins switched, a step rate
///      changed, a replay's recorded changes — applied and journalled;
///    * the tape applied or the look added, the recorders written, the
///      latches opened;
///    * the step phases in order — `input`, `movers`, `physics`, `elements`,
///      `rules`, `publish` and any a plugin added between them — each
///      running its systems in order;
///    * the step channel delivered and digested, the latches closed.
/// 3. **The post-step.** The frame channel delivered: the steps' events,
///    reconciled across a rollback, then the frame's own.
/// 4. **The frame phases**, in order, with the simulated time this frame
///    accepted and the interpolation alpha.
///
/// ## Time
///
/// * **The step rate is the world's** ([WorldTiming]); `dt` is one step of
///   it, always.
/// * **The time scale** changes how many steps a real second runs, not
///   `dt`. Half speed is half the steps, each the same size, so a slowed run
///   arrives at the same state as a fast one. Journalled for a replay to
///   pace by.
/// * **Lost time is announced** ([CatchUp], [TimeLost]), never silently
///   dropped.
///
/// ## Determinism
///
/// Phases and systems are ordered by constraints and registration order,
/// never by a hash map. Plugins switch only at a step boundary, and the
/// switch is journalled with its step; [schedule] makes a recorded journal's
/// changes at the same steps in a replay. A step reads no clock: the wall
/// clock is read by whoever calls [frame], and reaches a step only as a
/// count of steps.
///
/// ## The world, its snapshots and what it publishes
///
/// * **[world] is the simulation's model** (item 27): an [EcsWorld] every
///   system reaches as `LoopContext.world`. Commands a system defers run at
///   the end of its phase.
/// * **[snapshots] is the one path for state** — [capture], [restore],
///   [digest], [rewindTo], the double-step check, a rewind buffer, a
///   timeline — with the world as its first part and every plugin's own
///   state beside it: a genre's run under its plugin id, a physics world's
///   origin ([shiftsPhysics]).
/// * **[published] is what the view reads** (item 19): built after every
///   step while anybody reads it ([onPublished], or a frame system reading
///   `LoopContext.published`), immutable, with the world's published
///   components, double-precision positions and the steps' events, encoded.
///   A frame phase reads that and not [world]: `LoopContext.world` throws
///   there.
/// * **[queries] are the questions the view may ask by name**
///   (`SimulationHandle.ask`), answered against the world between steps.
/// * **[origin] is the floating origin** (item 18): [shiftOrigin] moves it,
///   calls the hooks that move what is held in float32, and publishes
///   [OriginShifted].
///
/// **In a debug build a step can be run twice to prove it.** Handed a
/// [DeterminismCheck], the loop steps each checked step from a snapshot,
/// puts the snapshot back and steps it again, and names the first system —
/// and the plugin that added it — whose two runs differ. Armed inside an
/// `assert`, so a release build steps once whatever it was handed.
final class EngineLoop extends LoopRegistry {
  EngineLoop({
    required this.input,
    EcsWorld? world,
    WorldTiming timing = const WorldTiming(),
    this.simulationBase = SimulationVersion.engineOnly,
    this.catchUp = const CatchUp.announce(),
    this.drainLook,
    this.longestFrame = 0.25,
    Iterable<Flutter3dPlugin> plugins = const <Flutter3dPlugin>[],
    Iterable<PluginRegistry> registries = const <PluginRegistry>[],
    MaterialCatalog? materials,
    String? backend,
    int reconcileWindow = 600,
    int stepEventLimit = 4096,
    this.determinismCheck,
  }) : _timing = timing, // ignore: prefer_initializing_formals
       materials =
           materials ??
           registries.whereType<MaterialCatalog>().firstOrNull ??
           MaterialCatalog.builtIn(),
       world = world ?? EcsWorld(),
       events = EventBus._(
         reconcileWindow: reconcileWindow,
         stepEventLimit: stepEventLimit,
       ) {
    // Armed only where assertions run: a debug build and a test. A release
    // build never evaluates this, so it never steps twice.
    assert(() {
      _checking = determinismCheck != null;
      return true;
    }());
    for (final phase in LoopPhase.stepPhases) {
      _addPhase(
        phase,
        _builtInAfter(LoopPhase.stepPhases, phase),
        const [],
        null,
      );
    }
    for (final phase in LoopPhase.framePhases) {
      _addPhase(
        phase,
        _builtInAfter(LoopPhase.framePhases, phase),
        const [],
        null,
      );
    }
    this.world.components
      ..register<WorldOrigin>(WorldOrigin.codec)
      ..register<WorldPosition>(const WorldPositionCodec(), published: true);
    events.declare<OriginShifted>(
      OriginShifted.eventName,
      description:
          'The floating origin moved: what is held in float32 moved the other '
          'way.',
      codec: OriginShifted.codec,
    );
    snapshots = Snapshots(world: this.world);
    this.plugins = PluginManager(
      loop: this,
      events: events,
      registries: <PluginRegistry>[
        ...registries,
        this.world.components,
        snapshots,
        queries,
        publishedWorlds,
        if (!registries.contains(this.materials)) this.materials,
      ],
      backend: backend,
    )..installAll(plugins);
  }

  static List<String> _builtInAfter(List<LoopPhase> chain, LoopPhase phase) {
    final at = chain.indexOf(phase);
    return at == 0 ? const <String>[] : <String>[chain[at - 1].name];
  }

  final InputState input;

  /// The simulation's world: what every system is handed as
  /// `LoopContext.world`.
  final EcsWorld world;

  /// Every part of the state, the world first: the one way it is captured,
  /// restored and digested. Plugins reach it as
  /// `host.registry<SnapshotRegistry>()`.
  late final Snapshots snapshots;

  /// The questions the view may ask by name, answered against [world]
  /// between two steps (`SimulationHandle.ask`). Plugins reach it as
  /// `host.registry<SimulationQueryRegistry>()`.
  final SimQueries queries = SimQueries();

  /// The worlds besides [world] whose published components the view reads:
  /// a genre's run, staged per level in a world of its own, which the genre
  /// adds when its simulation is set. Plugins reach it as
  /// `host.registry<PublishedWorlds>()`.
  final PublishedWorlds publishedWorlds = PublishedWorlds();

  /// The physical materials this engine knows: the engine's own
  /// (`MaterialCatalog.builtIn`) and every enabled plugin's, a data
  /// plugin's `materials:` among them. The catalogue handed in — as
  /// `materials`, or among the `registries` — or a fresh built-in one.
  /// Plugins reach it as `host.registry<MaterialCatalog>()`.
  ///
  /// **What staging hands a world**: a game that stages a `CollisionWorld`
  /// for this loop gives it this catalogue (`CollisionWorld.materials`), so
  /// a level's medium, a collider's material and a liquid named by a
  /// plugin's id resolve against the plugins this engine has.
  final MaterialCatalog materials;

  /// The engine's and the genre's simulation numbers, without the plugins':
  /// [simulationVersion] adds those.
  final SimulationVersion simulationBase;

  /// The simulation this loop runs: [simulationBase] with every enabled
  /// simulation plugin's own number. What a run file and a network hello
  /// carry.
  SimulationVersion get simulationVersion =>
      simulationBase.withPlugins(plugins.simulationVersions);

  /// The bus: step and frame channels.
  final EventBus events;

  /// The plugins: installed at construction, switched at step boundaries.
  late final PluginManager plugins;

  /// The policy for frames that bring more time than may be stepped.
  final CatchUp catchUp;

  /// Takes the view movement accumulated since the last call, into `out`:
  /// added to, never assigned, so two devices drained in turn both count. The
  /// movement is spread evenly over the frame's steps.
  final void Function(Vector2 out)? drainLook;

  /// The longest real frame accepted, in seconds; the excess is announced
  /// as [TimeLostReason.longFrame] rather than stepped through — a debugger's
  /// pause or a backgrounded app is not a quarter of a minute of play.
  final double longestFrame;

  /// Where each live step's input is written, after the tape or the look is
  /// applied and before the latches open. A resimulated step writes nothing:
  /// it was written the first time.
  final List<InputTapeRecorder> recorders = <InputTapeRecorder>[];

  /// Drives the input from a tape while set: each step's frame is applied in
  /// place of the devices' look until the tape runs out.
  InputTapePlayback? playback;

  /// Whether the simulation is stopped: no steps, no time handed to the
  /// clock, latches dropped, held keys kept. The frame phases still run, with
  /// no simulated time.
  bool isPaused = false;

  /// The double-step check this loop was handed, armed or not.
  final DeterminismCheck? determinismCheck;

  bool _checking = false;

  /// Whether steps are being run twice: a [determinismCheck] was given and
  /// assertions are on. Read by a conformance run that wants to know the
  /// check it asked for is really running.
  bool get checksDeterminism => _checking;

  final List<void Function(StepEventSummary summary)> _stepObservers =
      <void Function(StepEventSummary summary)>[];
  final List<void Function(LoopChange change)> _changeObservers =
      <void Function(LoopChange change)>[];

  /// Calls [observer] after every step with what the step published. A
  /// recording keeps the digests; a debug overlay counts.
  Registration onStepEnd(void Function(StepEventSummary summary) observer) {
    _stepObservers.add(observer);
    return Registration(() => _stepObservers.remove(observer));
  }

  final List<void Function(InputState input)> _inputSources =
      <void Function(InputState input)>[];

  /// Calls [source] at the start of every live step, after the look is added
  /// and before [recorders] write the step's input: the place for input that
  /// arrives as values rather than from a device — `LocalSimulation.submit`
  /// — to be put into [input], so it is on the tape like a key press.
  ///
  /// Not called while a tape plays ([playback]), which is the step's whole
  /// input, nor for a resimulated step, whose input was written the first
  /// time.
  Registration onStepInput(void Function(InputState input) source) {
    _inputSources.add(source);
    return Registration(() => _inputSources.remove(source));
  }

  /// Calls [observer] with every change journalled, as it is made.
  Registration onChange(void Function(LoopChange change) observer) {
    _changeObservers.add(observer);
    return Registration(() => _changeObservers.remove(observer));
  }

  WorldTiming _timing;
  WorldTiming? _nextTiming;
  double _timeScale = 1.0;
  int _step = 0;
  double _accumulator = 0.0;
  double _alpha = 0.0;
  double _lastFrame = 0.0;
  double _realFrame = 0.0;
  bool _wasPaused = false;
  int _lostSteps = 0;
  double _lostSeconds = 0.0;
  final Vector2 _look = Vector2.zero();
  final List<LoopChange> _journal = <LoopChange>[];
  final List<LoopChange> _scheduled = <LoopChange>[];

  final List<_Phase> _phases = <_Phase>[];
  final List<_System> _systems = <_System>[];
  int _registered = 0;
  bool _ordered = false;
  List<_PhaseRun> _stepRuns = const <_PhaseRun>[];
  List<_PhaseRun> _frameRuns = const <_PhaseRun>[];
  late final _Context _context = _Context(this);

  /// The world's timing, as of the last step boundary.
  WorldTiming get timing => _timing;

  /// Seconds one step covers: the world's.
  double get stepSeconds => _timing.stepSeconds;

  /// How many steps have run since the start, or since [rewindTo].
  int get step => _step;

  /// Where the frame sits between the last two steps, in `[0, 1)`.
  double get alpha => _alpha;

  /// Simulated seconds the last [frame] accepted: scaled, clamped, nought
  /// while paused. What anything advanced beside the simulation uses.
  double get lastFrame => _lastFrame;

  /// Whole steps the clock owed and never ran, in total.
  int get lostSteps => _lostSteps;

  /// Simulated seconds never run, in total — whole steps and long frames.
  ///
  /// For a frame overlay or a pacing report that wants the total rather
  /// than each [TimeLost] — what `Pace` is handed.
  double get lostSeconds => _lostSeconds;

  /// Every change made since the start, oldest first.
  List<LoopChange> get journal => List<LoopChange>.unmodifiable(_journal);

  /// How many steps a real second runs, as a fraction of the world's rate.
  double get timeScale => _timeScale;

  /// Sets the time scale from the next frame on, and journals it at the
  /// current step. Nought holds the world still without pausing it: frames
  /// go on, input is read, no step runs.
  set timeScale(double scale) {
    if (!scale.isFinite || scale < 0.0) {
      throw ArgumentError.value(
        scale,
        'scale',
        'a time scale is nought or more',
      );
    }
    if (scale == _timeScale) return;
    _timeScale = scale;
    _journalChange(LoopTimeScale(step: _step, scale: scale));
  }

  /// Puts the world's timing in place at the next step boundary, and
  /// journals it there: a change of step rate changes the simulation.
  void changeTiming(WorldTiming timing) => _nextTiming = timing;

  /// Makes [changes] — a recorded run's journal — at their steps as this
  /// loop reaches them. Steps count from this loop's [step], so a replay
  /// that starts a recording's tape calls [rewindTo] with 0 first.
  void schedule(Iterable<LoopChange> changes) {
    final list = List<LoopChange>.of(changes);
    plugins.schedule(<PluginChange>[
      for (final change in list)
        if (change is LoopPluginChange) change.change,
    ]);
    final all = <LoopChange>[
      ..._scheduled,
      ...list.where((change) => change is! LoopPluginChange),
    ];
    // Stable by step: `List.sort` is not, and two changes at one step stay
    // in the order they were journalled.
    final order = List<int>.generate(all.length, (i) => i)
      ..sort((a, b) {
        final byStep = all[a].step.compareTo(all[b].step);
        return byStep != 0 ? byStep : a.compareTo(b);
      });
    _scheduled
      ..clear()
      ..addAll(<LoopChange>[for (final i in order) all[i]]);
  }

  /// Every part of the state, through [snapshots].
  Snapshot capture() => snapshots.capture();

  /// Puts every part of the state back to [snapshot], through [snapshots].
  ///
  /// Throws a [StateError] when [snapshot] holds none of this loop's parts —
  /// a run's own `save()` handed to the loop, say — rather than leaving the
  /// state where it was.
  void restore(Snapshot snapshot) {
    snapshots.restore(snapshot);
    _readOrigin();
  }

  /// A number that differs when any part of the state does.
  int digest() => snapshots.digest();

  /// Puts the loop at step [step]: a rollback, a scrub, a replay from the
  /// start.
  ///
  /// **Through [snapshots], the one path.** With [state] — a [capture] taken
  /// after [step] steps — every part is restored from it. Without it, the
  /// loop restores the capture it kept of that step ([keep]).
  ///
  /// **A rewind always restores something.** Throws a [StateError] when
  /// [state] is missing and no capture of [step] is kept, and when [state]
  /// holds none of the loop's parts: a rewind that restored nothing would
  /// set the count back and leave the world where it was, which is the
  /// failure a rollback cannot see. A game whose state is a genre's run is
  /// covered, since the genre adds its run as a part.
  void rewindTo(int step, {Snapshot? state}) {
    if (step < 0) {
      throw ArgumentError.value(step, 'step', 'a step is nought or more');
    }
    final restoring = state ?? _kept[step];
    if (restoring == null) {
      throw StateError(
        'nothing to rewind to step $step from: pass the state captured '
        'there, or keep captures with keep(). Kept: '
        '${_kept.isEmpty ? 'none' : (_kept.keys.toList()..sort()).join(', ')}',
      );
    }
    restore(restoring);
    _step = step;
    _kept.removeWhere((at, _) => at > step);
  }

  /// Keeps a [capture] of the state after every [every] steps for the last
  /// [window] steps, so [rewindTo] can go back without being handed one —
  /// starting with the state as it is now, so the step the keeping began at
  /// is one it can go back to. Nought switches it off, which is the default:
  /// a capture costs a save of the whole world.
  void keep({required int window, int every = 1}) {
    if (window < 0 || every < 1) {
      throw ArgumentError('a window of nought or more, every one or more');
    }
    _keepWindow = window;
    _keepEvery = every;
    if (window == 0) {
      _kept.clear();
    } else {
      _kept[_step] = snapshots.capture();
    }
  }

  int _keepWindow = 0;
  int _keepEvery = 1;
  final Map<int, Snapshot> _kept = <int, Snapshot>{};

  /// The steps [rewindTo] can go back to without being handed a state.
  List<int> get keptSteps => _kept.keys.toList()..sort();

  void _keepIfDue() {
    if (_keepWindow == 0 || _step % _keepEvery != 0) return;
    _kept[_step] = snapshots.capture();
    _kept.removeWhere((at, _) => at < _step - _keepWindow);
  }

  // ---------------------------------------------------------------------------
  // What the view reads.

  PublishedState _published = PublishedState.empty;
  final List<void Function(PublishedState state)> _publishedListeners =
      <void Function(PublishedState state)>[];

  // Whether anything has read [published]: from then on every step
  // publishes, as it does while anybody listens.
  bool _read = false;

  bool get _publishing => _read || _publishedListeners.isNotEmpty;

  /// The state the last step published: what the view reads of the
  /// simulation.
  ///
  /// **Built once somebody reads it**, and after every step from then on: the
  /// first read — a view's, a frame system's through `LoopContext.published`
  /// — is answered with the state as it stands and turns publishing on, as a
  /// listener ([onPublished]) does. A loop nothing reads encodes nothing for
  /// a view.
  PublishedState get published {
    if (!_publishing) {
      _read = true;
      events._collecting = true;
      _published = _build();
    }
    return _published;
  }

  /// Calls [listener] with the state every step publishes from now on, and
  /// starts publishing.
  Registration onPublished(void Function(PublishedState state) listener) {
    _publishedListeners.add(listener);
    events._collecting = true;
    return Registration(() {
      _publishedListeners.remove(listener);
      events._collecting = _publishing;
    });
  }

  PublishedState _build() {
    final sources = <EcsWorld>[world, ...publishedWorlds.worlds];
    final components = <String, Map<Entity, Object?>>{};
    final positions = <Entity, WorldPosition>{};
    for (final source in sources) {
      for (final MapEntry(:key, :value)
          in source.publishedComponents().entries) {
        if (value.isEmpty) continue;
        if (components.containsKey(key)) {
          throw StateError(
            'the published component "$key" comes from two worlds, whose '
            'entities are numbered apart; publish it from one, or give the '
            "other world's component an id of its own",
          );
        }
        components[key] = value;
      }
      final placed = source.publishedPositions();
      if (placed.isEmpty) continue;
      if (positions.isNotEmpty) {
        throw StateError(
          'positions are published from two worlds, whose entities are '
          'numbered apart; set WorldPosition in one of them',
        );
      }
      positions.addAll(placed);
    }
    return PublishedState(
      step: _step,
      seconds: _step * stepSeconds,
      origin: _origin,
      components: components,
      positions: positions,
      events: events._takeCollected(),
      simulation: simulationVersion,
    );
  }

  void _publish() {
    if (!_publishing) return;
    final state = _build();
    _published = state;
    for (final listener in List.of(_publishedListeners)) {
      listener(state);
    }
  }

  // ---------------------------------------------------------------------------
  // The floating origin.

  WorldPosition _origin = WorldPosition.origin;
  final List<void Function(OriginShifted shift)> _originHooks =
      <void Function(OriginShifted shift)>[];

  /// The world position the simulation's float32 local frame is relative
  /// to. Positions held as [WorldPosition] do not depend on it.
  WorldPosition get origin => _origin;

  /// Calls [hook] whenever the origin moves, before anything else runs: the
  /// place to move bodies (`CollisionWorld.moveOriginTo`, which
  /// [shiftsPhysics] installs) and particles (`ParticleSystem.shiftOrigin`)
  /// by the opposite of the shift.
  Registration onOriginShift(void Function(OriginShifted shift) hook) {
    _originHooks.add(hook);
    return Registration(() => _originHooks.remove(hook));
  }

  /// Moves [world]'s colliders and characters with the origin from now on,
  /// and makes its origin part of the snapshots: [onOriginShift] with
  /// `CollisionWorld.moveOriginTo`, and `CollisionWorld.originPart` added to
  /// [snapshots], so a rewind across a shift puts the bodies back in the
  /// frame they were captured in. The physics hook a game with a world
  /// larger than float32 holds installs once.
  Registration shiftsPhysics(CollisionWorld world) {
    final moving = onOriginShift((shift) => world.moveOriginTo(shift.to));
    final saving = snapshots.add(world.originPart);
    return Registration(() {
      moving.cancel();
      saving.cancel();
    });
  }

  /// Moves the origin to [to]: every hook moves what it holds, then
  /// [OriginShifted] is published — on the step channel from inside a step,
  /// so a replay shifts at the same step, and the view hears it once.
  ///
  /// The origin is part of the world's snapshot while it is away from the
  /// world origin, so a rewind puts it back too.
  void shiftOrigin(WorldPosition to) {
    if (to == _origin) return;
    final shift = OriginShifted(from: _origin, to: to);
    _origin = to;
    _storeOrigin();
    for (final hook in List.of(_originHooks)) {
      hook(shift);
    }
    events.publish(shift);
  }

  void _storeOrigin() {
    if (_origin == WorldPosition.origin) {
      world.removeResource<WorldOrigin>();
    } else {
      world.setResource<WorldOrigin>(WorldOrigin(_origin));
    }
  }

  void _readOrigin() {
    _origin = world.resource<WorldOrigin>()?.at ?? WorldPosition.origin;
  }

  /// Forgets the time the clock holds that no step has run yet: a level that
  /// took seconds to load, whose wait happened in no game. The next frame
  /// starts from an empty accumulator, nothing is announced as lost, and the
  /// step count and the input are left alone.
  void resetClock() {
    _accumulator = 0.0;
    _alpha = 0.0;
  }

  /// One displayed frame of [dt] real seconds. Returns how many steps ran.
  int frame(double dt) {
    final real = dt.isFinite && dt > 0.0 ? dt : 0.0;
    _realFrame = real < longestFrame ? real : longestFrame;
    final steps = _advance(real);
    events._deliverFrame();
    _runFrame();
    return steps;
  }

  /// The frame-rate cap the vsync driver holds to — `A1.5`. Null, the
  /// default, runs a frame every refresh [frameAtVsync] is called for.
  FrameCadence? cadence;

  /// One refresh of the display at [vsync], the ticker's timestamp: a
  /// [frame] when [cadence] says this refresh is one to draw on, and nothing
  /// otherwise. Returns the steps run, or null for a refresh skipped.
  ///
  /// **The skipped refresh is not lost time.** The next frame drawn is
  /// handed every second since the last one — [FrameCadence.due] measures
  /// from the frame drawn, not from the refresh before — so a game held to
  /// sixty on a 120 Hz screen steps as many times a second as one that is
  /// not, two steps a frame where it was one.
  ///
  /// [seconds], when given, is the frame's length as the caller measured it
  /// — a `FrameClock` on the wall, which a stalled ticker's timestamps are
  /// not — summed over the skipped refreshes; the cadence's own measure is
  /// used otherwise.
  int? frameAtVsync(Duration vsync, {double? seconds}) {
    final measured = seconds;
    if (measured != null) _skippedSeconds += measured;
    final paced = cadence;
    final elapsed = paced?.due(vsync);
    if (paced != null && elapsed == null) return null;
    final dt = measured != null ? _skippedSeconds : (elapsed ?? 0.0);
    _skippedSeconds = 0.0;
    return frame(dt);
  }

  /// What [frameAtVsync] was told while it skipped, for the frame it draws.
  double _skippedSeconds = 0.0;

  /// Runs [count] steps now, whatever the clock says, through the same door
  /// as [frame]: a cutscene skipped, a rollback re-stepping, a replay.
  ///
  /// [resimulated] marks steps run again after a [rewindTo]: step systems
  /// see it, the recorders skip the steps, and the frame channel reconciles
  /// their events with what it already showed. The frame channel is
  /// delivered at the next [frame].
  void runSteps(int count, {bool resimulated = false}) {
    for (var i = 0; i < count; i++) {
      _stepOnce(0.0, 0.0, resimulated: resimulated);
    }
  }

  int _advance(double real) {
    if (isPaused) {
      _wasPaused = true;
      _lastFrame = 0.0;
      _look.setZero();
      drainLook?.call(_look);
      input.endStep();
      return 0;
    }
    if (_wasPaused) {
      _wasPaused = false;
      _accumulator = 0.0;
    }
    if (real > longestFrame) {
      _lose((real - longestFrame) * _timeScale, 0, TimeLostReason.longFrame);
    }
    _lastFrame = _realFrame * _timeScale;
    _accumulator += _lastFrame;

    final step = stepSeconds;
    var steps = 0;
    while (_accumulator >= step && steps < catchUp.maxStepsPerFrame) {
      _accumulator -= step;
      steps++;
    }
    if (_accumulator >= step && _accumulator > catchUp.backlog) {
      final owed = _accumulator ~/ step;
      final over = ((_accumulator - catchUp.backlog) / step).ceil();
      final dropped = over < owed ? over : owed;
      _accumulator -= dropped * step;
      _lose(dropped * step, dropped, TimeLostReason.overBudget);
    }
    if (_accumulator < 0.0) _accumulator = 0.0;
    final whole = _accumulator ~/ step;
    _alpha = (_accumulator - whole * step) / step;
    if (_alpha >= 1.0 || _alpha < 0.0) _alpha = 0.0;

    if (steps == 0) return 0;
    _look.setZero();
    drainLook?.call(_look);
    final perStep = 1.0 / steps;
    final lookX = _look.x * perStep;
    final lookY = _look.y * perStep;
    for (var i = 0; i < steps; i++) {
      _stepOnce(lookX, lookY, resimulated: false);
    }
    return steps;
  }

  void _lose(double seconds, int steps, TimeLostReason reason) {
    if (seconds <= 0.0) return;
    _lostSeconds += seconds;
    _lostSteps += steps;
    events.publishFrame(
      TimeLost(seconds: seconds, steps: steps, reason: reason),
    );
  }

  void _stepOnce(double lookX, double lookY, {required bool resimulated}) {
    _boundary();
    final tape = playback;
    if (tape != null && !tape.isFinished) {
      tape.applyTo(input);
    } else {
      input.addLook(lookX, lookY);
      if (!resimulated) {
        for (final source in List.of(_inputSources)) {
          source(input);
        }
      }
    }
    if (!resimulated) {
      for (var r = 0; r < recorders.length; r++) {
        recorders[r].record(input);
      }
    }
    input.beginStep();
    final check = determinismCheck;
    final checked =
        _checking && check != null && !resimulated && _step % check.every == 0;
    final StepDivergence? divergence;
    final StepEventSummary summary;
    if (checked) {
      (summary, divergence) = _checkedStep(check);
    } else {
      events._beginStep(_step, resimulated: resimulated);
      _runStepPhases(resimulated, null);
      summary = events._endStep();
      divergence = null;
    }
    input.endStep();
    _step++;
    _keepIfDue();
    _publish();
    for (final observer in List.of(_stepObservers)) {
      observer(summary);
    }
    if (divergence != null) {
      // Reported once the step is over, so a throw leaves the loop at a
      // step boundary rather than halfway through one.
      final report = check!.onDivergence;
      if (report == null) throw DeterminismError(divergence);
      report(divergence);
    }
  }

  /// Runs the step phases once. [trace], when given, gets the check's
  /// digest after every system, in the order they ran.
  void _runStepPhases(bool resimulated, List<int>? trace) {
    _context
      ..step = _step
      ..dt = stepSeconds
      ..realDt = 0.0
      ..alpha = 0.0
      ..isResimulated = resimulated;
    final digest = trace == null
        ? null
        : (determinismCheck!.digest ?? snapshots.digest);
    world
      ..beginStep(_step)
      // Whatever a frame phase deferred runs before the step, not in it.
      ..applyCommands();
    for (final run in _stepRuns) {
      _context.phase = run.phase;
      for (final system in run.systems) {
        system.system(_context);
        if (digest != null) trace!.add(digest());
      }
      world.applyCommands();
    }
  }

  /// One step run twice from the same state — see [DeterminismCheck]. The
  /// second run is the real one; the first is put back before it.
  (StepEventSummary, StepDivergence?) _checkedStep(DeterminismCheck check) {
    if (check.capture == null && snapshots.holdsNothing) {
      // Refused rather than passed: a check of a world with nothing in it
      // agrees with itself whatever the systems do, and a green check that
      // checked nothing is worse than none.
      throw StateError(
        'the determinism check has nothing to compare at step $_step: the '
        "loop's snapshots hold an empty world and no other part. A genre "
        "adds its run as a part when it is installed and given a "
        'simulation; state kept anywhere else needs a SnapshotPart '
        '(snapshots.add), or the check its own capture, restore and digest',
      );
    }
    final capture = check.capture ?? snapshots.capture;
    final restoreState =
        check.restore ??
        (Object? state) {
          snapshots.restore(state! as Snapshot);
          _readOrigin();
        };
    final digestState = check.digest ?? snapshots.digest;
    final before = capture();
    final start = digestState();

    events._beginStep(_step, resimulated: false);
    final first = <int>[];
    _runStepPhases(false, first);
    final firstEvents = events._discardStep();
    final firstEnd = digestState();

    restoreState(before);
    final restored = digestState();

    events._beginStep(_step, resimulated: false);
    final second = <int>[];
    _runStepPhases(false, second);
    final summary = events._endStep();
    final secondEnd = digestState();

    if (restored != start) {
      return (
        summary,
        StepDivergence(
          step: _step,
          reason:
              'the state read back after restoring is not the state the step '
              'began from (digest $restored, not $start), so the check '
              'cannot tell one run from the other. The snapshot leaves '
              'something out: capture and restore must cover everything a '
              'step system writes',
        ),
      );
    }
    final systems = <(LoopPhase, _System)>[
      for (final run in _stepRuns)
        for (final system in run.systems) (run.phase, system),
    ];
    for (var i = 0; i < systems.length && i < first.length; i++) {
      if (first[i] == second[i]) continue;
      final (phase, system) = systems[i];
      return (
        summary,
        StepDivergence(
          step: _step,
          system: system.name,
          phase: phase,
          owner: system.scope?.manifest.id,
          reason:
              'system "${system.name}" in ${phase.name}, added by '
              '${system.owner}, gave two answers from one state: every '
              'system before it agreed. It reads something a step may not — '
              'a clock, an unseeded Random, a hash map\'s order, a field it '
              'keeps outside the snapshot',
        ),
      );
    }
    if (firstEvents != summary.digest) {
      return (
        summary,
        StepDivergence(
          step: _step,
          reason:
              'every system left the same state and the step\'s events '
              'differ: a step subscriber published something else the '
              'second time',
        ),
      );
    }
    if (firstEnd != secondEnd) {
      return (
        summary,
        StepDivergence(
          step: _step,
          reason:
              'every system left the same state and the state after the '
              'step\'s subscribers differs: a step subscriber changed the '
              'world in two ways',
        ),
      );
    }
    return (summary, null);
  }

  /// Applies what is due before step [_step]: a replay's scheduled changes,
  /// a new world, the plugins' pending switches. Then sorts what changed.
  void _boundary() {
    while (_scheduled.isNotEmpty && _scheduled.first.step <= _step) {
      switch (_scheduled.removeAt(0)) {
        case LoopTimeScale(:final scale):
          if (scale != _timeScale) {
            _timeScale = scale;
            _journalChange(LoopTimeScale(step: _step, scale: scale));
          }
        case LoopStepRate(:final rate):
          _nextTiming = WorldTiming(stepRate: rate);
        case LoopPluginChange():
          break;
      }
    }
    final next = _nextTiming;
    if (next != null) {
      _nextTiming = null;
      if (next != _timing) {
        _timing = next;
        _journalChange(LoopStepRate(step: _step, rate: next.stepRate));
      }
    }
    if (plugins.hasPending) {
      final applied = plugins.applyPending(_step);
      if (applied.isNotEmpty) {
        _ordered = false;
        events._markOrderChanged();
        for (final change in applied) {
          _journalChange(LoopPluginChange(change));
        }
      }
    }
    if (!_ordered) _order();
  }

  void _journalChange(LoopChange change) {
    _journal.add(change);
    for (final observer in List.of(_changeObservers)) {
      observer(change);
    }
  }

  void _runFrame() {
    if (!_ordered) _order();
    _context
      ..step = _step
      ..dt = _lastFrame
      ..realDt = _realFrame
      ..alpha = _alpha
      ..isResimulated = false;
    for (final run in _frameRuns) {
      _context.phase = run.phase;
      for (final system in run.systems) {
        system.system(_context);
      }
    }
    // What the frame phases published goes out with the next post-step.
  }

  // ---------------------------------------------------------------------------
  // The registry.

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => _addPhase(phase, after, before, null);

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => _addSystem(name, phase, system, after, before, null);

  @override
  LoopRegistry forPlugin(PluginScope scope) => _ScopedLoop(this, scope);

  // A phase is looked up under the name it has now, so a plugin or a file
  // that names one by its former name (`LoopPhase.formerNames`) still finds
  // it.
  Registration _addPhase(
    LoopPhase named,
    List<String> afterNamed,
    List<String> beforeNamed,
    PluginScope? scope,
  ) {
    final phase = named.current;
    final after = afterNamed.map(LoopPhase.currentName).toList();
    final before = beforeNamed.map(LoopPhase.currentName).toList();
    for (final existing in _phases) {
      if (existing.phase.name == phase.name) {
        throw ArgumentError.value(
          phase.name,
          'phase',
          'a phase named "${phase.name}" is already in the loop, added by '
              '${existing.owner}',
        );
      }
    }
    for (final name in <String>[...after, ...before]) {
      final anchor = _phases.where((p) => p.phase.name == name).firstOrNull;
      if (anchor == null || anchor.phase.kind != phase.kind) {
        throw ArgumentError.value(
          name,
          'after/before',
          '${phase.name} is ordered against "$name", which is not a '
              '${phase.kind.name} phase of this loop',
        );
      }
    }
    final entry = _Phase(
      phase,
      List<String>.unmodifiable(after),
      List<String>.unmodifiable(before),
      scope,
      _registered++,
    );
    _phases.add(entry);
    _ordered = false;
    final registration = Registration(() {
      _phases.remove(entry);
      _ordered = false;
    });
    scope?.track(registration);
    return registration;
  }

  Registration _addSystem(
    String name,
    LoopPhase named,
    LoopSystem system,
    List<String> after,
    List<String> before,
    PluginScope? scope,
  ) {
    final phase = named.current;
    final existing = _systems.where((s) => s.name == name).firstOrNull;
    if (existing != null) {
      throw ArgumentError.value(
        name,
        'name',
        'a system named "$name" is already in the loop, in '
            '${existing.phase.name}, added by ${existing.owner}',
      );
    }
    if (!_phases.any((p) => p.phase == phase)) {
      throw ArgumentError.value(
        phase.name,
        'phase',
        'system "$name" was added to ${phase.kind.name} phase '
            '"${phase.name}", which is not in this loop',
      );
    }
    final entry = _System(
      name,
      phase,
      system,
      List<String>.unmodifiable(after),
      List<String>.unmodifiable(before),
      scope,
      _registered++,
    );
    _systems.add(entry);
    _ordered = false;
    final registration = Registration(() {
      _systems.remove(entry);
      _ordered = false;
    });
    scope?.track(registration);
    return registration;
  }

  /// The phases of [kind], in the order they run.
  List<LoopPhase> phases(PhaseKind kind) {
    if (!_ordered) _order();
    return <LoopPhase>[
      for (final run in kind == PhaseKind.step ? _stepRuns : _frameRuns)
        run.phase,
    ];
  }

  /// The names of [phase]'s systems, in the order they run.
  List<String> systemsIn(LoopPhase phase) {
    final current = phase.current;
    if (!_ordered) _order();
    final runs = current.kind == PhaseKind.step ? _stepRuns : _frameRuns;
    return <String>[
      for (final run in runs)
        if (run.phase == current)
          for (final system in run.systems) system.name,
    ];
  }

  /// Sorts phases and systems. Throws a [ConstraintCycleException] naming the
  /// cycle when the constraints have no order.
  void _order() {
    final phases = List<_Phase>.of(_phases)..sort(_Entry.compare);
    final systems = List<_System>.of(_systems)..sort(_Entry.compare);
    List<_PhaseRun> runsOf(PhaseKind kind) {
      final ordered = orderByConstraints<_Phase>(
        <_Phase>[
          for (final p in phases)
            if (p.phase.kind == kind) p,
        ],
        nameOf: (p) => p.phase.name,
        after: (p) => p.after,
        before: (p) => p.before,
        what: '${kind.name} phases',
      );
      return <_PhaseRun>[
        for (final p in ordered)
          _PhaseRun(
            p.phase,
            orderByConstraints<_System>(
              <_System>[
                for (final s in systems)
                  if (s.phase == p.phase) s,
              ],
              nameOf: (s) => s.name,
              after: (s) => s.after,
              before: (s) => s.before,
              what: 'systems in ${p.phase.name}',
            ),
          ),
      ];
    }

    _stepRuns = runsOf(PhaseKind.step);
    _frameRuns = runsOf(PhaseKind.frame);
    _ordered = true;
  }
}

final class _ScopedLoop extends LoopRegistry {
  _ScopedLoop(this._loop, this._scope);

  final EngineLoop _loop;
  final PluginScope _scope;

  bool get _viewOnly => !_scope.manifest.touches.simulates;

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    if (_viewOnly && phase.kind == PhaseKind.step) {
      throw PluginException(
        'plugin "${_scope.manifest.id}" declares that it touches only the '
        'view, and added the step phase "${phase.name}". Add a frame phase, '
        'or declare touches: PluginTouches.simulation',
      );
    }
    return _loop._addPhase(phase, after, before, _scope);
  }

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    if (_viewOnly && phase.kind == PhaseKind.step) {
      throw PluginException(
        'plugin "${_scope.manifest.id}" declares that it touches only the '
        'view, and added the system "$name" to the step phase '
        '"${phase.name}". Run it in a frame phase, or declare touches: '
        'PluginTouches.simulation',
      );
    }
    return _loop._addSystem(name, phase, system, after, before, _scope);
  }

  @override
  LoopRegistry forPlugin(PluginScope scope) => _loop.forPlugin(scope);
}

abstract base class _Entry {
  _Entry(this.scope, this.sequence);

  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  String get owner =>
      scope == null ? 'the application' : 'plugin "${scope!.manifest.id}"';

  static int compare(_Entry a, _Entry b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

final class _Phase extends _Entry {
  _Phase(this.phase, this.after, this.before, super.scope, super.sequence);

  final LoopPhase phase;
  final List<String> after;
  final List<String> before;
}

final class _System extends _Entry {
  _System(
    this.name,
    this.phase,
    this.system,
    this.after,
    this.before,
    super.scope,
    super.sequence,
  );

  final String name;
  final LoopPhase phase;
  final LoopSystem system;
  final List<String> after;
  final List<String> before;
}

final class _PhaseRun {
  const _PhaseRun(this.phase, this.systems);

  final LoopPhase phase;
  final List<_System> systems;
}

final class _Context extends LoopContext {
  _Context(this.loop);

  final EngineLoop loop;

  EventBus get bus => loop.events;

  @override
  EcsWorld get world {
    if (phase.kind == PhaseKind.frame) {
      throw StateError(
        'the world was read in the frame phase "${phase.name}". A frame '
        "phase is the view's: it reads LoopContext.published, which a step "
        'builds from the published components, so it keeps working when the '
        'simulation runs elsewhere. Register what the view needs with '
        'published: true, or move the system into a step phase',
      );
    }
    return loop.world;
  }

  @override
  PublishedState get published => loop.published;

  @override
  int step = 0;

  /// Simulated seconds, as [LoopContext.dt].
  @override
  double dt = 0.0;

  /// Wall-clock seconds of the frame, as [LoopContext.realDt].
  @override
  double realDt = 0.0;

  /// The 0..1 fraction between the last two steps, as [LoopContext.alpha].
  @override
  double alpha = 0.0;

  @override
  LoopPhase phase = LoopPhase.input;

  @override
  bool isResimulated = false;

  @override
  void publish(BusEvent event) => phase.kind == PhaseKind.step
      ? bus.publish(event)
      : bus.publishFrame(event);
}

/// The floating origin, as the world's resource while it is away from the
/// world origin: what puts it back on a restore.
final class WorldOrigin {
  const WorldOrigin(this.at);

  final WorldPosition at;

  /// How it is written in a snapshot.
  static final ComponentCodec<WorldOrigin> codec =
      ComponentCodec<WorldOrigin>.of(
        id: 'flutter3d.origin',
        encode: (origin) => <double>[origin.at.x, origin.at.y, origin.at.z],
        decode: (data, _) => switch (data) {
          [final num x, final num y, final num z] => WorldOrigin(
            WorldPosition(x.toDouble(), y.toDouble(), z.toDouble()),
          ),
          _ => null,
        },
      );
}
