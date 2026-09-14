/// `mat-24`'s own shadows panel: the scene-wide shadow request, and the
/// status line — `sceneStatusLabel`, "N sources, M shadowed of 6" — that
/// reads orange when `lightsDropped`/`shadowsDenied` say the renderer could
/// not keep up.
///
/// The status is computed elsewhere, by `computeSceneStatus`
/// (`scene_mode.dart`) — this widget only draws a [SceneStatus] it is
/// handed, the same split every panel in this app keeps between the pure
/// logic and the widget over it. `SceneStatus` names no string of its own
/// (`ui-22`): the numbers are pure, the words are this widget's, through
/// `AppLocalizations`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import '../../l10n/app_localizations.dart';
import '../scene_mode.dart';

/// The shadow toggle, and the status it drives.
final class SceneShadowsPanel extends StatelessWidget {
  const SceneShadowsPanel({
    super.key,
    required this.shadows,
    required this.status,
    required this.onShadowsChanged,
  });

  /// The project's own `SceneLighting.shadows` — a scene-wide request, not
  /// a promise: see `SceneLighting.shadows`'s own doc comment.
  final bool shadows;

  final SceneStatus status;

  final ValueChanged<bool> onShadowsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(l10n.sceneShadowsSectionLabel),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.sceneShadowsToggleLabel),
          value: shadows,
          onChanged: onShadowsChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            l10n.sceneStatusLabel(
              status.lightCount,
              status.shadowedCount,
              status.shadowCap,
            ),
            // The design hand-over's own warning colour is `tertiary`
            // (`#FFB86B`), not a hard-coded Material orange picked fresh for
            // this one panel — `status_line.dart`'s own doc comment names
            // the same role for the identical reason.
            style: theme.textTheme.bodySmall?.copyWith(
              color: status.warning
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: status.warning ? FontWeight.bold : null,
            ),
          ),
        ),
      ],
    );
  }
}
