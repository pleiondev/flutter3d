/// `mat-24`'s own source panel: the project's own lights, and the fields of
/// whichever one is selected.
///
/// **A dumb widget over `SceneLighting.lights`**, the same shape
/// `ModifierStackPanel` already gives its own stack: every callback names
/// the index of the light it is about, and every command — `AddLight`,
/// `RemoveLight`, `SetLightField` — is the caller's to run, not this
/// widget's. Nothing here reaches into `flutter3d_model_core` for a command;
/// it only reads the values those commands would have already changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../l10n/app_localizations.dart';
import 'theme.dart';

/// The lights, and the selected one's own fields.
final class SceneSourcePanel extends StatelessWidget {
  const SceneSourcePanel({
    super.key,
    required this.lights,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onTypeChanged,
    required this.onIntensityChanged,
    required this.onRangeChanged,
    required this.onShadowChanged,
    required this.onConeChanged,
  });

  final List<ProjectLight> lights;

  /// Which light's own fields are shown below the list, or null when none
  /// is — a fresh panel, or a light that was just removed.
  final int? selected;

  /// The light at this index was tapped in the list.
  final ValueChanged<int> onSelect;

  final VoidCallback onAdd;

  /// The light at this index should be dropped — `RemoveLight`'s own index.
  final ValueChanged<int> onRemove;

  final void Function(int index, ProjectLightType type) onTypeChanged;
  final void Function(int index, double value) onIntensityChanged;
  final void Function(int index, double value) onRangeChanged;
  final void Function(int index, bool value) onShadowChanged;

  /// The outer cone half-angle, in radians — meaningless off a spot light,
  /// and only offered when [selected] names one.
  final void Function(int index, double outerConeAngle) onConeChanged;

  static String _labelOf(ProjectLightType type) => switch (type) {
    ProjectLightType.point => 'Point',
    ProjectLightType.spot => 'Spot',
    // `ProjectLightType` is a value class, not a sealed one — see its own
    // doc comment — so a fourth kind reads as directional here until this
    // switch is taught its name, the same fallback `LightingSync` gives it.
    _ => 'Directional',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int? active =
        selected != null && selected! >= 0 && selected! < lights.length
        ? selected
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(AppLocalizations.of(context).sceneSourcesSectionLabel),
        if (lights.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No lights',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (var i = 0; i < lights.length; i++)
            ListTile(
              key: ValueKey<int>(i),
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: i == active,
              onTap: () => onSelect(i),
              title: Text(_labelOf(lights[i].type)),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Remove',
                onPressed: () => onRemove(i),
              ),
            ),
        TextButton(
          onPressed: onAdd,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: panelButtonMinimum(context),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Add'),
        ),
        if (active != null) ...<Widget>[
          const SectionLabel('Source'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DropdownButton<ProjectLightType>(
              isExpanded: true,
              value: lights[active].type,
              items: <DropdownMenuItem<ProjectLightType>>[
                for (final ProjectLightType type in ProjectLightType.values)
                  DropdownMenuItem<ProjectLightType>(
                    value: type,
                    child: Text(_labelOf(type)),
                  ),
              ],
              onChanged: (ProjectLightType? type) {
                if (type != null) onTypeChanged(active, type);
              },
            ),
          ),
          NumberField(
            label: 'Intensity',
            value: lights[active].intensity,
            onChanged: (double value) => onIntensityChanged(active, value),
          ),
          NumberField(
            label: 'Range',
            value: lights[active].range,
            onChanged: (double value) => onRangeChanged(active, value),
          ),
          if (lights[active].type == ProjectLightType.spot)
            NumberField(
              label: 'Cone',
              value: lights[active].outerConeAngle,
              onChanged: (double value) => onConeChanged(active, value),
            ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Casts shadow'),
            value: lights[active].castsShadow,
            onChanged: (bool value) => onShadowChanged(active, value),
          ),
        ],
      ],
    );
  }
}
