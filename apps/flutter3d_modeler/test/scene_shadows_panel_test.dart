/// `mat-24`'s own shadows panel: the scene-wide toggle and the status line
/// it draws beside it.
///
///     flutter test test/scene_shadows_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/l10n/app_localizations_en.dart';
import 'package:flutter3d_modeler/src/scene_mode.dart';
import 'package:flutter3d_modeler/src/ui/scene_shadows_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool shadows = false,
  required SceneStatus status,
  ValueChanged<bool>? onShadowsChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SceneShadowsPanel(
        shadows: shadows,
        status: status,
        onShadowsChanged: onShadowsChanged ?? (_) {},
      ),
    ),
  ),
);

/// The words `AppLocalizations.of(context).sceneStatusLabel` would build for
/// [status] under `Locale('en')` — the same locale [_pump] fixes the harness
/// to, so this stays the one place both sides of the comparison could drift.
String _statusText(SceneStatus status) => AppLocalizationsEn().sceneStatusLabel(
  status.lightCount,
  status.shadowedCount,
  status.shadowCap,
);

void main() {
  testWidgets('draws the status text verbatim', (tester) async {
    final status = computeSceneStatus(lights: const <ProjectLight>[]);
    await _pump(tester, status: status);

    expect(find.text(_statusText(status)), findsOneWidget);
  });

  testWidgets('the toggle reflects the shadows flag', (tester) async {
    final status = computeSceneStatus(lights: const <ProjectLight>[]);
    await _pump(tester, shadows: true, status: status);

    final Switch toggle = tester.widget(find.byType(Switch));
    expect(toggle.value, isTrue);
  });

  testWidgets('toggling reports the new value', (tester) async {
    final reported = <bool>[];
    final status = computeSceneStatus(lights: const <ProjectLight>[]);
    await _pump(tester, status: status, onShadowsChanged: reported.add);

    await tester.tap(find.byType(Switch));

    expect(reported, <bool>[true]);
  });

  testWidgets('a warning reads bold, and a clean status does not', (
    tester,
  ) async {
    const clean = SceneStatus(
      lightCount: 1,
      shadowedCount: 1,
      shadowCap: 6,
      warning: false,
    );
    await _pump(tester, status: clean);
    final Text text = tester.widget(find.text(_statusText(clean)));
    expect(text.style?.fontWeight, isNot(FontWeight.bold));

    const warned = SceneStatus(
      lightCount: 9,
      shadowedCount: 6,
      shadowCap: 6,
      warning: true,
    );
    await _pump(tester, status: warned);
    final Text warnedText = tester.widget(find.text(_statusText(warned)));
    // Mutation: draw the same style regardless of `status.warning` — a
    // status line that never changed weight or colour would tell nobody
    // the frame dropped anything.
    expect(warnedText.style?.fontWeight, FontWeight.bold);
    // The design hand-over's own warning colour — `colorScheme.tertiary`,
    // not a hard-coded Material `Colors.orange`.
    expect(warnedText.style?.color, kModelerScheme.tertiary);
    expect(text.style?.color, isNot(kModelerScheme.tertiary));
  });
}
