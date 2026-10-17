import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:vector_math/vector_math.dart';

/// What is happening to a sound that has a lifetime.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1).
final class Voice {
  const Voice._(this.name);

  /// Start it, at [Sustained.at].
  static const Voice begin = Voice._('begin');

  /// It is still running, and this is where it is now.
  static const Voice follow = Voice._('follow');

  /// Stop it.
  static const Voice end = Voice._('end');

  final String name;

  @override
  String toString() => name;
}

/// A sound with a lifetime: it starts, it follows the thing making it, and it
/// stops.
///
/// **Not the same as a [Heard], and the difference is the whole reason this
/// class exists.** A shot is over before the next step; a stone door grinding
/// open runs for as long as the door moves, has to be repositioned while it
/// runs, and has to be stopped by the same key that started it. Emitting that
/// as a one-shot per step would be a door that stutters instead of grinds.
///
/// The lifetime is decided by the game's soundtrack rather than by whoever
/// plays it, which is what makes [SustainedVoices] a player rather than a
/// bookkeeper: it holds a voice per key and does exactly what each of these
/// says.
final class Sustained {
  const Sustained.begin(this.key, SoundDef this.sound, Vector3 this.at)
    : what = Voice.begin;
  const Sustained.follow(this.key, Vector3 this.at)
    : what = Voice.follow,
      sound = null;
  const Sustained.end(this.key) : what = Voice.end, sound = null, at = null;

  final Voice what;

  /// Whatever is making the noise. The thing itself, so two doors are two
  /// voices and the same door twice is one.
  final Object key;

  /// Only on [Voice.begin]: which sound to start.
  final SoundDef? sound;

  /// Where it is now. Null only when stopping.
  final Vector3? at;

  @override
  String toString() => 'Sustained.${what.name}($key)';
}

/// Everything one step made a noise about: sounds heard [once], and the
/// [loops] begun, moved and stopped.
final class Sounding {
  const Sounding(this.once, this.loops);

  /// Nothing at all.
  static const Sounding silence = Sounding(<Heard>[], <Sustained>[]);

  final List<Heard> once;
  final List<Sustained> loops;
}

/// Plays a [Sounding]: the one-shots fired and forgotten, and one voice per
/// [Sustained.key], begun, moved and stopped as the soundtrack says.
///
/// **The lifetimes are the only thing here, and they are effects rather than
/// decisions.** Which key a grinding door is was decided by the soundtrack;
/// this keeps its voice so the same key can move and stop it.
///
/// Each voice is an [AudioEmitter] on its sound's bus, or on [bus] when one
/// is given.
final class SustainedVoices {
  SustainedVoices({this.bus});

  /// The bus every voice plays on, or null for each sound's own.
  final AudioBus? bus;

  final Map<Object, AudioEmitter> _voices = <Object, AudioEmitter>{};

  /// How many sustained voices are running.
  int get count => _voices.length;

  /// Whether [key]'s voice is running.
  bool isRunning(Object key) => _voices.containsKey(key);

  /// Plays [sounding] through [scene].
  void perform(Sounding sounding, AudioScene scene) {
    for (final heard in sounding.once) {
      scene.play(heard.sound, heard.at, bus: bus);
    }
    for (final loop in sounding.loops) {
      if (identical(loop.what, Voice.begin)) {
        _voices[loop.key] = scene.play(loop.sound!, loop.at!, bus: bus);
      } else if (identical(loop.what, Voice.follow)) {
        _voices[loop.key]?.position.setFrom(loop.at!);
      } else {
        _voices.remove(loop.key)?.stop();
      }
    }
  }

  /// Stops every running voice, for a level change or a restart.
  ///
  /// The [Voice.end] that would have stopped each of these comes from the
  /// thing that began it, and that thing is gone with its level — so a door
  /// caught mid-travel by a level change would be a loop nothing could ever
  /// stop.
  void stop() {
    for (final voice in _voices.values) {
      voice.stop();
    }
    _voices.clear();
  }
}
