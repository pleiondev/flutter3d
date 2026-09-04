import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:vector_math/vector_math.dart';

import 'sounds.dart';

/// What is happening to a sound that has a lifetime.
enum Voice {
  /// Start it, at [Sustained.at].
  begin,

  /// It is still running, and this is where it is now.
  follow,

  /// Stop it.
  end,
}

/// A sound with a lifetime: it starts, it follows the thing making it, and it
/// stops.
///
/// **Still this game's, while [Heard] moved to the audio package.** The rule is
/// the second consumer, and there is not one: the platformer has no sound that
/// outlives a step, and the racing game's engine is not this shape either — it
/// is one voice per car that never stops and is modulated rather than begun and
/// ended. Moving this on the strength of one user would be guessing what the
/// second one needs, and the second one is exactly what makes a shape right.
///
/// **Not the same as a [Heard], and the difference is the whole reason this
/// class exists.** A shot is over before the next step; a stone door grinding
/// open runs for as long as the door moves, has to be repositioned while it
/// runs, and has to be stopped by the same key that started it. Emitting that
/// as a one-shot per step would be a door that stutters instead of grinds.
///
/// The lifetime is decided here rather than in the caller, which is what makes
/// the caller a player rather than a bookkeeper: it holds a map of voices by
/// key and does exactly what each of these says.
final class Sustained {
  const Sustained.begin(this.key, SoundDef this.sound, Vector3 this.at)
    : what = Voice.begin;
  const Sustained.follow(this.key, Vector3 this.at)
    : what = Voice.follow,
      sound = null;
  const Sustained.end(this.key) : what = Voice.end, sound = null, at = null;

  final Voice what;

  /// Whatever is making the noise. The mechanism itself, so two doors are two
  /// voices and the same door twice is one.
  final Object key;

  /// Only on [Voice.begin]: which sound to start.
  final SoundDef? sound;

  /// Where it is now. Null only when stopping.
  final Vector3? at;
}

/// Everything one step made a noise about.
final class Sounding {
  const Sounding(this.once, this.loops);

  final List<Heard> once;
  final List<Sustained> loops;
}

/// What a step of this game sounds like.
///
/// **Split out of `main.dart` so that silence can fail a test.** The decisions
/// lived in eight `_audio.play` calls inside a widget's private methods, which
/// meant nothing could ask what a step ought to sound like without a device, a
/// renderer and a window. So the game was mute in a way no test could see:
/// `SoLoudBackend` falls back to `SilentBackend` when it cannot open a device,
/// and every call site went on calling into the silence perfectly happily.
///
/// The platformer went through this and the split found a real hole — six of
/// its fourteen sounds were never in the bank, and it had been half mute for
/// months. Here the hole was visible from the outside: four weapons and two
/// sounds.
///
/// Playing, stopping and repositioning are somebody else's. This decides.
final class Soundtrack {
  Soundtrack({this.stride = 1.9});

  /// How far the player walks between footsteps, in metres.
  ///
  /// Distance rather than time, which is the difference between a walk and a
  /// sprint sounding like the same person at two speeds and sounding like two
  /// different people. Shorter than the platformer's 2.2 because this game is
  /// played from inside the head: your own footsteps are closer together than
  /// somebody else's look.
  final double stride;

  double _sinceStep = 0.0;
  final Vector3 _wasAt = Vector3.zero();
  bool _placed = false;

  /// The mechanisms whose voices are running, so this can say where each one is
  /// on every step. Held here rather than by the caller for the same reason
  /// everything else is: a caller keeping its own set is a second answer to
  /// which sounds are playing.
  final Set<Mechanism> _running = <Mechanism>{};

  /// Called once per simulation step, in order.
  Sounding listen(GameSimulation sim, Player player, List<GameEvent> events) {
    final once = <Heard>[];
    final loops = <Sustained>[];
    final at = player.body.position;

    for (final GameEvent event in events) {
      switch (event) {
        case ShotFired():
          // At the eye rather than at the muzzle, for the same reason the shot
          // starts there: a sound half a metre to one side pans audibly wrong
          // when the player is against a wall.
          once.add(Heard(forWeapon(event.weapon), event.from));
        case ActorDied():
          final where = event.actor.position;
          if (where != null) once.add(Heard(Sounds.monsterDie, where));
        case ActorHurt():
          // Only the ones that flinched. A hit that did not stagger reads as a
          // hit that did not land, and every hit screaming is worse than none.
          final where = event.actor.position;
          if (event.staggered && where != null) {
            once.add(Heard(Sounds.monsterPain, where));
          }
        case MechanismUsed(outcome: Refused()):
          // A door that will not open. The refusal is the simulation's; saying
          // so is this.
          once.add(Heard(Sounds.locked, at));
      }
    }

    final mechanisms = sim.mechanisms;
    if (mechanisms != null) _machinery(mechanisms, at, once, loops);

    _step(player, at, once);
    return Sounding(once, loops);
  }

  /// What a weapon sounds like.
  ///
  /// **Public because it is the claim worth testing on its own.** The
  /// application asked `ammo == shells ? shotgun : pistol`, which is four
  /// weapons and two sounds — and there is no run of the game that makes that
  /// obvious, because you have to fire all four and remember.
  SoundDef forWeapon(WeaponDef weapon) => switch (weapon.ammo) {
    AmmoType.shells => Sounds.shotgun,
    AmmoType.rockets => Sounds.rocket,
    AmmoType.none => Sounds.punch,
    AmmoType.bullets => Sounds.pistol,
  };

  void _machinery(
    MechanismWorld mechanisms,
    Vector3 at,
    List<Heard> once,
    List<Sustained> loops,
  ) {
    for (final started in mechanisms.events.started) {
      _running.add(started);
      loops.add(
        Sustained.begin(started, Sounds.stoneMove, started.origin ?? at),
      );
    }
    for (final stopped in mechanisms.events.stopped) {
      _running.remove(stopped);
      loops.add(Sustained.end(stopped));
      once.add(Heard(Sounds.stoneStop, stopped.origin ?? at));
    }
    // Where each running voice is now. A door that is opening moves, and a
    // sound left where the door started drifts away from it — which on a lift
    // is a grinding noise that stays in the floor you left.
    for (final running in _running) {
      final where = running.origin;
      if (where != null) loops.add(Sustained.follow(running, where));
    }

    for (final taken in mechanisms.events.taken) {
      once.add(Heard(Sounds.pickup, taken.origin ?? at));
    }
  }

  /// Footsteps, paid for in metres travelled on the ground.
  void _step(Player player, Vector3 at, List<Heard> out) {
    if (!_placed) {
      _wasAt.setFrom(at);
      _placed = true;
      return;
    }

    final moved = Vector3(at.x - _wasAt.x, 0.0, at.z - _wasAt.z).length;
    _wasAt.setFrom(at);

    // Only while the feet are down. A player crossing a gap covers ground and
    // takes no steps, and hearing footsteps in mid-air is the sort of thing
    // nobody reports and everybody notices.
    if (!player.body.isGrounded) {
      _sinceStep = stride * 0.6;
      return;
    }

    _sinceStep += moved;
    if (_sinceStep < stride) return;
    _sinceStep = 0.0;
    out.add(Heard(Sounds.step, at));
  }

  /// For a level change or a restart: a fresh level makes its own noises.
  void reset() {
    _sinceStep = 0.0;
    _placed = false;
    _running.clear();
  }
}
