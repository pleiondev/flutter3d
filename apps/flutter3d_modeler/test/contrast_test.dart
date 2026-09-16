/// `ux-34`: the two pairs the review measured below the WCAG thresholds,
/// computed from the theme rather than read off a screenshot.
///
///     flutter test test/contrast_test.dart
///
/// **Computed, because a contrast ratio is arithmetic and a screenshot is
/// not.** The review found both of these by measuring a picture, which is
/// the only way to find one nobody has written a check for — and is also a
/// measurement that has to be redone by hand every time a tone moves. These
/// read the same constants the painter and the theme read, so a tone that
/// moves takes the check with it.
///
/// The thresholds are WCAG 2.2's own: 3:1 for a user-interface component or
/// a graphical object somebody has to see to use it (1.4.11), and 4.5:1 for
/// text below the large-text size (1.4.3). Nine pixels is below it by every
/// definition there is.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/orientation_dial.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// One channel, from sRGB's own 0–1 encoding to the linear light it stands
/// for — WCAG's own formula, not an approximation of it.
double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// The relative luminance of [colour], per WCAG 2.2.
double luminance(Color colour) =>
    0.2126 * _linear(colour.r) +
    0.7152 * _linear(colour.g) +
    0.0722 * _linear(colour.b);

/// The contrast ratio between [a] and [b], lighter over darker.
double contrast(Color a, Color b) {
  final double one = luminance(a);
  final double two = luminance(b);
  final double lighter = math.max(one, two);
  final double darker = math.min(one, two);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('ux-34: the two pairs that were below threshold', () {
    test('a slider track and a sheet handle reach 3:1 on both panel tones', () {
      final Color track = ModelerColors.dark.controlTrack;

      // **The hand-off puts these on `outlineVariant`, at 1.94:1.** A
      // divider may be that quiet — nothing depends on seeing one — but the
      // unfilled half of a track is what says how far a slider goes, and the
      // handle is the only thing saying a sheet can be dragged at all.
      for (final Color behind in <Color>[
        kModelerScheme.surfaceContainer,
        kModelerScheme.surfaceContainerLow,
      ]) {
        expect(
          contrast(track, behind),
          greaterThanOrEqualTo(3.0),
          reason: 'the track is invisible on this panel',
        );
      }
    });

    test(
      'and the tone it replaced would still fail, which is why it moved',
      () {
        // Mutation: put `outlineVariant` back, on the argument that the table
        // says so. This is the number that argument costs.
        expect(
          contrast(
            kModelerScheme.outlineVariant,
            kModelerScheme.surfaceContainerLow,
          ),
          lessThan(3.0),
        );
      },
    );

    test("the dial's own nine-pixel letters reach 4.5:1 on every ball", () {
      for (final MapEntry<String, Color> each in kDialAxisColours.entries) {
        expect(
          contrast(kDialLabel, each.value),
          greaterThanOrEqualTo(4.5),
          reason: '"${each.key}" cannot be read on its own ball',
        );
      }
    });

    test('and the near-black it was drawn in would not, on X', () {
      // The review's own 4.38:1. Mutation: go back to the viewport's own
      // near-black because it looks the same — on five of the six balls it
      // does, and on the warm one it is the whole of the margin.
      expect(
        contrast(ModelerColors.dark.viewport, kDialAxisColours['X']!),
        lessThan(4.5),
      );
    });
  });

  group('the formula itself', () {
    test('black on white is 21:1 and a colour against itself is 1:1', () {
      // A guard on the guard: every expectation above is only as good as
      // this arithmetic, and these two are the values WCAG states outright.
      expect(
        contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
      expect(
        contrast(kModelerScheme.primary, kModelerScheme.primary),
        closeTo(1.0, 1e-9),
      );
    });
  });
}
