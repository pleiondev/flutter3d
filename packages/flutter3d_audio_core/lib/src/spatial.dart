import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart' show WorldProperties;
import 'package:vector_math/vector_math.dart';

import 'audio_scene.dart';
import 'listener.dart';
import 'units.dart';

/// Scratch for [EqualPowerPanner.render], which is const and so cannot own
/// one: a mix is single-threaded and the vector never outlives a call.
final Vector3 _toSound = Vector3.zero();

/// What a [SpatialRenderer] is asked about one emitter: who hears, what is
/// heard, and what stands between them.
///
/// **One object rather than parameters, so it can grow** — a room, a
/// propagation graph, a head size — without every renderer's signature
/// changing. Made and reused by `AudioScene`; copy what you keep.
final class SpatialQuery {
  SpatialQuery({required this.listener, required this.emitter, this.occlusion});

  /// Where the ears are.
  AudioListener listener;

  /// What is making the noise, where, how fast it is moving and what it is.
  AudioEmitter emitter;

  /// What the world lets through between a point and the ears, from 0
  /// (nothing) to 1 (everything): the game's raycast, or null when there are
  /// no walls. `AudioScene.occlusion`.
  double Function(Vector3 from, Vector3 to)? occlusion;
}

/// What a [SpatialRenderer] decided about one emitter.
///
/// Everything a backend could want, in the units of the audio model, so a
/// stereo backend reads [gain] and [pan] and a binaural one reads [azimuth],
/// [elevation] and [distance] from the same result. Kept on the emitter
/// ([AudioEmitter.spatial]) between mixes.
final class SpatialResult {
  /// How loud it arrives, linear, before any bus: the sound's gain, the
  /// emitter's, the distance curve's and what the walls let through.
  double gain = 0.0;

  /// Where it sits between the ears, from −1 (left) to 1 (right). Played by
  /// an equal-power law; [EqualPowerPanner.gains] is that law.
  double pan = 0.0;

  /// How dull the world makes it, from 0 (clear) to 1 (through a wall): a
  /// 0..1 fraction.
  double muffle = 0.0;

  /// A multiple of its play rate from motion: the doppler shift, one when
  /// nothing moves or doppler is off. A unitless multiplier.
  double rate = 1.0;

  /// From the ears to it, in metres.
  double distance = 0.0;

  /// Which way it is, in radians in the listener's frame: nought ahead,
  /// positive to the right, ±π behind.
  double azimuth = 0.0;

  /// How far above the listener's horizon it is, in radians: positive up,
  /// ±π/2 straight above or below.
  double elevation = 0.0;

  @override
  String toString() =>
      'SpatialResult(gain: $gain, pan: $pan, muffle: $muffle, rate: $rate)';
}

/// Turns where a sound is into how it is heard.
///
/// **The seam the next renderers arrive behind.** Today's is
/// [EqualPowerPanner]: distance attenuation, occlusion and a stereo pan. A
/// binaural renderer (HRTF) and one that follows sound through the level
/// (propagation) are later implementations of this same class, handed to
/// `AudioScene(spatial: ...)`, with nothing else in a game changing: the
/// emitters, the listener, the buses and the snapshots stay what they are.
/// What a renderer decides that a flat stereo voice cannot carry —
/// a direction to convolve with — reaches a backend that opts into it
/// through `DirectionalBackend`.
///
/// `base`, so a member added in a later minor arrives with a default:
/// [beginMix] is one.
abstract base class SpatialRenderer {
  const SpatialRenderer();

  /// Called once a mix, before any [render], with the listener placed. A
  /// renderer that precomputes per frame — a propagation graph from the
  /// listener's room — does it here.
  void beginMix(AudioListener listener) {}

  /// Fills [out] for [query]'s emitter.
  ///
  /// [out] is the emitter's own result from the mix before; a renderer that
  /// leaves a field alone leaves what it said last time.
  void render(SpatialQuery query, SpatialResult out);
}

/// Distance attenuation, occlusion and an equal-power stereo pan: the
/// audio model's spatialisation today.
///
/// The gain is the sound's, times the emitter's, times its [Attenuation]
/// curve at the distance in metres, times what the occlusion lets through;
/// the pan is the left-right component of the direction to the sound in the
/// listener's frame, which an equal-power law ([gains]) turns into the two
/// ears.
///
/// **Doppler is wired and off.** With a [dopplerFactor] above nought, each
/// emitter's and the listener's velocity in metres per second shift its
/// [SpatialResult.rate] the way the classic formula does, against
/// [speedOfSound]; at nought, the default, the rate is exactly one and
/// nothing a game hears has changed.
final class EqualPowerPanner extends SpatialRenderer {
  const EqualPowerPanner({
    this.dopplerFactor = 0.0,
    this.speedOfSound = speedOfSoundInAir,
  }) : assert(dopplerFactor >= 0.0),
       assert(speedOfSound > 0.0);

  /// A panner whose Doppler shift is reckoned against the sound speed of
  /// [world]'s air: `WorldProperties.speedOfSound`, from its temperature
  /// (`speedOfSoundAt`) — 343 m/s in a room, 331 at freezing. What a game
  /// whose world is not a room's hands its `AudioScene`.
  EqualPowerPanner.inWorld(WorldProperties world, {double dopplerFactor = 0.0})
    : this(dopplerFactor: dopplerFactor, speedOfSound: world.speedOfSound);

  /// How much of the physical doppler shift is applied: nought is none, one
  /// is what the air does. Games usually want a fraction of it.
  final double dopplerFactor;

  /// The speed of sound, in metres per second: the air's at 20 °C
  /// ([speedOfSoundInAir]) unless the panner was made for a world
  /// ([EqualPowerPanner.inWorld]).
  final double speedOfSound;

  /// The two ears' gains for [pan], by the equal-power law: `cos` and `sin`
  /// of `(pan + 1) · π / 4`, so that left² + right² is always one and a
  /// sound crossing the field is as loud in the middle as at the sides.
  static ({double left, double right}) gains(double pan) {
    final angle = (pan.clamp(-1.0, 1.0) + 1.0) * math.pi / 4.0;
    return (left: math.cos(angle), right: math.sin(angle));
  }

  @override
  void render(SpatialQuery query, SpatialResult out) {
    final listener = query.listener;
    final emitter = query.emitter;
    final toSound = _toSound
      ..setFrom(emitter.position)
      ..sub(listener.position);
    final distance = toSound.length;
    out.distance = distance;

    final sound = emitter.sound;
    if (!sound.attenuation.carriesTo(distance)) {
      out
        ..gain = 0.0
        ..pan = 0.0
        ..rate = 1.0;
      return;
    }

    var gain = sound.gain * emitter.gain * sound.attenuation.gainAt(distance);

    final occlude = query.occlusion;
    var through = 1.0;
    if (gain > 0.0 && occlude != null && distance > 1e-6) {
      through = occlude(emitter.position, listener.position).clamp(0.0, 1.0);
      gain *= through;
    }

    out
      ..gain = gain
      // Quieter is half of what a wall does; the other half is duller, and a
      // backend that can filter is told how much. One minus the share that
      // got through, so a wall that halves the sound muffles it by half.
      ..muffle = 1.0 - through
      ..rate = dopplerFactor > 0.0
          ? _doppler(toSound, distance, listener, emitter)
          : 1.0;

    // Pan is the left-right component of the direction, and nothing else. A
    // sound on top of the listener has no direction at all, and panning it
    // by whatever the normalisation of a zero vector produces is how a
    // footstep ends up hard left.
    if (distance < 1e-6) {
      out
        ..pan = 0.0
        ..azimuth = 0.0
        ..elevation = 0.0;
      return;
    }
    toSound.scale(1.0 / distance);
    final right = toSound.dot(listener.right);
    out
      ..pan = right.clamp(-1.0, 1.0)
      ..azimuth = math.atan2(right, toSound.dot(listener.forward))
      ..elevation = math.asin(toSound.dot(listener.up).clamp(-1.0, 1.0));
  }

  /// The play-rate multiple for a source and a listener moving along the
  /// line between them: `(c + f·v_listener) / (c − f·v_source)`, each speed
  /// the component toward the other (so both approaching raise the pitch),
  /// f the [dopplerFactor], clamped below the speed of sound so a
  /// supersonic source does not divide by nothing, and the result to
  /// `[0.25, 4]`, the range a backend's rate is good for.
  double _doppler(
    Vector3 toSound,
    double distance,
    AudioListener listener,
    AudioEmitter emitter,
  ) {
    if (distance < 1e-6) return 1.0;
    final limit = speedOfSound / dopplerFactor * 0.99;
    // Positive when the listener moves toward the sound, and when the sound
    // moves away from the listener.
    final towardSound = (listener.velocity.dot(toSound) / distance).clamp(
      -limit,
      limit,
    );
    final awayFromListener = (emitter.velocity.dot(toSound) / distance).clamp(
      -limit,
      limit,
    );
    final shift =
        (speedOfSound + dopplerFactor * towardSound) /
        (speedOfSound + dopplerFactor * awayFromListener);
    return shift.clamp(0.25, 4.0);
  }
}
