import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_game_kit/soundtrack.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'sounds.dart';

/// What a step of this game sounds like.
///
/// **Split out of `main.dart` so that silence can fail a test.** The decisions
/// lived inside a widget's private method, which meant nothing could ask what a
/// step ought to sound like without a device, a renderer and a window. So the
/// game was mute in a way no test could see: `SoLoudBackend` falls back to
/// `SilentBackend` when it cannot open a device, and every call site went on
/// calling into the silence perfectly happily.
///
/// The same split `RunnerLooks` uses for the pose and `PlatformerLooks` for the
/// coin: deciding is a pure function of the simulation, and playing is an
/// effect somebody else performs.
///
/// This used to end by saying that particles and camera shake stay in the
/// widget because they "are already covered by the frame tests". They were
/// not: no test in this application mentioned a particle, an effect or a
/// shake. They are `Reactions` now, beside this — a sentence that excuses a
/// gap is worth less than no sentence, because it stops the next person from
/// looking.
final class Soundtrack {
  Soundtrack({this.stride = 2.2}) : _feet = Footsteps(stride: stride) {
    // One sound per event, which is what the flags could not do: two coins
    // swept up in one step were one `takenThisStep` entry each and two enemies
    // stomped were a single bool.
    _moments
      ..on<EnemyStomped>(
        (EnemyStomped event, List<Heard> out) =>
            out.add(Heard(Sounds.land, _at)),
      )
      ..on<CheckpointReached>(
        (CheckpointReached event, List<Heard> out) =>
            out.add(Heard(Sounds.checkpoint, _at)),
      )
      ..on<RunnerDied>(
        (RunnerDied event, List<Heard> out) =>
            out.add(Heard(Sounds.death, _at)),
      );
    // **The level's own machinery, which had particles and no sound**, and the
    // coins: each placed by the event itself. A pad that throws you and a
    // shelf that gives way under you are the two loudest things that can
    // happen in this game, and both were silent.
    placed
      ..on<CollectibleTaken>(
        (CollectibleTaken event, List<Heard> out) =>
            out.add(Heard(Sounds.coin, event.collectible.origin)),
      )
      ..on<SpringFired>(
        (SpringFired event, List<Heard> out) =>
            out.add(Heard(Sounds.spring, event.at)),
      )
      ..on<BlockCrumbled>(
        (BlockCrumbled event, List<Heard> out) =>
            out.add(Heard(Sounds.crumble, event.at)),
      )
      ..on<BlockBroke>(
        (BlockBroke event, List<Heard> out) =>
            out.add(Heard(Sounds.crumble, event.at)),
      );
  }

  /// How far the runner walks between footsteps, in metres.
  ///
  /// Distance rather than time, which is the difference between a walk and a
  /// sprint sounding like the same person moving at two speeds and sounding
  /// like two different people. At 6 m/s this is a step every third of a
  /// second, which is about right for something 1.8 m tall.
  final double stride;

  final Footsteps _feet;
  bool _wasFinished = false;

  /// The moments heard where the runner stands on the step they happen in:
  /// a stomp, a checkpoint, a death.
  final CueSheet _moments = CueSheet();

  /// The sounds an event places by itself — a coin where it lay, a spring, a
  /// shelf giving way — and so need nothing of the step but the event.
  ///
  /// **What the game hands a `SoundtrackPlugin`**, which plays them off the
  /// bus's frame channel once a frame, after the frame's steps. That is the
  /// frame they were always played in, from the same places, and a step run
  /// again on a rollback no longer plays them twice. Everything else here
  /// reads the runner as one step left it, which the frame channel cannot
  /// give back on a frame of two steps, and stays in [heardOnStep].
  final CueSheet placed = CueSheet();

  /// Where the runner is on the step being heard.
  Vector3 _at = Vector3.zero();

  /// Everything this step made a noise about: [heardOnStep], then [placed].
  ///
  /// Called once per simulation step, in order, and the list is what to play.
  /// What a test asks; the game plays [placed] through its plugin.
  List<Heard> listen(
    PlatformerSimulation sim,
    Runner runner,
    List<GameEvent> events,
  ) => heardOnStep(sim, runner, events)..addAll(placed.listen(events));

  /// What this step made a noise about that needs the runner as the step left
  /// it: the jumps, the landing, the footsteps, the end of the level, and the
  /// moments heard where the runner stands. Not [placed].
  ///
  /// Called once per simulation step, in order, and the list is what to play.
  List<Heard> heardOnStep(
    PlatformerSimulation sim,
    Runner runner,
    List<GameEvent> events,
  ) {
    final out = <Heard>[];
    final at = runner.position;
    _at = at;

    if (events.whereType<Jumped>().isNotEmpty) {
      out.add(
        Heard(runner.airJumpsLeft < 1 ? Sounds.airJump : Sounds.jump, at),
      );
    }
    if (events.whereType<Dashed>().isNotEmpty) out.add(Heard(Sounds.dash, at));
    // A long jump is the slide it came out of, launched: it gets the dash's
    // sound because it is the same commitment at a different angle.
    if (events.whereType<LongJumped>().isNotEmpty) {
      out.add(Heard(Sounds.dash, at));
    }
    if (events.whereType<Grabbed>().isNotEmpty) {
      out.add(Heard(Sounds.checkpoint, at));
    }

    _moments.hear(events, out);

    // **Decided here, and it was the one sound that was not.** The application
    // played this itself, beside the camera kick that goes with it, which left
    // two homes for "what does this step sound like" — and the second one was
    // in a widget, so the landing was the one sound in the game no test could
    // ask about. The camera's half stays where it is; only the decision moved.
    if (events.whereType<Landed>().isNotEmpty) out.add(Heard(Sounds.land, at));

    // Once, on the step the run ends. `RunState.finished` stays true for every
    // frame afterwards, and a fanfare restarted sixty times a second is a
    // buzzer.
    final finished = sim.state == RunState.finished;
    if (finished && !_wasFinished) out.add(Heard(Sounds.exit, at));
    _wasFinished = finished;

    // Footsteps, only while the feet are down and off the ladder.
    if (_feet.walked(
      at,
      grounded: runner.isGrounded && runner.climbing == null,
    )) {
      out.add(Heard(Sounds.stepOn(runner.standingOn), at));
    }
    return out;
  }

  /// For a level change or a restart: a fresh run makes its own noises.
  void reset() {
    _feet.reset();
    _wasFinished = false;
  }
}
