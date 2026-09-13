/// `mat-24`'s own shadows panel: the scene-wide shadow request, and the
/// status line — "Источников N · теневых M из 6" — that reads orange when
/// `lightsDropped`/`shadowsDenied` say the renderer could not keep up.
///
/// The status is computed elsewhere, by `computeSceneStatus`
/// (`scene_mode.dart`) — this widget only draws a [SceneStatus] it is
/// handed, the same split every panel in this app keeps between the pure
/// logic and the widget over it.
library;

import 'package:flutter/material.dart';

import '../scene_mode.dart';
import 'section_label.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Тени'),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Shadows'),
          value: shadows,
          onChanged: onShadowsChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            status.text,
            // `status_line.dart`'s own doc comment already names orange as
            // this app's own warning colour — used here for the identical
            // reason, not picked fresh for this one panel.
            style: theme.textTheme.bodySmall?.copyWith(
              color: status.warning
                  ? Colors.orange
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: status.warning ? FontWeight.bold : null,
            ),
          ),
        ),
      ],
    );
  }
}
