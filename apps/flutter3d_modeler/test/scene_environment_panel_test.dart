/// `mat-24`'s own environment panel: the sky preset and the ambient level.
///
///     flutter test test/scene_environment_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/scene_environment_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  SceneEnvironmentPreset environment = SceneEnvironmentPreset.none,
  double ambientIntensity = 0.3,
  ValueChanged<SceneEnvironmentPreset>? onEnvironmentChanged,
  ValueChanged<double>? onAmbientChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SceneEnvironmentPanel(
        environment: environment,
        ambientIntensity: ambientIntensity,
        onEnvironmentChanged: onEnvironmentChanged ?? (_) {},
        onAmbientChanged: onAmbientChanged ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the current preset and ambient value', (tester) async {
    await _pump(
      tester,
      environment: SceneEnvironmentPreset.daylight,
      ambientIntensity: 0.5,
    );

    expect(find.text('Daylight'), findsOneWidget);
    expect(find.text('0.5'), findsOneWidget);
  });

  testWidgets('picking a different preset reports it', (tester) async {
    final changes = <SceneEnvironmentPreset>[];
    await _pump(
      tester,
      environment: SceneEnvironmentPreset.none,
      onEnvironmentChanged: changes.add,
    );

    await tester.tap(find.byType(DropdownButton<SceneEnvironmentPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunset').last);
    await tester.pumpAndSettle();

    expect(changes, <SceneEnvironmentPreset>[SceneEnvironmentPreset.sunset]);
  });

  testWidgets('editing the ambient field reports the new number', (
    tester,
  ) async {
    final changes = <double>[];
    await _pump(tester, ambientIntensity: 0.3, onAmbientChanged: changes.add);

    await tester.enterText(find.widgetWithText(TextField, '0.3'), '0.8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changes, <double>[0.8]);
  });

  testWidgets('every preset is offered, in the type\'s own order', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byType(DropdownButton<SceneEnvironmentPreset>));
    await tester.pumpAndSettle();

    for (final SceneEnvironmentPreset preset
        in SceneEnvironmentPreset.values) {
      final label = switch (preset) {
        SceneEnvironmentPreset.studio => 'Studio',
        SceneEnvironmentPreset.daylight => 'Daylight',
        SceneEnvironmentPreset.sunset => 'Sunset',
        _ => 'None',
      };
      expect(find.text(label), findsWidgets);
    }
  });
}
