import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_game_kit/soundtrack.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'sounds.dart';

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
  Soundtrack({this.stride = 1.9}) : _feet = Footsteps(stride: stride) {
    _cues
      ..on<ShotFired>((ShotFired event, List<Heard> out) {
        // At the eye rather than at the muzzle, for the same reason the shot
        // starts there: a sound half a metre to one side pans audibly wrong
        // when the player is against a wall.
        out.add(Heard(forWeapon(event.weapon), event.from));
      })
      ..on<ActorDied>((ActorDied event, List<Heard> out) {
        final where = event.actor.position;
        if (where != null) out.add(Heard(Sounds.monsterDie, where));
      })
      ..on<ActorHurt>((ActorHurt event, List<Heard> out) {
        // Only the ones that flinched. A hit that did not stagger reads as a
        // hit that did not land, and every hit screaming is worse than none.
        final where = event.actor.position;
        if (event.staggered && where != null) {
          out.add(Heard(Sounds.monsterPain, where));
        }
      })
      ..on<SequenceSignal>((SequenceSignal event, List<Heard> out) {
        // A cutscene names the sound it wants and where, in the level's own
        // document; a name this bank has not got is silence rather than a
        // guess. Where it is not said, at the player.
        final named = event.data['sound'];
        final sound = Sounds.all
            .where((SoundDef s) => s.name == named)
            .firstOrNull;
        if (sound != null) {
          out.add(Heard(sound, _place(event.data['at']) ?? _at));
        }
      })
      ..on<MechanismUsed>((MechanismUsed event, List<Heard> out) {
        // A door that will not open. The refusal is the simulation's; saying
        // so is this.
        if (event.outcome is Refused) out.add(Heard(Sounds.locked, _at));
      });
  }

  /// How far the player walks between footsteps, in metres.
  ///
  /// Distance rather than time, which is the difference between a walk and a
  /// sprint sounding like the same person at two speeds and sounding like two
  /// different people. Shorter than the platformer's 2.2 because this game is
  /// played from inside the head: your own footsteps are closer together than
  /// somebody else's look.
  final double stride;

  final Footsteps _feet;

  /// What each event sounds like: the soundtrack addon's cue sheet, with this
  /// game's rows.
  final CueSheet _cues = CueSheet();

  /// Where the player is on the step being heard, for the cues that sound
  /// there.
  Vector3 _at = Vector3.zero();

  /// The mechanisms whose voices are running, so this can say where each one is
  /// on every step. Held here rather than by the caller for the same reason
  /// everything else is: a caller keeping its own set is a second answer to
  /// which sounds are playing.
  final Set<Mechanism> _running = <Mechanism>{};

  /// Three numbers as a place, or null.
  static Vector3? _place(Object? value) =>
      value is List && value.length == 3 && value.every((Object? e) => e is num)
      ? Vector3(
          (value[0]! as num).toDouble(),
          (value[1]! as num).toDouble(),
          (value[2]! as num).toDouble(),
        )
      : null;

  /// The cue sheet heard from the engine's bus and played through [scene]:
  /// what the game installs.
  ///
  /// **The events' half only.** The footsteps and the machinery are not
  /// events — a distance walked, a mover's voice held while it travels — and
  /// are heard in the step by [listenStep]. The sheet's rows are played on
  /// the frame channel, after the frame's steps, in the same frame.
  SoundtrackPlugin plugin({required AudioScene Function() scene}) =>
      SoundtrackPlugin(_cues, scene: scene);

  /// Everything a step sounds like: what the sheet makes of [events], then
  /// [listenStep]'s. The two halves the game hears apart, together, for a
  /// test that steps the simulation by hand.
  Sounding listen(GameSimulation sim, Player player, List<GameEvent> events) {
    _at = player.body.position;
    final once = <Heard>[];
    _cues.hear(events, once);
    final step = listenStep(sim, player);
    return Sounding(<Heard>[...once, ...step.once], step.loops);
  }

  /// What a step sounds like that is not an event: the machinery and the
  /// player's footsteps. Called once per simulation step, in order.
  Sounding listenStep(GameSimulation sim, Player player) {
    final once = <Heard>[];
    final loops = <Sustained>[];
    final at = player.body.position;
    _at = at;

    final mechanisms = sim.mechanisms;
    if (mechanisms != null) _machinery(mechanisms, at, once, loops);

    if (_feet.walked(at, grounded: player.body.isGrounded)) {
      once.add(Heard(Sounds.step, at));
    }
    return Sounding(once, loops);
  }

  /// What a weapon sounds like.
  ///
  /// **Public because it is the claim worth testing on its own.** The
  /// application asked `ammo == shells ? shotgun : pistol`, which is four
  /// weapons and two sounds — and there is no run of the game that makes that
  /// obvious, because you have to fire all four and remember.
  /// **What an ammunition this game has never heard of sounds like.**
  /// [AmmoType] is open, so a game built on this template can add one — and
  /// when it does, this table has no row for it. The answer here is the
  /// pistol: a weapon that fires and makes no sound reads as a broken weapon,
  /// and a wrong shot is better than a silent one in the one place where
  /// silence is indistinguishable from a bug. A game that adds ammunition adds
  /// a row, and this line is what it fails softly through until it does.
  SoundDef forWeapon(WeaponDef weapon) => switch (weapon.ammo) {
    AmmoType.shells => Sounds.shotgun,
    AmmoType.rockets => Sounds.rocket,
    AmmoType.none => Sounds.punch,
    _ => Sounds.pistol,
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

  /// For a level change or a restart: a fresh level makes its own noises.
  void reset() {
    _feet.reset();
    _running.clear();
  }
}
