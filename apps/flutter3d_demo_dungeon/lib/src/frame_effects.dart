import 'dart:math' as math;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

import 'effects.dart';
import 'reactions.dart';
import 'soundtrack.dart';

/// What one step's decisions turn into: particles, sounds, and the flashes
/// and message the HUD reads.
///
/// **The other half of the split `Reactions` and `Soundtrack` already make.**
/// Those two decide what a step is worth showing and hearing, as pure
/// functions of the simulation; this is the "performs" half, which needs a
/// particle system and a mixer to do anything. Splitting it out of `main.dart`
/// on its own — rather than leaving it beside `_step` — is safe for the same
/// reason `Reactions` and `Soundtrack` were: nothing here reads the sixty-times-
/// a-second state `_step` orchestrates (the simulation, the weapon view, the
/// camera), only the four things a reaction or a sound can change.
final class FrameEffects {
  /// Fades after the player's shot connects. Read by the HUD's crosshair.
  double hitFlash = 0.0;

  /// Fades after the player is hurt. Red rather than the crosshair's white,
  /// because taking damage and dealing it must never look alike.
  double painFlash = 0.0;

  /// The last thing the level said, and how long it has left on screen.
  String message = '';
  double messageFor = 0.0;

  /// Held while a mover is travelling, stopped when it arrives. A one-shot
  /// would be a stone slab that grinds for exactly as long as the sample.
  final Map<Object, SoundEmitter> moverVoices = <Object, SoundEmitter>{};

  // Scratch, reused every step. Allocating this per frame is the easiest way
  // to hand the collector work it does not need.
  final Vector3 _flameAt = Vector3.zero();

  /// What [Effects.flame] settles at with a torch burning steadily.
  ///
  /// Measured from the running game rather than derived — 0.24 to 0.30 with
  /// forty-odd particles alive — because the number depends on the effect's
  /// sizes, alphas and lifetimes in a way that is not worth deriving and would
  /// be wrong the moment any of them changed. The spread around it is the
  /// flicker, and it is the fire's own rather than a sine's.
  static const double _flamePower = 0.34;

  /// Fades the flashes and the message. Called once per simulated step.
  void fade(double dt) {
    if (hitFlash > 0.0) hitFlash = math.max(0.0, hitFlash - dt * 4.0);
    if (painFlash > 0.0) painFlash = math.max(0.0, painFlash - dt * 1.6);
    if (messageFor > 0.0) messageFor = math.max(0.0, messageFor - dt);
  }

  void say(String? said) {
    if (said == null) return;
    message = said;
    messageFor = 3.0;
  }

  /// Scaled rather than skipped, so the day a platform reports the two apart a
  /// flash can be turned down without turning the camera down with it. A
  /// full-screen flash on every hit is a photosensitivity question, which is
  /// not the same harm as a camera that moves by itself.
  void hurt(double screenFlash) => painFlash = screenFlash;

  /// Performs what `Reactions` decided. Nothing here chooses anything.
  void show(Reaction reaction, ParticleSystem particles, double screenFlash) {
    for (final shown in reaction.bursts) {
      particles.burst(shown.effect, shown.at, direction: shown.direction);
    }
    for (final lingering in reaction.lingering) {
      particles.emitTimed(
        lingering.key,
        lingering.effect,
        lingering.at,
        perSecond: lingering.perSecond,
        seconds: lingering.seconds,
      );
    }
    // Scaled by the player's own setting rather than decided in `Reactions`: a
    // full-screen flash on every hit is a photosensitivity question, and how
    // much of one is the player's answer.
    if (reaction.flash) hitFlash = screenFlash;
  }

  /// Every torch, every step. The rate is per second and the system keeps each
  /// source's fractional remainder, so the fire looks the same on a 60 Hz
  /// display and a 120 Hz one.
  void burnTorches(FixtureVisuals? fixtures, ParticleSystem particles) {
    if (fixtures == null) return;
    for (final entry in fixtures.flames.entries) {
      final fixture = entry.key;
      final fire = entry.value;
      if (!fixture.enabled) continue;
      // A steady rate, not one modulated by brightness. The flicker is
      // supposed to come out of the fire, and feeding brightness back into the
      // emission rate would make it come out of itself.
      particles.emit(
        fire,
        Effects.flame,
        fire.originInto(_flameAt),
        perSecond: 150.0,
      );

      // And the light is what the fire measures, not a sine running alongside
      // it. Divided by the power a healthy flame settles at, so the fixture
      // sees a fraction and the level's own intensity stays the thing that
      // decides how bright a torch is.
      fixture.measure(
        fire.glow.power / _flamePower,
        // Only once the glow has seen a particle. Before that its centre is
        // the world origin, and a torch whose light spends its first frames
        // inside a wall is worse than one that never moved at all.
        at: fire.glow.located ? fire.glow.centre : null,
      );
    }
  }

  /// Plays what the soundtrack decided, and keeps the running voices in place.
  ///
  /// The lifetimes are the only thing left here, and they are effects rather
  /// than decisions: a grinding door is one voice that has to be started,
  /// moved and stopped by the same key, and which key that is was decided in
  /// `Soundtrack`.
  void perform(Sounding sounding, AudioScene audio) {
    for (final heard in sounding.once) {
      audio.play(heard.sound, heard.at);
    }
    for (final loop in sounding.loops) {
      switch (loop.what) {
        case Voice.begin:
          moverVoices[loop.key] = audio.play(loop.sound!, loop.at!);
        case Voice.follow:
          moverVoices[loop.key]?.position.setFrom(loop.at!);
        case Voice.end:
          moverVoices.remove(loop.key)?.stop();
      }
    }
  }
}
