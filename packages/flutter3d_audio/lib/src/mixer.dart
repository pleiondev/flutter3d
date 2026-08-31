/// A group of sounds that a player can turn down as one.
///
/// Open the same way `GameAction` is, and for the same reason: the three below
/// are what every settings screen has ever shown, and a game with dialogue or
/// with a separate slider for footsteps declares its own without asking.
final class AudioBus {
  const AudioBus(this.name);

  final String name;

  /// Everything, and the slider labelled "volume".
  static const AudioBus master = AudioBus('master');

  static const AudioBus music = AudioBus('music');

  /// Everything that is not music. The default for a [SoundDef].
  static const AudioBus sfx = AudioBus('sfx');

  @override
  bool operator ==(Object other) => other is AudioBus && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'AudioBus($name)';
}

/// What each bus is turned to, and the one place a volume setting lives.
///
/// ## Why a bus is not part of being audible
///
/// The gain here is applied when a voice is handed to the backend, and
/// **deliberately not** when the mixer decides which sounds get voices at all.
/// Those are two different questions wearing one word:
///
/// * *Can it be heard from there* — distance, occlusion, priority. That decides
///   who gets one of the few voices a device has.
/// * *How loud has the player asked for this kind of thing to be* — this.
///
/// Fold the second into the first and turning the music down lets a distant
/// footstep take the voice the music was holding; turn it back up and the track
/// restarts from the beginning, because its voice was stopped while nobody was
/// listening. Keeping them apart means a muted bus is silent and still playing,
/// which is what a player expects from a slider.
final class Mixer {
  Mixer([Map<AudioBus, double>? volumes]) {
    if (volumes != null) {
      for (final entry in volumes.entries) {
        setVolume(entry.key, entry.value);
      }
    }
  }

  factory Mixer.fromJson(Map<String, Object?> json) {
    final mixer = Mixer();
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is num) mixer.setVolume(AudioBus(entry.key), value.toDouble());
    }
    return mixer;
  }

  final Map<AudioBus, double> _volumes = <AudioBus, double>{};

  /// What [bus] is set to, in `[0, 1]`. Unset buses are full.
  ///
  /// Full rather than silent, so that a game which declares a `dialogue` bus
  /// and forgets to configure it can still be heard. A settings file that has
  /// never been written must not mute anything.
  double volumeOf(AudioBus bus) => _volumes[bus] ?? 1.0;

  void setVolume(AudioBus bus, double volume) =>
      _volumes[bus] = volume.clamp(0.0, 1.0);

  /// The gain a sound on [bus] is actually played at.
  ///
  /// The bus and the master multiplied. Master is not a special case in the
  /// table — it is an ordinary bus that everything is also on.
  double gainFor(AudioBus bus) => bus == AudioBus.master
      ? volumeOf(AudioBus.master)
      : volumeOf(bus) * volumeOf(AudioBus.master);

  /// The buses somebody has actually set, for a settings screen to list.
  Iterable<AudioBus> get configured => _volumes.keys;

  Map<String, Object?> toJson() => <String, Object?>{
        for (final name in _volumes.keys.map((AudioBus b) => b.name).toList()
          ..sort())
          name: volumeOf(AudioBus(name)),
      };
}
