/// `mat-24`'s own environment panel: which built-in sky, and how much flat
/// ambient sits under it.
///
/// A dumb widget, the same shape as every other panel in this app: it draws
/// [environment] and [ambientIntensity] and reports a change through a
/// callback, and running `SetEnvironment` or `SetSceneLightingField` against
/// the change is the caller's job.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../l10n/app_localizations.dart';

/// The project's own sky preset, and its ambient level.
final class SceneEnvironmentPanel extends StatelessWidget {
  const SceneEnvironmentPanel({
    super.key,
    required this.environment,
    required this.ambientIntensity,
    required this.onEnvironmentChanged,
    required this.onAmbientChanged,
  });

  final SceneEnvironmentPreset environment;
  final double ambientIntensity;
  final ValueChanged<SceneEnvironmentPreset> onEnvironmentChanged;
  final ValueChanged<double> onAmbientChanged;

  static String _labelOf(SceneEnvironmentPreset preset) => switch (preset) {
    SceneEnvironmentPreset.studio => 'Studio',
    SceneEnvironmentPreset.daylight => 'Daylight',
    SceneEnvironmentPreset.sunset => 'Sunset',
    // A value class, not a sealed one — see its own doc comment — so a
    // fifth preset reads as "None" here until this switch is taught its
    // name.
    _ => 'None',
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SectionLabel(AppLocalizations.of(context).sceneEnvironmentSectionLabel),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DropdownButton<SceneEnvironmentPreset>(
          isExpanded: true,
          value: environment,
          items: <DropdownMenuItem<SceneEnvironmentPreset>>[
            for (final SceneEnvironmentPreset preset
                in SceneEnvironmentPreset.values)
              DropdownMenuItem<SceneEnvironmentPreset>(
                value: preset,
                child: Text(_labelOf(preset)),
              ),
          ],
          onChanged: (SceneEnvironmentPreset? preset) {
            if (preset != null) onEnvironmentChanged(preset);
          },
        ),
      ),
      NumberField(
        label: 'Ambient',
        value: ambientIntensity,
        onChanged: onAmbientChanged,
      ),
    ],
  );
}
