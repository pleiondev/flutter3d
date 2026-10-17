import 'package:vector_math/vector_math.dart';

import 'audio_scene.dart';
import 'mixer.dart';
import 'sound.dart';

/// One thing to be heard while it lasts: [key] the same from frame to frame
/// while it goes on — a fire, a fall of water, an engine — where it is, how
/// loud, and how fast its sound plays, one its recording's own speed.
typedef Held = ({int key, Vector3 at, double gain, double rate});

/// One looping voice of [sound] for each thing held, kept by its key: begun
/// when it is first heard, moved and turned to it each frame, stopped when
/// it is no longer heard.
///
/// A scene swapped for another — a game's silent one for the speakers' once
/// they open — takes its voices with it; the next [hold] begins them again
/// in the new one.
///
/// Each voice is an [AudioEmitter] on [bus] — the sound's own unless one was
/// given — so a mixer snapshot or a ducking rule reaches held voices as it
/// reaches everything else.
final class HeldVoices {
  HeldVoices(this.sound, {AudioBus? bus}) : bus = bus ?? sound.bus;

  /// What each voice plays: a looping sound.
  final SoundDef sound;

  /// The bus each voice plays on.
  final AudioBus bus;

  final Map<int, AudioEmitter> _voices = <int, AudioEmitter>{};
  AudioScene? _scene;

  /// How many voices are playing.
  int get count => _voices.length;

  /// The frame's [heard], played through [scene].
  void hold(AudioScene scene, Iterable<Held> heard) {
    if (!identical(scene, _scene)) {
      _voices.clear();
      _scene = scene;
    }
    final live = <int>{};
    for (final h in heard) {
      live.add(h.key);
      (_voices[h.key] ??= scene.play(sound, h.at, bus: bus))
        ..position.setFrom(h.at)
        ..gain = h.gain
        ..rate = h.rate;
    }
    _voices.removeWhere((key, voice) {
      if (live.contains(key)) return false;
      voice.stop();
      return true;
    });
  }

  /// Every voice stopped.
  void silence() {
    for (final voice in _voices.values) {
      voice.stop();
    }
    _voices.clear();
  }
}
