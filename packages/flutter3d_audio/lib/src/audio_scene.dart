import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'backend.dart';
import 'listener.dart';
import 'mixer.dart';
import 'sound.dart';

/// One sound, somewhere, possibly moving.
///
/// Held by whatever started it, so a monster can carry its own growl and move
/// it without the mixer needing to know what a monster is.
final class SoundEmitter {
  SoundEmitter({required this.sound, Vector3? at})
      : position = at?.clone() ?? Vector3.zero();

  final SoundDef sound;
  final Vector3 position;

  /// Scales the sound's own gain. For a growl that gets louder as a monster
  /// winds up, without a second SoundDef for each step of it.
  double gain = 1.0;

  /// Scales the sound's own speed, and may be moved while it plays.
  ///
  /// What an engine note is: one recording of an engine, played faster as the
  /// revs rise. Separate from [SoundDef.rate] because that one is the file's
  /// resting speed and its per-play variation, decided once, while this is the
  /// game's hand on it every step.
  double rate = 1.0;

  /// What the last mix decided, for anything that wants to know whether it is
  /// being heard — a debug overlay, or a monster deciding not to bother.
  double audibleGain = 0.0;
  double pan = 0.0;
  bool get isAudible => audibleGain > 0.0;

  bool _stopped = false;
  bool get isStopped => _stopped;

  /// The speed this emitter was dealt, including the sound's own variance.
  ///
  /// Drawn once, when the emitter is made, rather than each time a voice is
  /// started: a loop that lost its voice to something louder and got it back
  /// would otherwise come back at a different pitch, which on an engine is a
  /// gear change nobody asked for.
  double _dealtRate = 1.0;

  /// Ends it. A looping emitter runs until this is called; a one-shot also
  /// ends by itself when the backend says its voice has finished.
  void stop() => _stopped = true;

  VoiceId? _voice;
}

/// Decides what is heard, and how loudly.
///
/// The reason this exists rather than handing positions to the audio engine:
/// SoLoud's own 3D needs `update3dAudio()` to apply a moved source or a turned
/// listener, and flutter_soloud exposes neither that call nor anything that
/// makes it — so a source set once at `play3d` never moves again. In a game
/// where the listener turns constantly that is not a limitation, it is the
/// whole feature missing. So the geometry is computed here and the backend is
/// asked only for a flat voice with a volume and a pan, which every backend
/// can do and which applies immediately.
final class AudioScene {
  AudioScene({
    required this.backend,
    this.maxVoices = 24,
    this.occlusion,
    Mixer? mixer,
    math.Random? random,
  })  : mixer = mixer ?? Mixer(),
        _random = random ?? math.Random(1),
        assert(maxVoices > 0);

  /// Where the play-rate variance is drawn from.
  ///
  /// Injected so a game can hand over its own seeded generator: a playthrough
  /// test that replays a recorded run must get the same sequence of sounds, and
  /// an unseeded `Random()` in here would make every snapshot test that happens
  /// to play a sound irreproducible.
  final math.Random _random;

  /// The speed one play of [sound] runs at.
  double _rateFor(SoundDef sound) {
    if (sound.rateVariance <= 0.0) return sound.rate;
    // Two-sided: `1 + r * variance` would raise the average pitch by half the
    // variance, which is the sign mistake somebody actually writes.
    return sound.rate * (1.0 + (_random.nextDouble() * 2.0 - 1.0) * sound.rateVariance);
  }

  final AudioBackend backend;

  /// What each bus is turned to. Read every frame, so moving a slider is heard
  /// on the next one without restarting anything.
  final Mixer mixer;

  /// How many may sound at once.
  ///
  /// Not a performance number so much as a mixing one: past a couple of dozen
  /// voices a scene stops having a foreground, and the platform's own limit is
  /// somewhere nearby anyway.
  final int maxVoices;

  /// What the world does to a sound between there and here, from 0 (silenced)
  /// to 1 (clear).
  ///
  /// A callback rather than a wall test of its own, because the walls belong
  /// to the physics and this package must not learn about them. The game hands
  /// in a raycast.
  final double Function(Vector3 from, Vector3 to)? occlusion;

  final List<SoundEmitter> _emitters = <SoundEmitter>[];

  /// Everything currently held, audible or not.
  List<SoundEmitter> get emitters => List<SoundEmitter>.unmodifiable(_emitters);

  int get voiceCount => _emitters.where((SoundEmitter e) => e._voice != null).length;

  Future<void> preload(Iterable<SoundDef> bank) async {
    final seen = <String>{};
    for (final sound in bank) {
      if (seen.add(sound.asset)) await backend.preload(sound.asset);
    }
  }

  /// Starts [sound] at [at]. The emitter is returned so a caller that owns a
  /// moving source can keep it.
  SoundEmitter play(SoundDef sound, Vector3 at) {
    final emitter = SoundEmitter(sound: sound, at: at)
      // Dealt here, once, rather than each time a voice starts — see
      // [SoundEmitter._dealtRate].
      .._dealtRate = _rateFor(sound);
    _emitters.add(emitter);
    return emitter;
  }

  /// Stops everything, for a level change or a pause.
  void stopAll() {
    for (final emitter in _emitters) {
      final voice = emitter._voice;
      if (voice != null) backend.stop(voice);
      emitter._voice = null;
      emitter._stopped = true;
    }
    _emitters.clear();
  }

  /// Recomputes the mix. Called once a frame, after everything has moved.
  void update(AudioListener listener) {
    _audible.clear();

    for (var i = _emitters.length - 1; i >= 0; i--) {
      final emitter = _emitters[i];

      // A one-shot whose voice has run out is finished, and so is anything
      // stopped by hand.
      final voice = emitter._voice;
      if (emitter._stopped ||
          (voice != null && !emitter.sound.loop && !backend.isAlive(voice))) {
        if (voice != null) backend.stop(voice);
        emitter._voice = null;
        emitter.audibleGain = 0.0;
        _emitters.removeAt(i);
        continue;
      }

      _measure(emitter, listener);
      if (emitter.audibleGain > 0.0) _audible.add(emitter);
    }

    _chooseVoices();
  }

  /// Fills in [SoundEmitter.audibleGain] and [SoundEmitter.pan].
  void _measure(SoundEmitter emitter, AudioListener listener) {
    _toListener
      ..setFrom(emitter.position)
      ..sub(listener.position);
    final distance = _toListener.length;

    final sound = emitter.sound;
    if (!sound.attenuation.carriesTo(distance)) {
      emitter.audibleGain = 0.0;
      emitter.pan = 0.0;
      return;
    }

    var gain = sound.gain * emitter.gain * sound.attenuation.gainAt(distance);

    final occlude = occlusion;
    if (gain > 0.0 && occlude != null && distance > 1e-6) {
      gain *= occlude(emitter.position, listener.position).clamp(0.0, 1.0);
    }

    emitter.audibleGain = gain;

    // Pan is the left-right component of the direction, and nothing else. A
    // sound on top of the listener has no direction at all, and panning it
    // by whatever the normalisation of a zero vector produces is how a
    // footstep ends up hard left.
    if (distance < 1e-6) {
      emitter.pan = 0.0;
      return;
    }
    _toListener.scale(1.0 / distance);
    emitter.pan = _toListener.dot(listener.right).clamp(-1.0, 1.0);
  }

  /// Starts, updates and stops voices so that the loudest [maxVoices] sound.
  void _chooseVoices() {
    // Priority first, loudness second. A door closing outranks the ninth
    // footstep even when the footstep is nearer, which distance alone would
    // get backwards.
    _audible.sort((SoundEmitter a, SoundEmitter b) {
      final byPriority = b.sound.priority.compareTo(a.sound.priority);
      if (byPriority != 0) return byPriority;
      return b.audibleGain.compareTo(a.audibleGain);
    });

    _instances.clear();
    final keep = <SoundEmitter>{};
    for (final emitter in _audible) {
      if (keep.length >= maxVoices) break;
      final name = emitter.sound.name;
      final playing = _instances[name] ?? 0;
      // Ten identical grunts on one frame are not ten times as loud; they are
      // a click.
      if (playing >= emitter.sound.maxInstances) continue;
      _instances[name] = playing + 1;
      keep.add(emitter);
    }

    for (final emitter in _emitters) {
      final voice = emitter._voice;
      if (keep.contains(emitter)) {
        // The bus is applied here and not in `_measure`, so that a player
        // turning the music down cannot cost the music its voice. See [Mixer].
        final gain = emitter.audibleGain * mixer.gainFor(emitter.sound.bus);
        if (voice == null) {
          emitter._voice = backend.start(
            emitter.sound.asset,
            gain: gain,
            pan: emitter.pan,
            rate: emitter._dealtRate * emitter.rate,
            loop: emitter.sound.loop,
          );
        } else {
          backend.update(
            voice,
            gain: gain,
            pan: emitter.pan,
            rate: emitter._dealtRate * emitter.rate,
          );
        }
        continue;
      }

      // Out of the mix. A loop is stopped and may start again later; a
      // one-shot that never got a voice has simply missed its moment, which is
      // the right answer — restarting it half a second late is worse than
      // never playing it.
      if (voice != null) {
        backend.stop(voice);
        emitter._voice = null;
      }
      emitter.audibleGain = 0.0;
    }
  }

  final List<SoundEmitter> _audible = <SoundEmitter>[];
  final Map<String, int> _instances = <String, int>{};
  final Vector3 _toListener = Vector3.zero();
}

/// Turns a distance into the decibel figure a mixing desk would show.
///
/// Only for reporting — the mixer works in linear gain throughout, because
/// that is what a backend wants and converting twice is how a volume slider
/// ends up logarithmic in one build and linear in the next.
double gainToDecibels(double gain) =>
    gain <= 0.0 ? double.negativeInfinity : 20.0 * (math.log(gain) / math.ln10);
