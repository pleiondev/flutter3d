import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'events.dart';
import 'race_state.dart';
import 'track.dart';
import 'vehicle/vehicle_controller.dart';

/// A racing game's step, in the order it has to happen in.
///
/// The sibling of `PlatformerSimulation`, and the third time this order has
/// been written down: mechanisms move, the broadphase catches up, dynamics run,
/// the bodies move, overlaps dispatch, events are published. What is new here
/// is everything between — cars pushing each other apart, a lap that only
/// counts if it was driven the whole way round, and putting a car back on the
/// track when it has left it.
///
/// ## What counts a lap
///
/// Crossing the finish line is not enough, and the checkpoints exist for one
/// reason: without them a car can drive ten metres past the line, turn round,
/// and cross it forwards again for a lap a second. So the line only counts when
/// every checkpoint has been passed since the last one, in order.
///
/// ## What this does not own
///
/// The cars. They are handed in already built, they are stepped here, and they
/// are otherwise none of this class's business — the same relationship the
/// platformer's simulation has with its runner. That is what lets a car be
/// driven with no race around it at all.
final class RacingSimulation {
  RacingSimulation({
    required this.collision,
    required this.vehicles,
    required this.race,
    this.mechanisms,
    this.dynamics,
    this.killPlane = -50.0,
    this.offRoadPatience = 4.0,
    this.contactRestitution = 0.35,
  }) : inputs = List<VehicleInput>.generate(
         vehicles.length,
         (_) => VehicleInput(),
         growable: false,
       ) {
    for (var i = 0; i < vehicles.length; i++) {
      race.progress[i].s = vehicles[i].trackDistance;
      _previousS.add(vehicles[i].trackDistance);
      _backwards.add(0.0);
      _offRoadFor.add(0.0);
    }
  }

  final CollisionWorld collision;

  /// The order the world is stepped in, shared with the other two games — see
  /// [WorldStep], which carries the reasons.
  late final WorldStep _world = WorldStep(
    collision: collision,
    mechanisms: mechanisms,
    dynamics: dynamics,
  );

  /// The cars, in a fixed order. Nought is the player's.
  ///
  /// Fixed because the order is part of the answer: cars are pushed apart in
  /// pairs, and a set that iterated differently on another machine would
  /// separate them differently and take the replay with it.
  final List<VehicleController> vehicles;

  final RaceState race;
  final MechanismWorld? mechanisms;
  final Dynamics? dynamics;

  /// What each driver is asking for. Filled in before [step] — by the player's
  /// keys for car nought, and by an AI for the rest.
  final List<VehicleInput> inputs;

  /// The height below which there is no track left.
  final double killPlane;

  /// How long a car may be off the racing surface before it is put back.
  ///
  /// Long enough to run wide and recover, short enough that cutting the course
  /// is not a strategy.
  final double offRoadPatience;

  /// How much of the speed of a bump between two cars comes back out of it.
  final double contactRestitution;

  /// True on the step the race ended.
  /// What this step did, for a game that wants to hear about it.
  ///
  /// Drain it after the step; see `events.dart`. Unlike the flags beside it,
  /// every event names the car it happened to, so the field's moments can be
  /// read in the order they happened rather than by walking the grid.
  final GameEvents events = GameEvents();

  bool finishedThisStep = false;

  /// Advances one fixed step.
  ///
  /// The order, and why each piece is where it is:
  ///
  /// 1.  clear last step's flags, so that nothing reads an event twice;
  /// 2.  run the lights — during a countdown a car may rev and may not move;
  /// 3.  mechanisms move, then `reindex`, then dynamics: a mover that has not
  ///     been reindexed is a mover the sweeps below find in last step's place;
  /// 4.  every car steps, in a fixed order;
  /// 5.  cars that have ended up inside each other are pushed apart — after the
  ///     driving, because it is the driving that put them there;
  /// 6.  dynamics are shoved: intent, never leftover velocity;
  /// 7.  progress is read — where each car is round the lap, which checkpoints
  ///     it has passed, whether it is going backwards or has left the road;
  /// 8.  overlaps dispatch, then kinematic deltas are cleared;
  /// 9.  mechanisms publish, or every event they raised stays unread while the
  ///     machinery goes on working — the platformer's second lesson;
  /// 10. cars that have fallen off the world, or spent too long off it, are put
  ///     back, and the broadphase is told, because it is still holding them
  ///     where they went.
  void step(double dt) {
    race.clearStepFlags();
    finishedThisStep = false;

    if (race.phase == RacePhase.finished) return;

    final racing = _runLights(dt);
    race.elapsed += dt;

    _world.movers(dt);
    _world.index(dt);

    for (var i = 0; i < vehicles.length; i++) {
      vehicles[i].step(dt, racing ? inputs[i] : _revvingOnly(inputs[i]));
      if (!racing) {
        // Held on the line. The wheels have turned, which is the point of
        // letting the throttle through, but the car has not.
        vehicles[i].velocity.setZero();
      }
    }

    _separateCars();

    if (dynamics != null) {
      for (final vehicle in vehicles) {
        dynamics!.push(vehicle.collider, vehicle.velocity);
      }
    }

    for (var i = 0; i < vehicles.length; i++) {
      _readProgress(i, dt, racing);
    }

    _world.settle();
    _world.publish();

    for (var i = 0; i < vehicles.length; i++) {
      _recover(i, dt);
    }
  }

  /// Runs the countdown. Returns whether the cars may actually drive.
  bool _runLights(double dt) {
    if (race.phase != RacePhase.countdown) return true;

    final before = race.countdown.ceil();
    race.countdown -= dt;
    final after = race.countdown.ceil();
    if (after != before) {
      race.countdownTickThisStep = true;
      events.add(CountdownTicked(after));
    }

    if (race.countdown > 0.0) return false;

    race.countdown = 0.0;
    race.phase = RacePhase.running;
    race.startedThisStep = true;
    events.add(const RaceStarted());
    return true;
  }

  /// The throttle and nothing else, for a car waiting on the lights.
  VehicleInput _revvingOnly(VehicleInput asked) {
    _held
      ..reset()
      ..throttle = asked.throttle;
    return _held;
  }

  /// Pushes apart any two cars that have ended up inside each other.
  ///
  /// Symmetric, and in a fixed pair order. Both halves matter: a car that gave
  /// way to every other car would be shuffled across the track by a crowd, and
  /// a pair order that varied would separate them differently on two machines
  /// running the same replay.
  void _separateCars() {
    for (var i = 0; i < vehicles.length; i++) {
      for (var j = i + 1; j < vehicles.length; j++) {
        final a = vehicles[i];
        final b = vehicles[j];

        _between
          ..setFrom(b.position)
          ..sub(a.position);
        final distance = _between.length;

        final overlap = _radiusOf(a) + _radiusOf(b) - distance;
        if (overlap <= 0.0) continue;

        if (distance < 1e-6) {
          // Exactly on top of one another, which a grid with a bad column gap
          // can manage. Any direction will do; a fixed one keeps it repeatable.
          _between.setValues(1.0, 0.0, 0.0);
        } else {
          _between.scale(1.0 / distance);
        }

        a.position.addScaled(_between, -overlap / 2.0);
        b.position.addScaled(_between, overlap / 2.0);

        // And the part of their speeds that was closing the gap, swapped and
        // damped. Without this they separate and immediately drive back into
        // each other, which reads as two cars vibrating against one another.
        final closing = b.velocity.dot(_between) - a.velocity.dot(_between);
        if (closing >= 0.0) continue;
        final exchange = -closing * (1.0 + contactRestitution) / 2.0;
        a.velocity.addScaled(_between, -exchange);
        b.velocity.addScaled(_between, exchange);
      }
    }
  }

  double _radiusOf(VehicleController vehicle) {
    final shape = vehicle.collider.shape;
    return shape is CollisionSphere ? shape.radius : 1.0;
  }

  /// Where this car has got to, and what that means.
  void _readProgress(int index, double dt, bool racing) {
    final racer = race.progress[index];
    final vehicle = vehicles[index];
    final track = race.track;
    final length = track.length;

    final previous = _previousS[index];
    final current = track.centre.wrap(vehicle.trackDistance);
    final moved = _shortestDelta(previous, current, length);
    _previousS[index] = current;
    racer.s = current;

    // How far off the racing line, worked out from where the car already knows
    // it is rather than by searching the curve a second time.
    track.frameAt(current, _frame);
    _offset
      ..setFrom(vehicle.position)
      ..sub(_frame.position);
    racer.lateral = _offset.dot(_frame.right);

    final wasOffRoad = racer.offRoad;
    racer.offRoad = racer.lateral.abs() > track.widthAt(current) / 2.0;
    if (racer.offRoad && !wasOffRoad) {
      racer.leftRoadThisStep = true;
      events.add(LeftTheRoad(racer));
    }

    if (!racing || racer.finished || race.mode == RaceMode.freeRoam) {
      if (race.mode == RaceMode.freeRoam) racer.totalTime += dt;
      return;
    }

    racer.lapTime += dt;
    racer.totalTime += dt;

    _readWrongWay(racer, index, moved);
    _readCheckpoints(racer, previous, moved, length);
    _readLine(racer, previous, moved, length);
  }

  /// Going backwards, once it has gone on long enough to be deliberate.
  ///
  /// Measured as distance rather than as a moment, because a car sliding
  /// through a corner spends single steps pointing anywhere at all, and a
  /// warning that flashed on every one of those would mean nothing.
  void _readWrongWay(RacerProgress racer, int index, double moved) {
    if (moved < 0.0) {
      _backwards[index] -= moved;
    } else {
      _backwards[index] = math.max(0.0, _backwards[index] - moved);
    }

    final wrong = _backwards[index] > 12.0;
    if (wrong && !racer.wrongWay) {
      racer.wrongWayStartedThisStep = true;
      events.add(WentWrongWay(racer));
    }
    racer.wrongWay = wrong;
  }

  void _readCheckpoints(
    RacerProgress racer,
    double previous,
    double moved,
    double length,
  ) {
    final checkpoints = race.track.checkpoints;
    if (checkpoints.isEmpty || moved <= 0.0) return;

    // One step can cover several checkpoints on a short track at speed, so this
    // is a loop and not an `if`.
    while (racer.nextCheckpoint < checkpoints.length &&
        _swept(previous, moved, checkpoints[racer.nextCheckpoint], length)) {
      racer.nextCheckpoint += 1;
      racer.checkpointThisStep = true;
      events.add(CheckpointPassed(racer));
    }
  }

  /// Crossing the finish line, which only counts having been all the way round.
  void _readLine(
    RacerProgress racer,
    double previous,
    double moved,
    double length,
  ) {
    if (moved <= 0.0) return;
    if (!_swept(previous, moved, 0.0, length)) return;

    if (racer.nextCheckpoint < race.track.checkpoints.length) {
      // Over the line without having been round: a cut course, or a car that
      // reversed over the line and drove forwards again. Nothing happens, and
      // the checkpoints it does have are kept — it still has to reach the rest.
      return;
    }

    racer.lap += 1;
    racer.nextCheckpoint = 0;
    racer.lastLap = racer.lapTime;
    racer.lapCompletedThisStep = true;
    events.add(LapCompleted(racer));

    final best = racer.bestLap;
    if (best == null || racer.lastLap < best) {
      racer.bestLap = racer.lastLap;
      racer.bestLapThisStep = true;
      events.add(BestLapSet(racer));
    }
    racer.lapTime = 0.0;

    if (race.mode == RaceMode.race && racer.lap >= race.laps) {
      racer.finishedAt = race.elapsed;
      racer.finishedThisStep = true;
      events.add(RacerFinished(racer));
      if (race.progress.every((RacerProgress other) => other.finished)) {
        race.phase = RacePhase.finished;
        finishedThisStep = true;
        events.add(const RaceFinished());
      }
    }
  }

  /// Puts a car back when it has fallen off the world or spent too long off the
  /// track.
  void _recover(int index, double dt) {
    final racer = race.progress[index];
    final vehicle = vehicles[index];

    if (racer.offRoad) {
      _offRoadFor[index] += dt;
    } else {
      _offRoadFor[index] = 0.0;
    }

    final fell = vehicle.position.y < killPlane;
    final lost = _offRoadFor[index] > offRoadPatience;
    if (!fell && !lost) return;

    // Back to the last checkpoint reached, facing the way the track goes. Not
    // to where it left the road: a car put back where it went off is a car put
    // back into the wall it went off into.
    final checkpoints = race.track.checkpoints;
    final at = racer.nextCheckpoint == 0
        ? 0.0
        : checkpoints[racer.nextCheckpoint - 1];

    race.track.frameAt(at, _frame);
    _spawn
      ..setFrom(_frame.position)
      ..y += 1.0;
    vehicle.placeAt(
      _spawn,
      math.atan2(_frame.forward.x, _frame.forward.z),
      trackDistance: at,
    );

    _previousS[index] = race.track.centre.wrap(at);
    _backwards[index] = 0.0;
    _offRoadFor[index] = 0.0;
    racer
      ..s = _previousS[index]
      ..offRoad = false
      ..wrongWay = false
      ..respawnedThisStep = true;
    events.add(Respawned(racer));

    // No `reindex` here, unlike the platformer's revive. That one runs at the
    // top of a step and returns before the step's own reindex; this runs at the
    // bottom, after the overlaps have dispatched, and the next step reindexes
    // before anything sweeps. A call here would be one nobody could observe.
  }

  /// Whether moving [moved] metres on from [from] passes [mark] going forwards.
  ///
  /// Both ends wrap, so the mark is tried a lap either side as well: a step that
  /// crosses the finish line has a `from` near the length and a mark at nought.
  static bool _swept(double from, double moved, double mark, double length) {
    final to = from + moved;
    for (final candidate in <double>[mark - length, mark, mark + length]) {
      if (candidate > from && candidate <= to) return true;
    }
    return false;
  }

  /// The shorter of the two ways round from [from] to [to], signed.
  static double _shortestDelta(double from, double to, double length) {
    var delta = (to - from) % length;
    if (delta > length / 2) delta -= length;
    return delta;
  }

  /// The race, the cars, and what this class remembers between steps.
  ///
  /// **The racing game could not be saved at all**, alone among the three:
  /// `save`/`restore` did not appear anywhere in the package. The other two
  /// have had them since they were written, and a snapshot is the same object
  /// three times over — a save file, a network packet and the input to a
  /// determinism test — so the gap was three gaps.
  ///
  /// What is here beyond the obvious is this class's own bookkeeping, and it is
  /// the half that is easy to forget because it is invisible: how far round the
  /// lap each car was last step, how long it has been going the wrong way, and
  /// how long it has been off the road. Drop them and a restored race
  /// immediately tells the leader they are going backwards, or gives a car that
  /// was one second from being put back on the track a fresh four.
  /// **A [Snapshot], which this one was not.** It returned a bare map, so it
  /// had no version, could not refuse a document from a newer build, and did
  /// not fit `RunSession.snapshotOf` — the signature every other genre answers.
  /// The one save mechanism the architecture describes had two users out of
  /// three.
  Snapshot save() => Snapshot(<String, Object?>{
    'race': race.save(),
    'cars': <Map<String, Object?>>[
      for (final vehicle in vehicles) vehicle.save(),
    ],
    'previousS': List<double>.of(_previousS),
    'backwards': List<double>.of(_backwards),
    'offRoadFor': List<double>.of(_offRoadFor),
    // Declared by this class and saved by neither of the two lines that used
    // to be here. A circuit's own machinery — a gate, a lamp, whatever a track
    // document names — came back at whatever state the level file starts in.
    if (mechanisms != null) 'mechanisms': mechanisms!.save(),
  });

  void restore(Snapshot snapshot) {
    final from = snapshot.data;
    final saved = from.object('race');
    if (saved != null) race.restore(saved);

    final cars = from['cars'];
    if (cars is List) {
      for (var i = 0; i < vehicles.length && i < cars.length; i++) {
        final row = cars[i];
        if (row is Map) vehicles[i].restore(row.cast<String, Object?>());
      }
    }

    _restoreDoubles(from['previousS'], _previousS);
    _restoreDoubles(from['backwards'], _backwards);
    _restoreDoubles(from['offRoadFor'], _offRoadFor);

    mechanisms?.restore(from['mechanisms']);

    // **`reindex` alone was a third of the job.** The broadphase disagrees
    // with every car that moved, which that call fixes — but the overlap set
    // and the kinematic deltas still describe the pre-restore world, so the
    // first step after a load dispatched somebody else's contacts. See
    // `WorldStep.afterRestore`, which is the whole tail and is what the other
    // two genres were already calling.
    _world.afterRestore();
    finishedThisStep = false;
  }

  static void _restoreDoubles(Object? from, List<double> into) {
    if (from is! List) return;
    for (var i = 0; i < into.length && i < from.length; i++) {
      final value = from[i];
      if (value is num) into[i] = value.toDouble();
    }
  }

  final List<double> _previousS = <double>[];
  final List<double> _backwards = <double>[];
  final List<double> _offRoadFor = <double>[];
  final VehicleInput _held = VehicleInput();
  final TrackFrame _frame = TrackFrame();
  final Vector3 _offset = Vector3.zero();
  final Vector3 _between = Vector3.zero();
  final Vector3 _spawn = Vector3.zero();
}
