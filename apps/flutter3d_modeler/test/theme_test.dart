/// `kModelerScheme` held to the design hand-over's own exact hex values —
/// an intermediate UI review (this session, against commit `ff645927`) found
/// seven surface/outline roles and `primary` itself drifted from the spec by
/// one to three hex digits each. This is the regression guard for exactly
/// that class of drift, the same shape `theme.dart`'s own header comment
/// already promises ("a test holds each of them to that hex").
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_modeler/src/mesh_overlay_builder.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every colour `doc/design/modeler-handoff/README.md`'s own table names, by
/// the role this application keeps it in — `ux-32`.
///
/// **The whole table in one place, rather than a test per row.** The review
/// found four tones drifted at once, which is what happens when a table is
/// checked row by row and a new row is added by copying a neighbour. A map
/// fails with the role's own name in the message and cannot be added to
/// without deciding what the hex is.
const Map<String, Color> kHandoffTones = <String, Color>{
  'surfaceContainerLowest': Color(0xFF0B0E0F),
  'surfaceContainerLow': Color(0xFF131617),
  'surfaceContainer': Color(0xFF171A1B),
  'surfaceContainerHigh': Color(0xFF1B1F20),
  'surfaceContainerHighest': Color(0xFF262A2B),
  'onSurface': Color(0xFFE1E3E3),
  'onSurfaceVariant': Color(0xFFBFC8CA),
  'outline': Color(0xFF899295),
  'outlineVariant': Color(0xFF3F484A),
  'primary': Color(0xFF5FD4E4),
  'primaryContainer': Color(0xFF004F58),
  'onPrimaryContainer': Color(0xFFA2EEFF),
  'secondary': Color(0xFFFF458E),
  'tertiary': Color(0xFFFFB86B),
  'tertiaryContainer': Color(0xFF3A2118),
  'onTertiaryContainer': Color(0xFFFFD9B0),
};

Color _roleOf(ColorScheme scheme, String role) => switch (role) {
  'surfaceContainerLowest' => scheme.surfaceContainerLowest,
  'surfaceContainerLow' => scheme.surfaceContainerLow,
  'surfaceContainer' => scheme.surfaceContainer,
  'surfaceContainerHigh' => scheme.surfaceContainerHigh,
  'surfaceContainerHighest' => scheme.surfaceContainerHighest,
  'onSurface' => scheme.onSurface,
  'onSurfaceVariant' => scheme.onSurfaceVariant,
  'outline' => scheme.outline,
  'outlineVariant' => scheme.outlineVariant,
  'primary' => scheme.primary,
  'primaryContainer' => scheme.primaryContainer,
  'onPrimaryContainer' => scheme.onPrimaryContainer,
  'secondary' => scheme.secondary,
  'tertiary' => scheme.tertiary,
  'tertiaryContainer' => scheme.tertiaryContainer,
  'onTertiaryContainer' => scheme.onTertiaryContainer,
  _ => throw ArgumentError('no reader for $role'),
};

void main() {
  group('ux-32: every tone the hand-off names', () {
    test('is the hex it names', () {
      for (final MapEntry<String, Color> each in kHandoffTones.entries) {
        expect(
          _roleOf(kModelerScheme, each.key),
          each.value,
          reason: '${each.key} has drifted from the hand-off',
        );
      }
    });

    test('and the two it names outside the scheme are where they live', () {
      // The hand-off's own "успех" and its "surface (вьюпорт, тёмная часть)"
      // are not Material roles: one is a verdict colour and the other is the
      // backing the scene is drawn on. Both sit on `ModelerColors`.
      expect(ModelerColors.dark.success, const Color(0xFF7EE081));
      expect(ModelerColors.dark.viewport, const Color(0xFF0E1112));
    });

    test("ColorScheme.surface is not the hand-off's own surface row, on "
        'purpose', () {
      // **The hand-off's `surface` row is the viewport**, which is what its
      // own "(вьюпорт, тёмная часть) — подложка сцены" says. Material's
      // `surface` is the ambient background every component falls back to,
      // so painting it `#0E1112` would make a dialog, a menu and a card the
      // same colour as the picture. The window's own background is
      // `surfaceContainerLowest`, which is the row the hand-off actually
      // gives for "фон окна", and every shell reads that.
      expect(kModelerScheme.surface, const Color(0xFF14181A));
      expect(kModelerScheme.surface, isNot(ModelerColors.dark.viewport));
    });

    test('the warm selection colour in the viewport is a deliberate '
        'difference', () {
      // The hand-off puts a selected face at `primaryContainer` 55 % with a
      // `primary` outline. `MeshOverlayColours` draws it warm instead, and
      // that is a decision rather than drift: `pro-uv-01` gave a UV seam its
      // own cool blue, and a teal selection beside a blue seam is two cool
      // lines a person has to compare rather than tell apart. What the
      // hand-off is protecting — one accent family, nothing competing with
      // the model — the warm accent protects too, against a grey model on a
      // near-black ground.
      final MeshOverlayColours colours = MeshOverlayColours();
      expect(colours.selected.x, greaterThan(colours.selected.z));
      expect(colours.seam.z, greaterThan(colours.seam.x));
    });
  });

  // **The per-role tests that used to be here are the table above now.**
  // `ui-38d` and the review before it each added a `test()` per colour, and a
  // list of sixteen one-line tests is a list somebody extends by copying a
  // neighbour and forgetting to change the hex. What is left in this group is
  // everything that is not a colour.
  group('ui-38d — the rest of the token pass', () {
    test('ModelerColors.success', () {
      expect(ModelerColors.dark.success, const Color(0xFF7EE081));
    });

    test('the panel-title style is 14/500', () {
      final TextTheme text = modelerTheme().textTheme;
      expect(text.titleMedium?.fontSize, 14);
      expect(text.titleMedium?.fontWeight, FontWeight.w500);
    });

    test('the global slider theme is a 4-thick track and a ⌀16 thumb', () {
      final SliderThemeData slider = modelerTheme().sliderTheme;
      expect(slider.trackHeight, 4);
      expect(
        (slider.thumbShape! as RoundSliderThumbShape).enabledThumbRadius,
        8,
      );
    });

    test('the rail button is 40×36, radius 10', () {
      expect(ModelerMetrics.railButtonWidth, 40);
      expect(ModelerMetrics.railButtonHeight, 36);
      expect(ModelerMetrics.railButtonRadius, 10);
    });

    testWidgets(
      'a SectionLabel under modelerTheme draws 11/400, 0.08em, outline',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: const Scaffold(body: SectionLabel('Shadows')),
          ),
        );

        final Text text = tester.widget(find.byType(Text));
        expect(text.style?.fontSize, 11);
        expect(text.style?.fontWeight, FontWeight.w400);
        expect(text.style?.letterSpacing, 0.88);
        expect(text.style?.color, kModelerScheme.outline);
      },
    );
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
