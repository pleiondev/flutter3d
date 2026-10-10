import 'dart:math' as math;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show WorldPosition;
import 'package:vector_math/vector_math.dart';

import 'backend.dart';
import 'listener.dart';
import 'mixer.dart';
import 'pose.dart';
import 'sound.dart';
import 'spatial.dart';

/// One sound, somewhere, possibly moving: the emitter component of the
/// audio model.
///
/// Held by whatever started it, so a monster can carry its own growl and move
/// it without the mixer needing to know what a monster is.
///
/// ## A component of the scene
///
/// An emitter is placed either by hand — its [position] moved by whatever
/// holds it — or by a node it [follow]s, whose world matrix each mix reads
/// for its place and the way it faces, and whose motion gives its
/// [velocity]. [AudioScene.attach] makes one that follows from the start.
///
/// It plays on [bus], the sound's own unless it was started on another, so
/// the same footstep can be foley in one place and a cutscene's in another.
///
/// Units: metres, metres per second, linear gain, a rate as a multiple of
/// the recording's own speed.
final class AudioEmitter {
  AudioEmitter({required this.sound, Vector3? at, AudioBus? bus})
    : position = at?.clone() ?? Vector3.zero(),
      bus = bus ?? sound.bus;

  final SoundDef sound;

  /// Where it is: metres from the origin the listener's position is
  /// relative to (see [AudioListener]), a float32 offset. [placeAt] puts it
  /// at a place in the world.
  final Vector3 position;

  /// The way it faces, a unit vector: read from the node it follows, for a
  /// renderer that cares which way a sound points.
  final Vector3 forward = Vector3(0.0, 0.0, -1.0);

  /// How fast it is moving, in metres per second: what a doppler shift is
  /// computed from. Derived while the mix is given its seconds: from the
  /// node while it [follow]s one, and from successive [placeAt] calls
  /// otherwise. Set by hand for an emitter moved through [position] alone.
  final Vector3 velocity = Vector3.zero();

  /// The bus it plays on. May be moved while it plays; the next mix hears
  /// it on the new one.
  AudioBus bus;

  /// What the spatial renderer decided in the last mix. [audibleGain],
  /// [pan] and [muffle] are copied from it; a binaural backend reads the
  /// rest.
  final SpatialResult spatial = SpatialResult();

  PoseSource? _pose;
  bool _placed = false;
  final Vector3 _was = Vector3.zero();
  final HandMotion _hand = HandMotion();

  /// The node this emitter follows, or null when it is placed by hand.
  PoseSource? get following => _pose;

  /// Follows [pose] from the next mix on — usually `() => node.worldMatrix`
  /// — or stops following with null, leaving the emitter where it was.
  void follow(PoseSource? pose) {
    _pose = pose;
    _placed = false;
    _hand.reset();
  }

  /// Puts the emitter at [at] in the world: [position] becomes [at]'s offset
  /// from [origin], worked out in doubles. [origin] is the one the listener
  /// is placed against, the scene's origin for a game that draws one —
  /// required, as the listener's is, so the two cannot drift apart by one
  /// of them taking the world's origin as a default.
  ///
  /// The velocity comes from the placements, by the rules
  /// `AudioListener.placeAt` gives: the difference since the last mix over
  /// its seconds, nought on the first placement and on a [teleport], and
  /// [velocity] when the game gives one.
  void placeAt(
    WorldPosition at, {
    required WorldPosition origin,
    Vector3? velocity,
    bool teleport = false,
  }) {
    _hand.placed(this.velocity, velocity: velocity, teleport: teleport);
    final offset = at.relativeTo(origin);
    position.setValues(offset.x, offset.y, offset.z);
  }

  /// Reads the node [follow] was given, if any, and the velocity from how
  /// far it moved in [seconds] — or, placed by hand, how far the [placeAt]
  /// calls moved it. Called by [AudioScene.update] once a mix.
  void syncPose(double seconds) {
    final pose = _pose;
    if (pose == null) {
      _hand.settle(position, velocity, seconds);
      return;
    }
    _was.setFrom(position);
    final world = pose();
    poseTranslation(world, position);
    poseForward(world, forward);
    if (_placed && seconds > 0.0 && seconds.isFinite) {
      velocity
        ..setFrom(position)
        ..sub(_was)
        ..scale(1.0 / seconds);
    }
    _placed = true;
  }

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
  /// A linear gain.
  double audibleGain = 0.0;

  /// Where the last mix placed it between the ears, from −1 (left) to 1
  /// (right); unitless.
  double pan = 0.0;

  /// How much the walls dull this sound, from 0 (clear) to 1. Set by
  /// [AudioScene.update] from the occlusion callback and handed to the
  /// backend beside the gain.
  double muffle = 0.0;
  bool get isAudible => audibleGain > 0.0;

  bool _stopped = false;

  /// Whether this emitter has been stopped and will not be heard again.
  ///
  /// The scene drops stopped emitters on its own update, so nothing here has to
  /// check. It is for a game holding a handle to one — a machine it turned off,
  /// a voice line it interrupted — that wants to know whether the thing it is
  /// holding is still alive before asking it for anything else.
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
///
/// ## A mix
///
/// [update], once a frame, after everything has moved:
///
/// 1. the [mixer] moves on by the frame's seconds — snapshots blend, ducks
///    attack and release, against what was heard in the mix before;
/// 2. the listener and every emitter that follows a node read it;
/// 3. the [spatial] renderer decides, for each emitter, how loud it
///    arrives, where it sits and how dull it is;
/// 4. the loudest [maxVoices] by priority get voices, each at its bus's
///    gain and through its bus's low-pass.
///
/// `AudioPlugin` runs it in the engine loop's `audio` phase.
final class AudioScene {
  AudioScene({
    required this.backend,
    this.maxVoices = 24,
    this.occlusion,
    Mixer? mixer,
    math.Random? random,
    this.spatial = const EqualPowerPanner(),
  }) : mixer = mixer ?? Mixer(),
       _random = random ?? math.Random(1),
       assert(maxVoices > 0);

  /// Turns where a sound is into how it is heard: [EqualPowerPanner] unless
  /// a game hands in another — a binaural one, one that follows sound
  /// through the level.
  final SpatialRenderer spatial;

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
    return sound.rate *
        (1.0 + (_random.nextDouble() * 2.0 - 1.0) * sound.rateVariance);
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

  final List<AudioEmitter> _emitters = <AudioEmitter>[];

  /// Everything currently held, audible or not.
  List<AudioEmitter> get emitters => List<AudioEmitter>.unmodifiable(_emitters);

  int get voiceCount =>
      _emitters.where((AudioEmitter e) => e._voice != null).length;

  Future<void> preload(Iterable<SoundDef> bank) async {
    final seen = <String>{};
    for (final sound in bank) {
      if (seen.add(sound.asset)) await backend.preload(sound.asset);
    }
  }

  /// Starts [sound] at [at], in metres. The emitter is returned so a caller
  /// that owns a moving source can keep it.
  ///
  /// [bus] plays it on a bus other than the sound's own. [follow] puts it on
  /// a node from the next mix on, as [attach] does.
  AudioEmitter play(
    SoundDef sound,
    Vector3 at, {
    AudioBus? bus,
    PoseSource? follow,
  }) {
    final emitter = AudioEmitter(sound: sound, at: at, bus: bus)
      // Dealt here, once, rather than each time a voice starts — see
      // [AudioEmitter._dealtRate].
      .._dealtRate = _rateFor(sound);
    if (follow != null) emitter.follow(follow);
    _emitters.add(emitter);
    return emitter;
  }

  /// Starts [sound] on the node [pose] reads — a torch, an engine, a
  /// monster's mouth — placed there at once and following it every mix.
  AudioEmitter attach(SoundDef sound, PoseSource pose, {AudioBus? bus}) {
    final at = Vector3.zero();
    poseTranslation(pose(), at);
    return play(sound, at, bus: bus, follow: pose)..syncPose(0.0);
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
  ///
  /// [dt] is the seconds since the last mix: what snapshots blend and ducks
  /// move by, and what a followed node's velocity is measured over. Left at
  /// nought, nothing blends and no velocity is measured — the mix as it
  /// was before there were either.
  void update(AudioListener listener, {double dt = 0.0}) {
    mixer.advance(dt, activity: _activity);
    listener.syncPose(dt);
    spatial.beginMix(listener);
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

      emitter.syncPose(dt);
      _measure(emitter, listener);
      if (emitter.audibleGain > 0.0) _audible.add(emitter);
    }

    _chooseVoices();

    // **A one-shot holding no voice is finished**, which is what the comment
    // in [_chooseVoices] has always said and what nothing acted on. The
    // removal at the top of the loop above can only fire for an emitter that
    // *has* a voice — so a sound played out of earshot never got one, never
    // lost one, and stayed here for the life of the scene: measured every
    // frame, and raycast for occlusion every frame. It was invisible in
    // [voiceCount] too, which counts only emitters with voices, so the number
    // a game puts on its debug overlay said nothing was wrong.
    //
    // The crypt's near sounds carry 26 metres in a level larger than that, so
    // every grunt, every door and every hit across it accumulated permanently.
    //
    // Loops are excluded on purpose: one out of range now may come back into
    // it, which is the difference between a sound and a source of sound.
    _emitters.removeWhere(
      (AudioEmitter emitter) => !emitter.sound.loop && emitter._voice == null,
    );
  }

  /// Fills in [AudioEmitter.spatial] through the renderer, and the
  /// emitter's [AudioEmitter.audibleGain], [AudioEmitter.pan] and
  /// [AudioEmitter.muffle] from it.
  void _measure(AudioEmitter emitter, AudioListener listener) {
    final query =
        (_query ??= SpatialQuery(listener: listener, emitter: emitter))
          ..listener = listener
          ..emitter = emitter
          ..occlusion = occlusion;
    final out = emitter.spatial;
    spatial.render(query, out);
    emitter
      ..audibleGain = out.gain
      ..pan = out.pan
      ..muffle = out.muffle;
  }

  /// Starts, updates and stops voices so that the loudest [maxVoices] sound.
  void _chooseVoices() {
    // Priority first, loudness second. A door closing outranks the ninth
    // footstep even when the footstep is nearer, which distance alone would
    // get backwards.
    _audible.sort((AudioEmitter a, AudioEmitter b) {
      final byPriority = b.sound.priority.compareTo(a.sound.priority);
      if (byPriority != 0) return byPriority;
      return b.audibleGain.compareTo(a.audibleGain);
    });

    _instances.clear();
    _activity.clear();
    final mixing = backend is MixingBackend ? backend as MixingBackend : null;
    final directional = backend is DirectionalBackend
        ? backend as DirectionalBackend
        : null;
    final keep = <AudioEmitter>{};
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
        final bus = emitter.bus;
        // What a ducking rule listens to: the loudest voice on each bus, as
        // it arrives, before any slider.
        final loudest = _activity[bus];
        if (loudest == null || emitter.audibleGain > loudest) {
          _activity[bus] = emitter.audibleGain;
        }
        // The bus is applied here and not in `_measure`, so that a player
        // turning the music down cannot cost the music its voice. See
        // [Mixer]. A backend that mixes buses itself applies them there.
        final gain = mixing != null
            ? emitter.audibleGain
            : emitter.audibleGain * mixer.gainFor(bus);
        // A bus's low-pass is the same dullness a wall is; the duller wins.
        // `max(muffle, 0)` is the muffle unchanged when no bus has one.
        final muffle = mixing != null
            ? emitter.muffle
            : math.max(emitter.muffle, mixer.muffleFor(bus));
        // Doppler's share is exactly one unless a renderer was asked for it.
        final rate = emitter._dealtRate * emitter.rate * emitter.spatial.rate;
        final VoiceId live;
        if (voice == null) {
          final started = backend.start(
            emitter.sound.asset,
            gain: gain,
            pan: emitter.pan,
            rate: rate,
            loop: emitter.sound.loop,
            muffle: muffle,
          );
          emitter._voice = started;
          if (started == null) continue;
          mixing?.routeVoice(started, bus);
          live = started;
        } else {
          backend.update(
            voice,
            gain: gain,
            pan: emitter.pan,
            rate: rate,
            muffle: muffle,
          );
          live = voice;
        }
        directional?.placeVoice(live, emitter.spatial);
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

    if (mixing != null) _mixBuses(mixing);
  }

  /// Hands a [MixingBackend] every bus it may have a voice on, and the buses
  /// those route into, with each one's own gain and effects.
  void _mixBuses(MixingBackend mixing) {
    final buses = <AudioBus>{};
    for (final emitter in _emitters) {
      for (AudioBus? at = emitter.bus; at != null; at = mixer.parentOf(at)) {
        if (!buses.add(at)) break;
      }
    }
    for (final bus in buses) {
      mixing.mixBus(
        bus,
        parent: mixer.parentOf(bus),
        gain: mixer.ownGainOf(bus),
        effects: mixer.effectsOf(bus),
      );
    }
  }

  final List<AudioEmitter> _audible = <AudioEmitter>[];
  final Map<String, int> _instances = <String, int>{};

  /// The loudest voice on each bus in the last mix, linear: what the
  /// mixer's ducking rules listen to on the next.
  final Map<AudioBus, double> _activity = <AudioBus, double>{};
  SpatialQuery? _query;
}

/// Turns a distance into the decibel figure a mixing desk would show.
///
/// Only for reporting — the mixer works in linear gain throughout, because
/// that is what a backend wants and converting twice is how a volume slider
/// ends up logarithmic in one build and linear in the next.
double gainToDecibels(double gain) =>
    gain <= 0.0 ? double.negativeInfinity : 20.0 * (math.log(gain) / math.ln10);
