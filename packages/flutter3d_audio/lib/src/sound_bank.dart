import 'package:vector_math/vector_math.dart';

import 'sound.dart';

/// Everything one game can make a noise about, as one list.
///
/// ## The failure this exists because of
///
/// All three games in this repository wrote the same shape by hand: a class of
/// `static const SoundDef` constants, and beside them a `static const List` of
/// the ones to preload. Two lists of the same facts, kept in step by whoever
/// remembered.
///
/// The platformer did not remember. **Six of its fourteen definitions were
/// never added to the list**, so the mixer preloaded eight — and the game was
/// half mute for months without anything noticing, because a sound that was
/// never loaded plays silently and returns an emitter exactly like one that
/// did. Footsteps on three of four surfaces, the spring, the crumble and the
/// exit fanfare: all declared, all referenced, none audible.
///
/// A bank is that one list. What it removes is the *duplication* — there is no
/// longer a second collection that has to agree with a first — and what it adds
/// is that the collection cannot be extended after it is built, and cannot hold
/// two sounds under one name.
///
/// **It does not remove the omission**, and that is worth saying plainly: a
/// `static const SoundDef` declared beside the bank and left out of it is still
/// silent, and no type can see that. Each game keeps a test that reads its own
/// source and compares what is declared against what is in the bank; this makes
/// that test *possible to write once per game* instead of once per list.
///
/// ## What it deliberately does not do
///
/// It does not check that the files are on disk. That is a question about the
/// filesystem and this package runs where there is none — see the browser
/// build. Each game's own test asks it, in three lines, against the same
/// [sounds] list; what this removes is the half that could be got wrong in a
/// place nobody looks.
/// An [Iterable] on purpose: `AudioScene.preload` already takes one, so a game
/// that swaps its hand-written list for a bank changes the declaration and not
/// a single call site.
final class SoundBank extends Iterable<SoundDef> {
  SoundBank(Iterable<SoundDef> sounds)
    : sounds = List<SoundDef>.unmodifiable(sounds) {
    final seen = <String>{};
    for (final sound in this.sounds) {
      if (!seen.add(sound.name)) {
        // Two definitions under one name is a bank where the second silently
        // wins whatever a caller asked for, which is the same class of failure
        // in a different disguise.
        throw ArgumentError('two sounds are called "${sound.name}"');
      }
    }
  }

  /// Everything in it, in the order it was declared. This is what a mixer
  /// preloads, and there is no other list to keep in step with it.
  final List<SoundDef> sounds;

  @override
  Iterator<SoundDef> get iterator => sounds.iterator;

  /// Every asset path in it, for a test that wants to look on disk.
  Iterable<String> get assets => sounds.map((SoundDef s) => s.asset);
}

/// One sound, and where it happened.
///
/// **A decision, not a call.** Whether a step made a noise is a fact about the
/// simulation and can be asserted without a device; playing it needs an
/// [AudioScene], a backend and a window. Splitting the two is what lets a test
/// say "a monster died here and nothing was heard" — and both games that have
/// done the split found real silence with it: six sounds missing from one
/// bank, four weapons sharing two sounds in the other.
///
/// It arrived twice, identically, in two applications' `soundtrack.dart`. What
/// each game keeps is the deciding; this is only the shape of an answer.
final class Heard {
  const Heard(this.sound, this.at);

  final SoundDef sound;

  /// Where in the world it happened, for the panning. Not where the listener
  /// is — a sound placed at the ear is a sound with no direction.
  final Vector3 at;

  @override
  String toString() => 'Heard(${sound.name})';
}
