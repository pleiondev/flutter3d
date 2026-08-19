/// What the game loads, against what the game plays.
///
///     flutter test test/sounds_test.dart
///
/// **The game shipped half silent and nothing noticed.** `Sounds` declared
/// fourteen sounds; `Sounds.all` — the list handed to `preload` — named eight.
/// The six left out were the footsteps, the springs, the crumbling shelves and
/// the fanfare at the exit: declared, with their `.wav` on disk, shipped in the
/// bundle, asked for by `Soundtrack` every time they happened, and never loaded
/// — so the backend had no source, returned no voice, and made no sound.
///
/// It leaked as well. An emitter that never gets a voice is neither stopped nor
/// finished, and those are the only two things `AudioScene.update` retires, so
/// each attempt left one behind for the length of the run — about one per two
/// metres walked.
///
/// **A list beside a list, with nothing comparing them**, which is the same
/// shape as the credits: a directory of models and a list of authors, kept in
/// step by hand until they were not. That one is guarded by walking the
/// directory; this one is guarded by reading the declarations.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/sounds.dart';

/// Every `SoundDef` this game declares, by name, read out of the source.
///
/// From the file rather than from a second list, because a second list is the
/// bug. Dart has no reflection to ask a class what it holds, so the source is
/// the only place that knows — and it is the same source the compiler reads.
Set<String> _declared() {
  final source = File('lib/src/sounds.dart').readAsStringSync();
  return RegExp(r'static const SoundDef ([A-Za-z]+)')
      .allMatches(source)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

/// The names inside the bank's own literal.
///
/// Still read from the source, and still necessary: a `SoundBank` removes the
/// *second list* — there is nothing left that has to agree with anything — but
/// it cannot see a constant declared beside it and left out. No type can. This
/// is the check that catches that, and it is the check the platformer needed
/// and did not have when six of its fourteen went missing.
Set<String> _loaded() {
  final source = File('lib/src/sounds.dart').readAsStringSync();
  final list = RegExp(r'static final SoundBank all = SoundBank\(<SoundDef>\[(.*?)\]\);',
          dotAll: true)
      .firstMatch(source)!
      .group(1)!;
  return RegExp(r'([A-Za-z]+),')
      .allMatches(list)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

void main() {
  test('every sound the game declares is one the game loads', () {
    // **The one that was false.** A declared sound that is not preloaded is a
    // sound that can never play: the backend has no source for it, hands back
    // no voice, and the emitter waits for one for ever.
    final missing = _declared().difference(_loaded());

    expect(missing, isEmpty,
        reason: 'declared and never preloaded, so silent in the real build: '
            '${missing.join(', ')}');
  });

  test('and nothing is loaded that was never declared', () {
    expect(_loaded().difference(_declared()), isEmpty);
  });

  test('and every one of them has its file where it says', () {
    // The other way this goes silent, and it looks identical from the outside:
    // a definition pointing at an asset that is not there.
    for (final sound in Sounds.all) {
      expect(File(sound.asset).existsSync(), isTrue,
          reason: '${sound.asset} is declared and not in the game');
    }
  });

  test('and the ones the level surfaces name are among them', () {
    // `stepOn` picks by the surface a brush is made of, and a surface nobody
    // named falls through to stone. All three have to be loadable or the game
    // walks in silence on that floor only — which is the hardest kind of this
    // bug to notice, because it is silent in one place and not another.
    for (final surface in <String?>['ice', 'moss', 'stone', null, 'nonsense']) {
      expect(Sounds.all, contains(Sounds.stepOn(surface)), reason: '$surface');
    }
  });
}
