import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// The buses a player is offered, in the order the panel shows them.
///
/// **One list, because there were four.** The settings panel had its own, and
/// each of the three games wrote the same three names again in its
/// `_applyConfig`. That is not a tidiness complaint: the panel's own doc records
/// the day the lists disagreed — *"Music was missing here… the mixer has had the
/// bus since the soundtrack landed and the application was already restoring its
/// saved volume; the panel simply never offered it, so the one slider a player
/// reaches for first was the one that did not exist."*
///
/// A fourth bus now costs one line rather than four, and a slider that nobody
/// applies is no longer possible to write by accident.
const List<AudioBus> settableBuses = <AudioBus>[
  AudioBus.master,
  AudioBus.music,
  AudioBus.sfx,
];

/// The buses [sounds] actually reaches, in the order [settableBuses] lists.
///
/// **The other half of the mistake [settableBuses] was written to end.** One
/// list stopped a game from applying a volume the panel offered; it did not
/// stop a game from *offering* a volume nothing in it plays. The crypt and the
/// circuit have no music — every one of their sounds takes `SoundDef`'s
/// default bus — and both showed a Music slider that moved, was written to
/// disk, was applied to the mixer, and changed nothing a player could hear.
///
/// Derived from the bank rather than listed per game, so the slider comes back
/// by itself on the day one of them gets a soundtrack, and cannot be left
/// behind on the day one loses it.
///
/// [AudioBus.master] is always here: it is the volume of everything, and a game
/// with any sound at all has something for it to turn down.
List<AudioBus> busesIn(Iterable<SoundDef> sounds) {
  final used = sounds.map((SoundDef sound) => sound.bus).toSet();
  return <AudioBus>[
    for (final bus in settableBuses)
      if (bus == AudioBus.master || used.contains(bus)) bus,
  ];
}

/// Copies every saved volume into [mixer].
///
/// Called when the settings are loaded and again whenever one changes, which is
/// the whole of what an application has to do about volume.
void applySavedVolumes(GameConfig config, Mixer mixer) {
  for (final bus in settableBuses) {
    mixer.setVolume(bus, config.volumeOf(bus.name));
  }
}
