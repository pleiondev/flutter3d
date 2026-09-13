/// `kModelerScheme` held to the design hand-over's own exact hex values —
/// an intermediate UI review (this session, against commit `ff645927`) found
/// seven surface/outline roles and `primary` itself drifted from the spec by
/// one to three hex digits each. This is the regression guard for exactly
/// that class of drift, the same shape `theme.dart`'s own header comment
/// already promises ("a test holds each of them to that hex").
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kModelerScheme matches the design hand-over exactly', () {
    test('primary', () {
      expect(kModelerScheme.primary, const Color(0xFF5FD4E4));
    });

    test('primaryContainer', () {
      expect(kModelerScheme.primaryContainer, const Color(0xFF004F58));
    });

    test('onPrimaryContainer', () {
      expect(kModelerScheme.onPrimaryContainer, const Color(0xFFA2EEFF));
    });

    test('surfaceContainerLowest', () {
      expect(kModelerScheme.surfaceContainerLowest, const Color(0xFF0B0E0F));
    });

    test('surfaceContainerLow', () {
      expect(kModelerScheme.surfaceContainerLow, const Color(0xFF131617));
    });

    test('surfaceContainer', () {
      expect(kModelerScheme.surfaceContainer, const Color(0xFF171A1B));
    });

    test('surfaceContainerHigh', () {
      expect(kModelerScheme.surfaceContainerHigh, const Color(0xFF1B1F20));
    });

    test('surfaceContainerHighest', () {
      expect(kModelerScheme.surfaceContainerHighest, const Color(0xFF262A2B));
    });

    test('onSurfaceVariant', () {
      expect(kModelerScheme.onSurfaceVariant, const Color(0xFFBFC8CA));
    });

    test('outline — captions and utility values, not a grid line', () {
      expect(kModelerScheme.outline, const Color(0xFF899295));
    });

    test('outlineVariant — dividers and slider tracks', () {
      expect(kModelerScheme.outlineVariant, const Color(0xFF3F484A));
    });

    test('tertiary already matched the spec\'s own warning colour', () {
      // Not part of the review's own finding — checked here so a future
      // edit to this scheme trips the same guard the drifted roles above
      // already have.
      expect(kModelerScheme.tertiary, const Color(0xFFFFB86B));
    });
  });

  test(
    'the divider colour tracks outlineVariant, not a hand-copied surface tone',
    () {
      final theme = modelerTheme();
      expect(theme.dividerTheme.color, kModelerScheme.outlineVariant);
    },
  );

  test(
    'the segmented-button border tracks outlineVariant, not the old outline value',
    () {
      final theme = modelerTheme();
      final side = theme.segmentedButtonTheme.style?.side?.resolve(
        <WidgetState>{},
      );
      expect(side?.color, kModelerScheme.outlineVariant);
    },
  );
}
