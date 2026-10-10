import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Issue, IssueSink;
import 'package:flutter_soloud/flutter_soloud.dart';

import 'cutoff.dart';

/// Plays through SoLoud, flat.
///
/// Flat on purpose. SoLoud has a 3D layer, and it is not usable from here:
/// applying a moved source or a turned listener requires `update3dAudio()`,
/// which flutter_soloud exposes neither directly nor by way of any call that
/// makes it — its `set3dSourcePosition` passes straight through to a SoLoud
/// method that only marks the source dirty. A source set once at `play3d`
/// therefore never moves again, which in a first-person game means the whole
/// feature. So [AudioScene] does the geometry and this asks for a voice with a
/// volume and a pan, both of which take effect immediately.
///
/// If a later flutter_soloud exposes the call, the right change is a second
/// backend rather than an edit here — the base class exists for exactly that.
///
/// What it could not do it says through [onIssue], in the engine's one
/// [Issue] type, which `flutter3d_app` reports through as well.
final class SoLoudBackend extends AudioBackend {
  SoLoudBackend({SoLoud? soloud, IssueSink? onIssue})
    : _soloud = soloud ?? SoLoud.instance,
      onIssue = onIssue ?? _printIssue;

  final SoLoud _soloud;

  /// Where this says what it could not play.
  ///
  /// **It said it to `debugPrint` and nowhere else**, which in a release build
  /// is nowhere at all: a sound that will not decode is silent for the rest of
  /// the session and the only record of it was a console line stripped out of
  /// the build a player runs. Every storage path in `flutter3d_app` threads one
  /// of these; audio was the layer that did not.
  final IssueSink onIssue;

  static void _printIssue(Issue issue) => debugPrint('flutter3d_audio: $issue');

  final Map<String, AudioSource> _sources = <String, AudioSource>{};

  /// Assets [preload] was asked for and could not decode.
  ///
  /// Kept so a caller can say which sounds a level is missing rather than
  /// discovering it by silence. Empty on a healthy load.
  List<String> get failedAssets => List<String>.unmodifiable(_failed);
  final List<String> _failed = <String>[];

  /// Boots the audio engine. Safe to call twice.
  ///
  /// Named for the engine rather than for a voice, because [start] on the
  /// interface begins a sound and two meanings of one word in one class is how
  /// somebody eventually calls the wrong one.
  @override
  Future<void> open() async {
    if (_soloud.isInitialized) return;
    // The web module races the app. flutter_soloud's two script tags are
    // loaded with `defer`, the wasm behind them initialises after `main` is
    // already running, and an `init` called in that gap throws reading
    // `_isInited` off a module that is not there yet — which every demo on
    // the site did, on every load, and it looked exactly like a game with no
    // sound. The gap measured under a second on the deployed demos, so a
    // patient loop covers it; a genuinely broken engine still surfaces,
    // because the last attempt rethrows into the caller's own
    // fallback-to-silence.
    const attempts = 20;
    for (var attempt = 1; ; attempt++) {
      try {
        await _soloud.init();
        return;
      } catch (_) {
        if (attempt == attempts) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  /// Frees the sources and shuts the engine down.
  ///
  /// **`deinit` is the half this was missing.** Dropping the sources leaves
  /// the audio device open for the life of the process, and [open] returns
  /// early when `isInitialized` — so a second backend after a hot restart
  /// attached to an engine nobody had re-initialised and played nothing, which
  /// looks exactly like a game with no sound.
  @override
  Future<void> dispose() async {
    _sources.clear();
    _sampleRates.clear();
    _failed.clear();
    await _soloud.disposeAllSources();
    if (_soloud.isInitialized) _soloud.deinit();
  }

  @override
  Future<void> preload(String asset) async {
    if (_sources.containsKey(asset)) return;
    final AudioSource source;
    try {
      // The bytes first and the source from them, rather than `loadAsset`:
      // the file's sample rate is in its header, and the filter below has to
      // know it. See `cutoff.dart`.
      final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
      _sampleRates[asset] = wavSampleRate(bytes) ?? _kAssumedSampleRate;
      source = await _soloud.loadMem(asset, bytes);
    } catch (error) {
      // A missing sound leaves the game silent in one place rather than
      // stopping it. Losing a footstep should not cost the play-test — but it
      // is worth saying out loud, because silence is what a sound that works
      // and a sound that failed to decode look like from the outside.
      _failed.add(asset);
      onIssue(Issue('could not load "$asset": $error'));
      return;
    }
    _sources[asset] = source;
    // A low-pass on every source, open all the way, so a voice heard through
    // a wall can be dulled by moving its cutoff rather than by starting a
    // filter mid-sound — which is a click. Per source rather than global,
    // because a global filter has one cutoff for every voice at once, and a
    // torch behind the door and a torch beside you are not the same torch.
    try {
      final filter = source.filters.biquadFilter;
      if (!filter.isActive) filter.activate();
      filter.type().value = _kLowPass;
      // What a voice starts with before [start] sets its own: open for any
      // speed down to half, so no voice ever begins past its Nyquist.
      filter.frequency().value = openCutoff(
        sampleRate: _sampleRates[asset]!,
        rate: 0.5,
      );
    } catch (error) {
      if (!_filterRefused) {
        _filterRefused = true;
        onIssue(
          Issue(
            'no low-pass filter on this platform, walls only quieten: $error',
          ),
        );
      }
    }
  }

  /// SoLoud's biquad type for a low-pass.
  static const double _kLowPass = 0.0;

  /// What a file that is not a WAV is taken to be recorded at: what
  /// compressed formats nearly always are.
  static const int _kAssumedSampleRate = 44100;

  /// Each loaded asset's sample rate, from its header.
  final Map<String, int> _sampleRates = <String, int>{};

  /// The sample rate of each live voice's file.
  final Map<SoundHandle, int> _voiceRate = <SoundHandle, int>{};

  /// Said once. A platform without the filter is a platform where walls only
  /// quieten, which is what every platform did until now.
  bool _filterRefused = false;

  /// Which source each live voice came from, for reaching its filter.
  final Map<SoundHandle, AudioSource> _voiceSource =
      <SoundHandle, AudioSource>{};

  /// The cutoff each voice was last given, so a voice nothing has changed
  /// costs no call into the engine.
  final Map<SoundHandle, double> _voiceCutoff = <SoundHandle, double>{};

  /// Moves a voice's cutoff to where [muffle] says, for the speed [rate] it
  /// plays at: see [muffledCutoff], and [openCutoff] for why the speed
  /// matters. Skipped when the cutoff is within a percent of where it was.
  void _applyMuffle(SoundHandle handle, double muffle, double rate) {
    if (_filterRefused) return;
    final source = _voiceSource[handle];
    final sampleRate = _voiceRate[handle];
    if (source == null || sampleRate == null) return;
    final cutoff = muffledCutoff(
      openCutoff(sampleRate: sampleRate, rate: rate),
      muffle,
    );
    final last = _voiceCutoff[handle];
    if (last != null && (last - cutoff).abs() < 0.01 * last) return;
    _voiceCutoff[handle] = cutoff;
    try {
      source.filters.biquadFilter.frequency(soundHandle: handle).value = cutoff;
    } catch (error) {
      _filterRefused = true;
      onIssue(
        Issue(
          'the low-pass filter refused a voice, walls only quieten: $error',
        ),
      );
    }
  }

  @override
  VoiceId? start(
    String asset, {
    required double gain,
    required double pan,
    required double rate,
    required bool loop,
    double muffle = 0.0,
  }) {
    final source = _sources[asset];
    if (source == null) return null;
    try {
      // **Started held while the backend is paused.** A sound the game
      // started under a pause menu, or in the frame the application went to
      // the background, used to play at once, over the pause; held here, it
      // is listed like any other voice and [resume] lets it go with them.
      final handle = _soloud.play(
        source,
        volume: gain,
        pan: pan,
        looping: loop,
        paused: _paused,
      );
      // Set rather than passed: `play` has no speed argument, and setting it on
      // the handle immediately afterwards is the same frame, so nothing is
      // audible at the wrong speed.
      if (rate != 1.0) _soloud.setRelativePlaySpeed(handle, rate);
      _voiceSource[handle] = source;
      _voiceRate[handle] = _sampleRates[asset] ?? _kAssumedSampleRate;
      // Always, not only when muffled: the source's own cutoff is safe for
      // any speed down to half, and this voice may be slower, or faster and
      // due a brighter one.
      _applyMuffle(handle, muffle, rate);
      return handle;
    } catch (error) {
      onIssue(Issue('could not play "$asset": $error'));
      return null;
    }
  }

  /// **The three below run per audible voice per frame, and were the three
  /// with no guard.** Only [start] was wrapped, which is backwards: a throw
  /// there costs one sound, and a throw here comes out of the render loop and
  /// takes the frame with it. A `SoundHandle` goes stale for reasons this side
  /// does not control — a device change, an engine torn down underneath a
  /// voice — and the right answer to a stale handle is to stop using it, not
  /// to stop the game.
  @override
  void update(
    VoiceId voice, {
    required double gain,
    required double pan,
    required double rate,
    double muffle = 0.0,
  }) {
    final handle = voice as SoundHandle;
    try {
      _soloud
        ..setVolume(handle, gain)
        ..setPan(handle, pan)
        ..setRelativePlaySpeed(handle, rate);
    } catch (error) {
      onIssue(Issue('could not update a voice: $error'));
    }
    _applyMuffle(handle, muffle, rate);
  }

  @override
  void stop(VoiceId voice) {
    final handle = voice as SoundHandle;
    _voiceSource.remove(handle);
    _voiceRate.remove(handle);
    _voiceCutoff.remove(handle);
    try {
      _soloud.stop(handle);
    } catch (error) {
      onIssue(Issue('could not stop a voice: $error'));
    }
  }

  /// Pauses every voice this backend started and has not stopped, and holds
  /// every voice [start]ed before [resume].
  @override
  void pause() => _setPaused(true);

  /// Lets the voices [pause] held go on, and the ones started since.
  @override
  void resume() => _setPaused(false);

  /// Whether [pause] holds the voices: set by [pause], cleared by [resume].
  bool get isPaused => _paused;
  bool _paused = false;

  void _setPaused(bool paused) {
    _paused = paused;
    for (final handle in _voiceSource.keys) {
      try {
        // A one-shot that ran out is still listed until the mix forgets it.
        if (_soloud.getIsValidVoiceHandle(handle)) {
          _soloud.setPause(handle, paused);
        }
      } catch (error) {
        // A voice that ran out between the last mix and now; the next mix
        // forgets it.
        onIssue(Issue('could not pause a voice: $error'));
      }
    }
  }

  @override
  bool isAlive(VoiceId voice) {
    try {
      return _soloud.getIsValidVoiceHandle(voice as SoundHandle);
    } catch (error) {
      // Not alive, which is the answer that lets the scene forget it. Saying
      // "yes" here would keep a dead handle being updated every frame for the
      // life of the level.
      onIssue(Issue('could not ask about a voice: $error'));
      return false;
    }
  }
}
