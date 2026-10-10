import 'bus_effect.dart';
import 'mixer.dart';
import 'spatial.dart';

/// A live voice, as the backend sees it.
///
/// Opaque on purpose: the mixer holds it and hands it back, and has no
/// business knowing whether it is a SoLoud handle or an index into a list.
typedef VoiceId = Object;

/// What actually makes noise.
///
/// A base class because the mixing is worth testing and an audio device is not
/// something a test can have — and because the backend is the part most likely
/// to be replaced, having already been chosen twice.
///
/// **Extended outside this package, and stays extendable through 1.x.** A
/// backend `extends AudioBackend` and implements the five members a voice
/// needs; the device's lifecycle — [open], [pause], [resume], [dispose] — has
/// bodies that do nothing, which is right for a backend with no device, and a
/// member added in a minor release arrives with a body too, so a backend
/// written against 1.0 keeps compiling. A capability that changes what the
/// scene hands a backend arrives beside it instead, as an interface the
/// backend opts into: [MixingBackend], [DirectionalBackend].
abstract base class AudioBackend {
  /// A backend; a subclass starts nothing here, [open] does.
  AudioBackend();

  /// Readies the device, so the first [start] makes a sound. Safe to call
  /// twice. Nothing to ready by default.
  Future<void> open() async {}

  /// Reads an asset so that [start] does not have to wait.
  Future<void> preload(String asset);

  /// Begins a voice, or null when the backend refused.
  ///
  /// [pan] runs from -1 (hard left) through 0 to 1 (hard right). [rate] is a
  /// multiple of the file's own speed, and it is a required parameter rather
  /// than an optional one on purpose: a one-shot that begins at rate one and is
  /// corrected a frame later is audible as a chirp, so there is no
  /// `setRate(voice, rate)` to forget to call.
  ///
  /// [muffle] is how much of the sound's top end the world takes away, from
  /// 0 (clear) to 1 (heard through a wall): a backend that can filter turns
  /// it into a low-pass cutoff, and one that cannot ignores it. Optional so
  /// a backend written before there was a wall between anything keeps
  /// working; `SoundOcclusion` in the bridge is what supplies it.
  VoiceId? start(
    String asset, {
    required double gain,
    required double pan,
    required double rate,
    required bool loop,
    double muffle = 0.0,
  });

  /// Changes a voice that is already playing.
  ///
  /// [rate] is required here for the same reason it is required on [start], and
  /// the reason there is a rate here at all is a looping sound whose speed is
  /// the point: an engine note is one file played faster and slower, and a
  /// backend that could only set it once would leave a car droning on one tone
  /// through every gear. The argument that killed `setRate` for one-shots — a
  /// sound that begins at the wrong speed and is corrected a frame later is
  /// audible as a chirp — does not apply to a loop already running at the speed
  /// the caller last asked for.
  void update(
    VoiceId voice, {
    required double gain,
    required double pan,
    required double rate,
    double muffle = 0.0,
  });

  void stop(VoiceId voice);

  /// False once a one-shot has run out, so the mixer can forget it.
  bool isAlive(VoiceId voice);

  /// Holds every voice where it is: the application went to the background,
  /// a route covered the game, the player paused. Nothing by default.
  ///
  /// **A voice [start]ed while paused is held too**, from its first sample,
  /// and goes on with the others at [resume]: a sound the game starts under
  /// a pause menu must not play over it. A backend that pauses keeps this.
  void pause() {}

  /// Lets the voices [pause] held go on from where they were, the ones
  /// started during the pause from their beginning. Nothing by default.
  void resume() {}

  /// Frees what the backend holds and closes the device; the backend is not
  /// used after this. Nothing to free by default.
  Future<void> dispose() async {}
}

/// A backend that mixes the bus tree itself: what [AudioBackend] grows into
/// for buses, beside it rather than inside it.
///
/// **Opt-in, and an interface on its own**: a backend `extends AudioBackend`
/// and `implements MixingBackend`, and the scene asks `backend is
/// MixingBackend`. It is not an [AudioBackend] itself, so it does not grow
/// when the base class does. A backend that implements this as well is told which bus each
/// voice is on and handed each bus's own gain and effects every mix, and is
/// then handed a voice's gain *without* its buses' and its muffle without
/// theirs — the buses are its to apply, reverb included. One that does not
/// gets what it always got: a flat voice with the bus folded into its gain
/// and a bus's low-pass folded into its muffle.
abstract interface class MixingBackend {
  /// Puts [voice], just started, on [bus].
  void routeVoice(VoiceId voice, AudioBus bus);

  /// What [bus] does this mix: routes into [parent] (null for the master),
  /// at [gain] linear — its volume and level, not its parents' — through
  /// [effects] in order.
  void mixBus(
    AudioBus bus, {
    required AudioBus? parent,
    required double gain,
    required List<BusEffect> effects,
  });
}

/// A backend that places a voice in three dimensions itself: where a
/// binaural (HRTF) or multichannel backend comes in.
///
/// **Opt-in**, and an interface on its own, as [MixingBackend] is. After each start and update, a voice
/// is handed the whole [SpatialResult] its renderer decided — azimuth,
/// elevation and distance in the listener's frame — and the backend may
/// render from those instead of from the stereo pan, which it still gets.
abstract interface class DirectionalBackend {
  /// Where [voice] is heard from this mix.
  void placeVoice(VoiceId voice, SpatialResult spatial);
}

/// A backend that makes no sound and records everything.
///
/// Not only for tests: a build with no audio device, a headless capture, or a
/// player who has turned sound off should all take this path rather than a
/// branch at every call site.
final class SilentBackend extends AudioBackend {
  final List<String> preloaded = <String>[];
  final List<SilentVoice> started = <SilentVoice>[];

  /// Voices still running, in start order.
  List<SilentVoice> get live =>
      started.where((SilentVoice v) => v.isAlive).toList(growable: false);

  int _next = 0;

  /// Whether [pause] holds the voices: set by [pause], cleared by [resume].
  bool get isPaused => _paused;
  bool _paused = false;

  @override
  void pause() => _setPaused(true);

  @override
  void resume() => _setPaused(false);

  void _setPaused(bool paused) {
    _paused = paused;
    for (final voice in started) {
      if (voice.isAlive) voice.isPaused = paused;
    }
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  @override
  Future<void> dispose() async => _disposed = true;

  @override
  Future<void> preload(String asset) async => preloaded.add(asset);

  @override
  VoiceId? start(
    String asset, {
    required double gain,
    required double pan,
    required double rate,
    required bool loop,
    double muffle = 0.0,
  }) {
    // Held from the start while paused, as [AudioBackend.pause] asks.
    final voice = SilentVoice(_next++, asset, gain, pan, rate, loop)
      ..muffle = muffle
      ..isPaused = _paused;
    started.add(voice);
    return voice;
  }

  @override
  void update(
    VoiceId voice, {
    required double gain,
    required double pan,
    required double rate,
    double muffle = 0.0,
  }) {
    final live = voice as SilentVoice;
    live
      ..gain = gain
      ..pan = pan
      ..rate = rate
      ..muffle = muffle;
    live.updates++;
  }

  @override
  void stop(VoiceId voice) => (voice as SilentVoice).isAlive = false;

  @override
  bool isAlive(VoiceId voice) => (voice as SilentVoice).isAlive;

  /// Ends a one-shot, the way a real backend would when the file runs out.
  void finish(VoiceId voice) => (voice as SilentVoice).isAlive = false;
}

/// One recorded voice. Public because a test reads it, and a type a test has
/// to reach for is part of the interface whether or not it looks like one.
final class SilentVoice {
  SilentVoice(this.id, this.asset, this.gain, this.pan, this.rate, this.loop);

  final int id;
  final String asset;

  /// How loud it plays, a linear gain.
  double gain;

  /// Where it sits between the ears, from −1 (left) to 1 (right); unitless.
  double pan;

  /// What speed it is playing at. Set at the start, and moved by `update` for
  /// a loop whose speed is the point — see there. A unitless multiplier on
  /// the file's own speed.
  double rate;
  final bool loop;
  bool isAlive = true;

  /// Whether the backend's pause holds it: true for a voice started while
  /// the backend was paused, until it resumes.
  bool isPaused = false;
  int updates = 0;

  /// The last muffle handed over, so a test can see a wall reach the voice.
  /// A 0..1 fraction, 0 clear.
  double muffle = 0.0;

  @override
  String toString() => 'voice($asset, gain: $gain, pan: $pan, rate: $rate)';
}
