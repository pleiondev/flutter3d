/// Screen 19's own four budget bars — `ui-28`'s and `anim-24`'s own
/// acceptance numbers, used exactly: 28/64 triangles reads green at
/// 0.4375, 19/16 joints reads orange.
///
///     flutter test test/ui/budget_bars_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/budget_bars.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, ProfileBudgetReport report) =>
    tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Scaffold(body: BudgetBars(report: report)),
      ),
    );

const ProfileBudgetReport _report = ProfileBudgetReport(
  triangles: BudgetUsage(used: 28, limit: 64),
  joints: BudgetUsage(used: 19, limit: 16),
  influences: BudgetUsage(used: 4, limit: 4),
  textureBytes: BudgetUsage(used: 100, limit: 1000),
  wireframeDeclined: true,
);

void main() {
  testWidgets(
    '28/64 triangles draws its own bar at fraction 0.4375, in the success '
    'colour',
    (tester) async {
      await _pump(tester, _report);

      final fill = tester.widget<FractionallySizedBox>(
        find.byKey(fillKey('triangles')),
      );
      expect(fill.widthFactor, closeTo(0.4375, 1e-9));

      final colour = tester.widget<DecoratedBox>(
        find.byKey(fillColourKey('triangles')),
      );
      final BoxDecoration decoration = colour.decoration as BoxDecoration;
      final theme = modelerTheme();
      expect(
        decoration.color,
        theme.extension<ModelerColors>()!.success,
        reason: 'a bar within budget reads in the success colour',
      );
    },
  );

  testWidgets(
    '19/16 joints draws its own bar over budget, in the tertiary colour',
    (tester) async {
      await _pump(tester, _report);

      final fill = tester.widget<FractionallySizedBox>(
        find.byKey(fillKey('joints')),
      );
      // Clamped to 1.0 for the bar's own width — a bar cannot draw past its
      // own track — while the colour alone says it is over.
      expect(fill.widthFactor, 1.0);

      final colour = tester.widget<DecoratedBox>(
        find.byKey(fillColourKey('joints')),
      );
      final BoxDecoration decoration = colour.decoration as BoxDecoration;
      final theme = modelerTheme();
      expect(decoration.color, theme.colorScheme.tertiary);
    },
  );

  testWidgets('a bar within budget never reads in the tertiary colour', (
    tester,
  ) async {
    await _pump(tester, _report);

    final colour = tester.widget<DecoratedBox>(
      find.byKey(fillColourKey('influences')),
    );
    final BoxDecoration decoration = colour.decoration as BoxDecoration;
    final theme = modelerTheme();
    expect(decoration.color, isNot(theme.colorScheme.tertiary));
  });
}
