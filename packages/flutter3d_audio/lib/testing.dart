/// Reading a game's sound table out of its own source, for the one check no
/// type can make.
///
///     import 'package:flutter3d_audio/testing.dart';
///
///     final it = soundTableIn('lib/src/sounds.dart');
///     expect(it.declared.difference(it.inTheBank), isEmpty);
///
/// **A `SoundBank` removes the second list and cannot remove this.** There is
/// nothing left that has to agree with anything — the bank *is* the list a mixer
/// preloads — but a `static const SoundDef` declared beside it and left out of
/// it is invisible to every type in Dart, because there is no reflection to ask
/// a class what it holds. The source is the only place that knows, and it is the
/// same source the compiler reads.
///
/// It is worth the ugliness: the platformer shipped for months with six of its
/// fourteen sounds declared and not banked, and the game was half mute.
///
/// ## Why this is here rather than in each game
///
/// Because it was in three of them, twice each — `_declared` and `_inTheBank`,
/// the same two regular expressions copied — and a scan in three copies is two
/// copies that will stop matching the day somebody reformats a bank.
///
/// It returns the two sets rather than asserting on them. Asserting would mean
/// `flutter_test` as a real dependency of a package that ships to a browser, to
/// save each caller three lines.
library;

import 'dart:io';

/// What [path] declares, and what its bank actually holds.
///
/// [path] is a Dart source file with `static const SoundDef` declarations and a
/// `static final SoundBank all = SoundBank(<SoundDef>[…])` beside them, which is
/// the shape all three games use.
({Set<String> declared, Set<String> inTheBank}) soundTableIn(String path) {
  final source = File(path).readAsStringSync();

  final declared = RegExp(
    r'static const SoundDef ([A-Za-z]+)',
  ).allMatches(source).map((RegExpMatch m) => m.group(1)!).toSet();

  final literal = RegExp(
    r'static final SoundBank all = SoundBank\(<SoundDef>\[(.*?)\]\);',
    dotAll: true,
  ).firstMatch(source);
  if (literal == null) {
    // Loud rather than empty. An empty set makes "the bank holds nothing" and
    // "the pattern stopped matching" the same answer, and only one of them is
    // the game's fault.
    throw StateError(
      'no `static final SoundBank all = SoundBank(<SoundDef>[…]);` in $path. '
      'If the bank has been written a different way, this scan has to learn '
      'the new shape or it will report every sound as missing.',
    );
  }

  final inTheBank = RegExp(
    r'([A-Za-z]+),',
  ).allMatches(literal.group(1)!).map((RegExpMatch m) => m.group(1)!).toSet();

  return (declared: declared, inTheBank: inTheBank);
}
