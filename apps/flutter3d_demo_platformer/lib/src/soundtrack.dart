import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
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
  Soundtrack({this.stride = 2.2});

  /// How far the runner walks between footsteps, in metres.
  ///
  /// Distance rather than time, which is the difference between a walk and a
  /// sprint sounding like the same person moving at two speeds and sounding
  /// like two different people. At 6 m/s this is a step every third of a
  /// second, which is about right for something 1.8 m tall.
  final double stride;

  double _sinceStep = 0.0;
  bool _wasFinished = false;

  final Vector3 _wasAt = Vector3.zero();
  bool _placed = false;

  /// Everything this step made a noise about.
  ///
  /// Called once per simulation step, in order, and the list is what to play.
  List<Heard> listen(
    PlatformerSimulation sim,
    Runner runner,
    List<GameEvent> events,
  ) {
    final out = <Heard>[];
    final at = runner.position;

    if (events.has<Jumped>()) {
      out.add(
        Heard(runner.airJumpsLeft < 1 ? Sounds.airJump : Sounds.jump, at),
      );
    }
    if (events.has<Dashed>()) out.add(Heard(Sounds.dash, at));
    // A long jump is the slide it came out of, launched: it gets the dash's
    // sound because it is the same commitment at a different angle.
    if (events.has<LongJumped>()) out.add(Heard(Sounds.dash, at));
    if (events.has<Grabbed>()) out.add(Heard(Sounds.checkpoint, at));

    // One sound per event, which is what the flags could not do: two coins
    // swept up in one step were one `takenThisStep` entry each and two enemies
    // stomped were a single bool.
    for (final GameEvent event in events) {
      switch (event) {
        case CollectibleTaken():
          out.add(Heard(Sounds.coin, event.collectible.origin));
        case EnemyStomped():
          out.add(Heard(Sounds.land, at));
        case CheckpointReached():
          out.add(Heard(Sounds.checkpoint, at));
        case RunnerDied():
          out.add(Heard(Sounds.death, at));
      }
    }

    // **Decided here, and it was the one sound that was not.** The application
    // played this itself, beside the camera kick that goes with it, which left
    // two homes for "what does this step sound like" — and the second one was
    // in a widget, so the landing was the one sound in the game no test could
    // ask about. The camera's half stays where it is; only the decision moved.
    if (events.has<Landed>()) out.add(Heard(Sounds.land, at));

    // **The level's own machinery, which had particles and no sound.** A pad
    // that throws you and a shelf that gives way under you are the two loudest
    // things that can happen in this game, and both were silent.
    for (final GameEvent event in events) {
      switch (event) {
        case SpringFired():
          out.add(Heard(Sounds.spring, event.at));
        case BlockCrumbled() || BlockBroke():
          out.add(Heard(Sounds.crumble, (event as FurnitureEvent).at));
      }
    }

    // Once, on the step the run ends. `RunState.finished` stays true for every
    // frame afterwards, and a fanfare restarted sixty times a second is a
    // buzzer.
    final finished = sim.state == RunState.finished;
    if (finished && !_wasFinished) out.add(Heard(Sounds.exit, at));
    _wasFinished = finished;

    _step(runner, at, out);
    return out;
  }

  /// Footsteps, paid for in metres travelled on the ground.
  void _step(Runner runner, Vector3 at, List<Heard> out) {
    if (!_placed) {
      _wasAt.setFrom(at);
      _placed = true;
      return;
    }

    final moved = Vector3(at.x - _wasAt.x, 0.0, at.z - _wasAt.z).length;
    _wasAt.setFrom(at);

    // Only while the feet are down. A runner crossing a gap covers ground and
    // takes no steps, and hearing footsteps in mid-air is the sort of thing
    // nobody reports and everybody notices.
    if (!runner.isGrounded || runner.climbing != null) {
      _sinceStep = stride * 0.6;
      return;
    }

    _sinceStep += moved;
    if (_sinceStep < stride) return;
    _sinceStep = 0.0;
    out.add(Heard(Sounds.stepOn(runner.standingOn), at));
  }

  /// For a level change or a restart: a fresh run makes its own noises.
  void reset() {
    _sinceStep = 0.0;
    _wasFinished = false;
    _placed = false;
  }
}
