/// One list of buses, applied one way.
///
///     flutter test test/volumes_test.dart
///
/// **There were four lists.** The settings panel had its own and each of the
/// three games wrote the same three names again where it copied the saved
/// volumes into the mixer. The panel's own doc records the day they disagreed:
/// the mixer had a music bus, the application was already restoring its saved
/// volume, and the panel simply never offered the slider — so the one a player
/// reaches for first was the one that did not exist.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every bus a player is offered is a bus that gets applied', () {
    // The claim the four lists could not make. Written as a loop over the one
    // list rather than three assertions, so a fourth bus is covered the day it
    // is added.
    final config = GameConfig();
    for (final bus in settableBuses) {
      config.setVolume(bus.name, 0.25);
    }
    final mixer = Mixer();

    applySavedVolumes(config, mixer);

    for (final bus in settableBuses) {
      expect(mixer.volumeOf(bus), closeTo(0.25, 1e-9),
          reason: '${bus.name} is offered and never applied');
    }
  });

  test('and a bus nobody saved keeps what the mixer had', () {
    // A fresh config has no volumes in it, and the answer is the default rather
    // than silence: a game that opened muted because nothing had been saved yet
    // would be a game nobody hears on first launch.
    final mixer = Mixer();
    final before = mixer.volumeOf(AudioBus.master);

    applySavedVolumes(GameConfig(), mixer);

    expect(mixer.volumeOf(AudioBus.master), closeTo(before, 1e-9));
  });

  test('and the master bus is one of them', () {
    // Named rather than assumed: a list that lost the master would leave a
    // player with no way to turn the game down at all.
    expect(settableBuses, contains(AudioBus.master));
    expect(settableBuses, contains(AudioBus.music));
    expect(settableBuses, contains(AudioBus.sfx));
  });
}
