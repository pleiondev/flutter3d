/// A bank knows what is in it, so nobody has to keep a second list.
///
///     flutter test test/sound_bank_test.dart
///
/// **The platformer lost six of its fourteen sounds** by declaring them and not
/// adding them to the list beside them. The game was half mute for months and
/// nothing noticed, because a sound that was never preloaded plays silently and
/// hands back an emitter exactly like one that was.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';

const SoundDef _step = SoundDef(name: 'step', asset: 'a/step.wav');
const SoundDef _jump = SoundDef(name: 'jump', asset: 'a/jump.wav');

void main() {
  test('is the list, so there is no second one to forget', () {
    // The whole point stated as an identity: what a game declares and what the
    // mixer preloads are the same object. There is nowhere for them to differ.
    final bank = SoundBank(<SoundDef>[_step, _jump]);

    expect(bank.sounds, <SoundDef>[_step, _jump]);
    expect(bank.length, 2);
  });

  test('and can be handed straight to anything that preloads', () {
    // `AudioScene.preload` takes an `Iterable<SoundDef>`, which is why this is
    // one: a game swapping its hand-written list for a bank changes the
    // declaration and not a single call site.
    final bank = SoundBank(<SoundDef>[_step, _jump]);

    expect(bank, isA<Iterable<SoundDef>>());
    expect(bank.map((SoundDef s) => s.name), <String>['step', 'jump']);
  });

  test('and refuses two sounds under one name', () {
    // The same failure in a different disguise: with two definitions called
    // `step`, whichever a caller asked for, one of them silently wins.
    expect(
      () => SoundBank(<SoundDef>[
        _step,
        const SoundDef(name: 'step', asset: 'a/other.wav'),
      ]),
      throwsArgumentError,
    );
  });

  test('and hands over its assets for a test that can look on disk', () {
    // Deliberately not checked here: this package runs where there is no
    // filesystem — the browser build — so "is the file there" is a question for
    // each game's own test, against this list rather than a copy of it.
    final bank = SoundBank(<SoundDef>[_step, _jump]);

    expect(bank.assets, <String>['a/step.wav', 'a/jump.wav']);
  });

  test('and cannot be added to after it is built', () {
    // A bank that grew after the preload would be a bank whose later entries
    // are silent, which is exactly the failure this replaces.
    final bank = SoundBank(<SoundDef>[_step]);

    expect(() => bank.sounds.add(_jump), throwsUnsupportedError);
  });
}
