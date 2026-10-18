/// `LessonTheme`'s colours held to WCAG 2.2 at level AA: each pair a
/// student has to tell apart keeps its ratio over every grey frame from
/// black to white, and no colour stands outside a pair.
library;

import 'dart:ui' show Color;

import 'package:flutter3d_game_ui/theme.dart' show ContrastPair, Wcag;
import 'package:flutter3d_lesson_viewer/src/lesson_theme.dart';
import 'package:flutter_test/flutter_test.dart';

ContrastPair _pair(LessonContrast pair) => ContrastPair(
  pair.name,
  foreground: pair.foreground,
  background: pair.background,
  minimum: pair.text ? Wcag.textContrast : Wcag.nonTextContrast,
  edge: pair.edge,
);

void main() {
  test('every pair the viewer names holds over any frame', () {
    expect(LessonTheme.pairs, isNotEmpty);
    for (final pair in LessonTheme.pairs.map(_pair)) {
      expect(
        pair.worstRatio,
        greaterThanOrEqualTo(pair.minimum),
        reason: '${pair.name} falls to ${pair.worstRatio.toStringAsFixed(2)}',
      );
    }
  });

  test('every colour of the theme is in a pair', () {
    final paired = <int>{
      for (final pair in LessonTheme.pairs) ...<int>[
        pair.foreground.toARGB32(),
        pair.background.toARGB32(),
        if (pair.edge case final edge?) edge.toARGB32(),
      ],
    };
    for (final token in LessonTheme.tokens) {
      expect(
        paired,
        contains(token.toARGB32()),
        reason: '0x${token.toARGB32().toRadixString(16)} is in no pair',
      );
    }
  });

  test('the check can fail: the white at half the hint once was does not '
      'read on the scrim over a light frame', () {
    final washedOut = _pair((
      name: 'white54 on scrim',
      foreground: const Color(0x8AFFFFFF),
      background: LessonTheme.scrim,
      text: true,
      edge: null,
    ));
    expect(washedOut.isMet, isFalse);
  });

  test('the focus ring alone, without its rim, vanishes over white', () {
    final bare = _pair((
      name: 'ring without rim',
      foreground: LessonTheme.focusRing,
      background: const Color(0x00000000),
      text: false,
      edge: null,
    ));
    expect(bare.isMet, isFalse);
  });
}
