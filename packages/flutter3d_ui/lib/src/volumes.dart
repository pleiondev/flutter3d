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

/// Copies every saved volume into [mixer].
///
/// Called when the settings are loaded and again whenever one changes, which is
/// the whole of what an application has to do about volume.
void applySavedVolumes(GameConfig config, Mixer mixer) {
  for (final bus in settableBuses) {
    mixer.setVolume(bus, config.volumeOf(bus.name));
  }
}
