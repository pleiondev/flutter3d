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
import 'named_button.dart';

/// The project's own sky preset, and its ambient level.
final class SceneEnvironmentPanel extends StatelessWidget {
  const SceneEnvironmentPanel({
    super.key,
    required this.environment,
    required this.ambientIntensity,
    required this.onEnvironmentChanged,
    required this.onAmbientChanged,
    this.panoramaName,
    this.onChoosePanorama,
    this.onClearPanorama,
  });

  final SceneEnvironmentPreset environment;
  final double ambientIntensity;
  final ValueChanged<SceneEnvironmentPreset> onEnvironmentChanged;
  final ValueChanged<double> onAmbientChanged;

  /// What the project's own panorama is called, or null for none — `ux-49`.
  final String? panoramaName;

  /// Opens a picker for a Radiance `.hdr`. Null where there is no filesystem
  /// to pick one from, and the row does not appear at all — a browser has no
  /// path and no `.hdr` to point at.
  final VoidCallback? onChoosePanorama;

  /// Takes the panorama off, so the preset above lights the scene again.
  final VoidCallback? onClearPanorama;

  static String _labelOf(AppLocalizations l, SceneEnvironmentPreset preset) =>
      switch (preset) {
        SceneEnvironmentPreset.studio => l.envStudio,
        SceneEnvironmentPreset.daylight => l.envDaylight,
        SceneEnvironmentPreset.sunset => l.envSunset,
        // A value class, not a sealed one — see its own doc comment — so a
        // fifth preset reads as "None" here until this switch is taught its
        // name.
        _ => l.envNone,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
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
                  child: Text(_labelOf(l, preset)),
                ),
            ],
            onChanged: (SceneEnvironmentPreset? preset) {
              if (preset != null) onEnvironmentChanged(preset);
            },
          ),
        ),
        // `ux-49`: a panorama beside the four presets rather than as a fifth
        // one. **When there is one it is what lights the scene**, and the
        // dropdown above is what a project falls back to when it is cleared —
        // which is why this row says which of the two is in force rather than
        // sitting silently under a preset nobody is looking at.
        if (onChoosePanorama != null) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                const Icon(Icons.panorama_outlined, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    panoramaName ?? 'No panorama — the preset above lights it',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (panoramaName != null && onClearPanorama != null)
                  NamedButton(
                    label: l.envClearPanorama,
                    child: IconButton(
                      tooltip: l.envClearPanorama,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: onClearPanorama,
                    ),
                  ),
                TextButton(
                  onPressed: onChoosePanorama,
                  child: Text(panoramaName == null ? 'Choose…' : 'Replace…'),
                ),
              ],
            ),
          ),
        ],
        NumberField(
          label: l.envAmbient,
          value: ambientIntensity,
          onChanged: onAmbientChanged,
        ),
      ],
    );
  }
}
