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
  String? panoramaName,
  VoidCallback? onChoosePanorama,
  VoidCallback? onClearPanorama,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: modelerTheme(),
    home: Scaffold(
      body: SceneEnvironmentPanel(
        environment: environment,
        ambientIntensity: ambientIntensity,
        onEnvironmentChanged: onEnvironmentChanged ?? (_) {},
        onAmbientChanged: onAmbientChanged ?? (_) {},
        panoramaName: panoramaName,
        onChoosePanorama: onChoosePanorama,
        onClearPanorama: onClearPanorama,
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

    for (final SceneEnvironmentPreset preset in SceneEnvironmentPreset.values) {
      final label = switch (preset) {
        SceneEnvironmentPreset.studio => 'Studio',
        SceneEnvironmentPreset.daylight => 'Daylight',
        SceneEnvironmentPreset.sunset => 'Sunset',
        _ => 'None',
      };
      expect(find.text(label), findsWidgets);
    }
  });

  group('ux-49: the panorama beside the presets', () {
    testWidgets('a platform with no picker shows no row at all', (
      tester,
    ) async {
      await _pump(tester);

      // Mutation: draw the row regardless. A browser then gets a "Choose…"
      // that opens nothing, which is worse than not offering it.
      expect(find.text('Choose…'), findsNothing);
    });

    testWidgets('with a picker and no panorama, it says the preset lights it', (
      tester,
    ) async {
      var chosen = 0;
      await _pump(tester, onChoosePanorama: () => chosen++);

      expect(
        find.text('No panorama — the preset above lights it'),
        findsOneWidget,
      );
      await tester.tap(find.text('Choose…'));
      await tester.pump();
      expect(chosen, 1);
    });

    testWidgets('and with one, it names the picture and offers to clear it', (
      tester,
    ) async {
      var cleared = 0;
      await _pump(
        tester,
        panoramaName: 'overcast-noon.hdr',
        onChoosePanorama: () {},
        onClearPanorama: () => cleared++,
      );

      // **Which of the two is in force.** The dropdown above still shows a
      // preset, and a panorama is what actually lights the scene while
      // there is one — a row that only said "a panorama is set" would leave
      // the preset looking like the answer.
      expect(find.text('overcast-noon.hdr'), findsOneWidget);
      expect(find.text('Replace…'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear the panorama'));
      await tester.pump();
      expect(cleared, 1);
    });
  });
}
