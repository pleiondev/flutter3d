/// The lap somebody already drove, kept and drawn beside the one they are on.
///
///     flutter test test/ghost_test.dart
///
/// **Two hundred and ninety lines of ghost were written, tested and never
/// used.** `GhostRecorder`, `GhostTape` and `GhostPlayer` have been in the
/// racing package since it existed, with a test file of their own — and the
/// game called none of them. Nothing recorded a lap, nothing kept one and
/// nothing drew one. This file is about the half that was missing: whether a
/// best lap reaches the disk, comes back off it, and ends up somewhere on the
/// track.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing/src/ghost_car.dart';
import 'package:vector_math/vector_math.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// A car that goes where it is put, so a test about keeping a lap is not also a
/// test about driving one.
final class _Car implements VehicleController {
  _Car()
      : collider =
            Collider(shape: CollisionSphere(0.7), position: Vector3.zero());

  @override
  final Collider collider;

  @override
  Vector3 get position => collider.position;

  @override
  final Vector3 velocity = Vector3.zero();

  @override
  double headingYaw = 0.0;

  final Matrix3 _basis = Matrix3.identity();

  @override
  Matrix3 get visualBasis => _basis;

  @override
  double get speed => velocity.length;

  @override
  double slipAngle = 0.0;

  @override
  double slipRatio = 0.0;

  @override
  bool grounded = true;

  @override
  double rpm = 0.0;

  @override
  double trackDistance = 0.0;

  @override
  void step(double dt, VehicleInput input) {}

  @override
  void placeAt(Vector3 at, double yaw, {double? trackDistance}) {
    collider.position.setFrom(at);
    headingYaw = yaw;
  }

  /// A stand-in car keeps nothing between steps, so there is nothing to save.
  /// The interface still asks, because a race that can be saved has to be able
  /// to save whatever is driving in it.
  @override
  Map<String, Object?> save() => const <String, Object?>{};

  @override
  void restore(Map<String, Object?> from) {}
}

/// Drives [seconds] of a straight line at 20 m/s past the keeper, at 60 Hz,
/// which is how the game calls it.
void _drive(GhostKeeper keeper, {double seconds = 4.0, double from = 0.0}) {
  final car = _Car();
  for (var step = 0; step * (1 / 60.0) <= seconds; step++) {
    final time = step / 60.0;
    car.position.setValues(from + time * 20.0, 0.0, 0.0);
    keeper.watch(time, car);
  }
}

GhostKeeper _keeper(_Storage storage, {String track = 'assets/tracks/ring.json'}) =>
    GhostKeeper(storage: storage, track: track);

void main() {
  test('a best lap is still there the next time the game starts', () {
    // The reason any of it exists. A lap driven and then lost at the window
    // close is a lap nobody drove.
    final storage = _Storage();
    final keeper = _keeper(storage);
    _drive(keeper, seconds: 4.0);

    expect(keeper.finished(4.0), isTrue);

    final afterRelaunch = _keeper(storage)..load();

    expect(afterRelaunch.best, isNotNull);
    expect(afterRelaunch.best!.lapTime, closeTo(4.0, 1e-3));
    // Eighty metres is where four seconds at twenty a second ends; the last
    // sample lands a fifteenth of a second short of the line, which is why the
    // tape carries the lap time separately from its own last stamp.
    expect(afterRelaunch.best!.poses.last.position.x, closeTo(79.0, 1.5),
        reason: 'it kept the shape of a lap but not where the lap went');
  });

  test('and a slower lap does not take its place', () {
    // Mutation: keep every lap. The ghost would be whatever was driven last,
    // which is the opposite of what a player is racing against.
    //
    // The keeper decides this itself now, against the record on disk. It used
    // to be told, by a simulation whose "best so far" began each race empty —
    // see the record's own test below for what that cost.
    final storage = _Storage();
    final keeper = _keeper(storage);
    _drive(keeper, seconds: 4.0);
    keeper.finished(4.0);

    _drive(keeper, seconds: 9.0, from: 500.0);
    expect(keeper.finished(9.0), isFalse);

    expect(keeper.best!.lapTime, closeTo(4.0, 1e-3));
    expect(_keeper(storage).let((k) => k..load()).best!.lapTime,
        closeTo(4.0, 1e-3),
        reason: 'the disk kept the slow lap even though memory did not');
  });

  test('and the lap after a kept one is a lap, not two of them', () {
    // Mutation: drop the reset. The second tape would begin at the first
    // lap's start line, and a ghost of it would drive the previous lap again
    // before it drove this one.
    final storage = _Storage();
    final keeper = _keeper(storage);
    _drive(keeper, seconds: 4.0);
    keeper.finished(4.0);

    _drive(keeper, seconds: 3.0, from: 500.0);
    keeper.finished(3.0);

    expect(keeper.best!.poses.first.position.x, closeTo(500.0, 0.5),
        reason: 'the new lap starts where the old one did');
    expect(keeper.best!.poses.first.time, closeTo(0.0, 1e-6));
  });

  test('and a lap nobody really drove is not kept', () {
    // Four samples is a third of a second of recording. A "lap" that short is
    // somebody who reversed over the line, and a ghost of it would be a car
    // sliding a few metres across the infield every lap forever.
    final storage = _Storage();
    final keeper = _keeper(storage);
    _drive(keeper, seconds: 0.1);

    expect(keeper.finished(0.1), isFalse);
    expect(keeper.best, isNull);
    expect(storage.documents, isEmpty);
  });

  test('and a lap of one circuit is not offered on another', () {
    // Mutation: one filename for every track. A best lap of the ring drawn on
    // a different circuit is a car driving through the scenery.
    final storage = _Storage();
    final ring = _keeper(storage, track: 'assets/tracks/ring.json');
    _drive(ring, seconds: 4.0);
    ring.finished(4.0);

    final elsewhere = _keeper(storage, track: 'assets/tracks/other.json')
      ..load();

    expect(elsewhere.best, isNull);
    expect(storage.documents.keys, contains('ghost-ring.json'));
  });

  test('and a file that will not read costs a lap, not the game', () {
    final storage = _Storage();
    storage.documents['ghost-ring.json'] = 'this is not a lap';

    final keeper = _keeper(storage);
    expect(keeper.load, returnsNormally);

    expect(keeper.best, isNull);
    expect(storage.documents, isEmpty,
        reason: 'it will fail to read the same file every launch');
  });

  group('one step of a race', () {
    /// Drives a lap the way the game does: every step, through [stepped],
    /// with the simulation's own idea of when a lap ends.
    ///
    /// The finishing step is what this is for. It arrives with `lapTime`
    /// already back at nought and the lap's real length in `lastLap`, because
    /// that is what `Simulation._readLine` leaves behind.
    GhostKeeper lapThrough(
      GhostKeeper keeper, {
      required double seconds,
      required bool best,
      double from = 0.0,
    }) {
      final car = _Car();
      final player = RacerProgress(index: 0);
      for (var step = 0; step * (1 / 60.0) < seconds; step++) {
        player.lapTime = step / 60.0;
        car.position.setValues(from + player.lapTime * 20.0, 0.0, 0.0);
        keeper.stepped(player, car);
      }
      player
        ..lastLap = seconds
        ..lapTime = 0.0
        ..lapCompletedThisStep = true
        ..bestLapThisStep = best;
      keeper.stepped(player, car);
      return keeper;
    }

    test('leaves a lap that can actually be drawn', () {
      // **What was nearly asserted here and turned out to be false**: that
      // sampling before closing the lap would append a frame stamped nought,
      // ending the tape before its own beginning and hiding the ghost forever.
      // Swapping the two lines was tried, and the test kept passing — the
      // recorder drops that frame, because its next sample is not due yet. The
      // test that survives says the thing that matters instead: a lap that was
      // recorded through this method is a lap that appears on screen.
      final storage = _Storage();
      final keeper = lapThrough(_keeper(storage), seconds: 4.0, best: true);

      final tape = keeper.best!;
      expect(tape.poses.last.time, greaterThan(3.0),
          reason: 'the tape ends before it began');

      final ghost = GhostCar(SceneNode(name: 'ghost'));
      ghost.showAt(2.0, tape, 0.0);
      expect(ghost.node.visible, isTrue,
          reason: 'a recorded lap that can never be drawn');
    });

    test('and the lap after it is one lap long, not two', () {
      // The closing step samples the new lap at the line, which is where the
      // car is — so the second tape starts at nought and covers its own three
      // seconds. A missing reset would give it seven.
      final keeper = lapThrough(_keeper(_Storage()), seconds: 4.0, best: true);
      lapThrough(keeper, seconds: 3.0, best: true, from: 500.0);

      final tape = keeper.best!;
      expect(tape.poses.first.time, closeTo(0.0, 1e-6));
      expect(tape.poses.last.time, closeTo(3.0, 0.2),
          reason: 'the second tape is ${tape.poses.last.time}s of recording');
      expect(tape.lapTime, closeTo(3.0, 1e-6));
    });
  });

  group('the record', () {
    test('is what a lap is measured against, not this session', () {
      // **The bug the record found, and it destroyed things.** `finished` used
      // to be handed the simulation's `bestLapThisStep`, and a race starts with
      // no laps in it — so the first lap of every launch was the best one by
      // definition. The out-lap somebody drove while getting used to the car
      // took the place of a record set on another evening, and the ghost they
      // were about to race went with it.
      final storage = _Storage();
      final keeper = _keeper(storage);
      _drive(keeper, seconds: 4.0);
      keeper.finished(4.0);

      // A new launch: nothing in memory, everything on disk.
      final relaunched = _keeper(storage)..load();
      _drive(relaunched, seconds: 9.0, from: 500.0);

      expect(relaunched.finished(9.0), isFalse,
          reason: 'the out-lap of a new launch took the record');
      expect(relaunched.record, closeTo(4.0, 1e-3));
      expect(relaunched.best!.poses.first.position.x, closeTo(0.0, 0.5),
          reason: 'the record is 4s and the ghost is the nine-second lap');
    });

    test('and is the tape\'s own time, so the two cannot disagree', () {
      // One document. A record kept beside the ghost could say 1:58 with a
      // two-minute car on the track, and there would be no telling which of the
      // two was lying.
      final keeper = _keeper(_Storage());
      expect(keeper.record, isNull);

      _drive(keeper, seconds: 4.0);
      keeper.finished(4.0);

      expect(keeper.record, keeper.best!.lapTime);
    });

    test('and a lap that beats it says so, once', () {
      // What the screen is told. The line only flashes on the step the record
      // moved: a game that said it every step would be a game that never
      // stopped saying it.
      final storage = _Storage();
      final keeper = _keeper(storage);
      final car = _Car();
      final player = RacerProgress(index: 0);

      for (var step = 0; step * (1 / 60.0) < 4.0; step++) {
        player.lapTime = step / 60.0;
        car.position.setValues(player.lapTime * 20.0, 0.0, 0.0);
        expect(keeper.stepped(player, car), isFalse,
            reason: 'a record was announced mid-lap');
      }
      player
        ..lastLap = 4.0
        ..lapTime = 0.0
        ..lapCompletedThisStep = true;

      expect(keeper.stepped(player, car), isTrue);

      player.lapCompletedThisStep = false;
      expect(keeper.stepped(player, car), isFalse,
          reason: 'it went on announcing the same record');
    });

    test('and a lap that does not beat it says nothing', () {
      final storage = _Storage();
      final keeper = _keeper(storage);
      _drive(keeper, seconds: 4.0);
      keeper.finished(4.0);

      final car = _Car();
      final player = RacerProgress(index: 0);
      for (var step = 0; step * (1 / 60.0) < 6.0; step++) {
        player.lapTime = step / 60.0;
        car.position.setValues(500.0 + player.lapTime * 20.0, 0.0, 0.0);
        keeper.stepped(player, car);
      }
      player
        ..lastLap = 6.0
        ..lapTime = 0.0
        ..lapCompletedThisStep = true;

      expect(keeper.stepped(player, car), isFalse);
      expect(keeper.record, closeTo(4.0, 1e-3));
    });
  });

  test('and the game itself is the thing that calls all of it', () {
    // **The failure this whole file is a fix for, and it has to be a scan.**
    // Every class here was written, tested and left uncalled for as long as the
    // game existed; a test suite full of green ticks said nothing about that,
    // because the calls sit in a private method of a widget no test can mount.
    // Reading the source is crude and it is the only thing that fails when the
    // ghost quietly stops being recorded or drawn.
    final game = File('lib/main.dart').readAsStringSync();

    expect(game, contains('.stepped('),
        reason: 'nothing records a lap, so there will never be a ghost');
    expect(game, contains('.showAt('),
        reason: 'laps are recorded and kept, and nothing draws one');
    expect(game, contains('.load()'),
        reason: 'a best lap is written and never read back');
    expect(game, contains('_ghosts.record'),
        reason: 'the record is kept and the screen never says what it is');
  });

  group('the car it is drawn as', () {
    GhostTape recordedLap() {
      final storage = _Storage();
      final keeper = _keeper(storage);
      _drive(keeper, seconds: 4.0);
      keeper.finished(4.0);
      return keeper.best!;
    }

    test('is where the lap was at this point of the lap being driven', () {
      final ghost = GhostCar(SceneNode(name: 'ghost'));

      ghost.showAt(2.0, recordedLap(), 0.0);

      expect(ghost.node.visible, isTrue);
      // Two seconds into a straight line at twenty metres a second.
      expect(ghost.node.localMatrix.getTranslation().x, closeTo(40.0, 0.5));
    });

    test('and is hidden rather than parked where the recording ran out', () {
      // Mutation: leave it where it was. A ghost that stops at the point the
      // tape ended reads as a car abandoned on the racing line — and on a lap
      // slower than the recorded one, that is most of the lap.
      final ghost = GhostCar(SceneNode(name: 'ghost'));
      final lap = recordedLap();

      ghost.showAt(2.0, lap, 0.0);
      expect(ghost.node.visible, isTrue);

      ghost.showAt(99.0, lap, 0.0);

      expect(ghost.node.visible, isFalse);
    });

    test('and is lifted along its own up, not the world\'s', () {
      // The same reason the cars are: on a cambered corner the two differ by
      // most of a metre, and a ghost lifted vertically sinks into the banking.
      final tape = GhostTape(seconds: 1.0, poses: <GhostFrame>[
        GhostFrame(time: 0.0)..up.setValues(1.0, 0.0, 0.0),
        GhostFrame(time: 1.0)..up.setValues(1.0, 0.0, 0.0),
      ]);
      final ghost = GhostCar(SceneNode(name: 'ghost'));

      ghost.showAt(0.5, tape, 0.5);

      expect(ghost.node.localMatrix.getTranslation().x, closeTo(0.5, 1e-3));
      expect(ghost.node.localMatrix.getTranslation().y, closeTo(0.0, 1e-3));
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
