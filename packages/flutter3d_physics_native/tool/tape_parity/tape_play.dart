// The racing and shooter tapes played on the core for a thousand steps, the
// world's digest taken every hundred: the half of the tape parity both entry
// points share, `tape_digests_test.dart` (the VM, dart2js and dart2wasm) and
// `tape_digests_device_test.dart` (a phone, through `flutter test -d`).
//
// **A thousand steps of a shorter tape is the tape looped**: when it ends,
// its frames are played again from the first into the same run, so the
// world goes on from where it was rather than starting over. The racing
// tape is 600 steps and the shooter's 220.
//
// **The world's digest** is `StateDigest` of the run's whole save, the one a
// `.f3drun` checkpoint holds and rollback compares machines by: the bodies
// the core stepped and everything the game kept beside them. Two targets
// that print the same digests stepped the same world to the bit.
// ignore_for_file: depend_on_referenced_packages
library;

import 'dart:convert';

import 'package:flutter3d_demo_content/shooter_staging.dart'
    show ShooterHeadlessGame;
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart'
    show RacingHeadlessGame, TrackDocument;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Steps each tape is played for.
const int tapeSteps = 1000;

/// Steps between digests.
const int digestEvery = 100;

/// The tapes, in the order they are played.
const List<String> tapes = <String>['racing', 'shooter'];

const double _dt = 1.0 / 60.0;

/// The crypt names a `widget_surface`, which the application draws a widget
/// on and the simulation never reads; this is that kind without Flutter.
final class _WidgetSurfaceKind extends EntityKind {
  const _WidgetSurfaceKind() : super('widget_surface');
}

/// Loads the core (in a browser from [wasmUrl]) and chooses it; throws when
/// this target would fall back to the Dart reference, which measures nothing
/// of the core.
Future<String> startCore({String wasmUrl = defaultPhysicsCoreUrl}) async {
  await loadPhysicsCore(url: wasmUrl);
  final started = await startPhysics(asked: 'native');
  if (started.fallbackBecause case final String because) {
    throw StateError('the core did not start here: $because');
  }
  return started.backend.name;
}

/// Plays tape [name] reading its files through [read], and returns its
/// lines: a `parity racing start 1a2b3c4d` line, then one such as
/// `parity racing 100 5e6f7a8b` every [digestEvery] steps.
Future<List<String>> playTape(
  String name,
  Future<String> Function(String file) read,
) async {
  Future<Map<String, Object?>> json(String file) async =>
      (jsonDecode(await read(file)) as Map).cast<String, Object?>();
  switch (name) {
    case 'racing':
      final document = TrackDocument.fromJson(await json('ring.json'));
      return _play(
        name,
        game: RacingHeadlessGame(track: document.track),
        level: document.level!,
        demo: Demo.fromJson(await json('racing.f3drun')),
      );
    case 'shooter':
      return _play(
        name,
        game: const ShooterHeadlessGame(
          extra: <EntityKind>[_WidgetSurfaceKind()],
        ),
        level: Level.fromJson(await json('crypt.json')),
        demo: Demo.fromJson(await json('shooter.f3drun')),
      );
    default:
      throw ArgumentError.value(name, 'name', 'not one of $tapes');
  }
}

List<String> _play(
  String name, {
  required HeadlessGame game,
  required Level level,
  required Demo demo,
}) {
  final physics = usePhysics(asked: 'native');
  final world = CollisionWorld(backend: physics);
  level.addTo(world);
  physics.attach(world);
  final input = InputState();
  final run = game.start(
    HeadlessStart(level: level, world: world, input: input),
  );
  world.update();
  // From the recording's own start, which a fresh staging may miss in a
  // last bit (a heading through the platform's atan2).
  if (run is RestorableRun) run.restore(demo.start);
  final lines = <String>['parity $name start ${_digest(run)}'];

  var playback = InputTapePlayback.tape(demo.tape);
  for (var step = 1; step <= tapeSteps; step++) {
    if (playback.isFinished) playback = InputTapePlayback.tape(demo.tape);
    playback.applyTo(input);
    input.beginStep();
    run.step(_dt);
    input.endStep();
    if (step % digestEvery == 0) {
      lines.add('parity $name $step ${_digest(run)}');
    }
  }
  return lines;
}

/// The digest of [run]'s whole save, as a checkpoint writes it.
String _digest(HeadlessRun run) =>
    StateDigest.of(run.save().toJson()).toRadixString(16).padLeft(8, '0');
