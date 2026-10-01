/// A live voice, as the backend sees it.
///
/// Opaque on purpose: the mixer holds it and hands it back, and has no
/// business knowing whether it is a SoLoud handle or an index into a list.
typedef VoiceId = Object;

/// What actually makes noise.
///
/// An interface because the mixing is worth testing and an audio device is not
/// something a test can have — and because the backend is the part most likely
/// to be replaced, having already been chosen twice.
abstract interface class AudioBackend {
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
}

/// A backend that makes no sound and records everything.
///
/// Not only for tests: a build with no audio device, a headless capture, or a
/// player who has turned sound off should all take this path rather than a
/// branch at every call site.
final class SilentBackend implements AudioBackend {
  final List<String> preloaded = <String>[];
  final List<SilentVoice> started = <SilentVoice>[];

  /// Voices still running, in start order.
  List<SilentVoice> get live =>
      started.where((SilentVoice v) => v.alive).toList(growable: false);

  int _next = 0;

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
    final voice = SilentVoice(_next++, asset, gain, pan, rate, loop)
      ..muffle = muffle;
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
  void stop(VoiceId voice) => (voice as SilentVoice).alive = false;

  @override
  bool isAlive(VoiceId voice) => (voice as SilentVoice).alive;

  /// Ends a one-shot, the way a real backend would when the file runs out.
  void finish(VoiceId voice) => (voice as SilentVoice).alive = false;
}

/// One recorded voice. Public because a test reads it, and a type a test has
/// to reach for is part of the interface whether or not it looks like one.
final class SilentVoice {
  SilentVoice(this.id, this.asset, this.gain, this.pan, this.rate, this.loop);

  final int id;
  final String asset;
  double gain;
  double pan;

  /// What speed it is playing at. Set at the start, and moved by `update` for
  /// a loop whose speed is the point — see there.
  double rate;
  final bool loop;
  bool alive = true;
  int updates = 0;

  /// The last muffle handed over, so a test can see a wall reach the voice.
  double muffle = 0.0;

  @override
  String toString() => 'voice($asset, gain: $gain, pan: $pan, rate: $rate)';
}
