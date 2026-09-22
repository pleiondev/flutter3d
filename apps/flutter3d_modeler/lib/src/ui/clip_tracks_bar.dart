/// Screen 14's own bottom slot: the blend slider that previews a crossfade
/// from whatever the target is already playing onto the just-applied
/// retargeted clip — `anim-18`'s row, `ui/clip_tracks_bar.dart` in the
/// plan's own words, `ModelerMetrics.retargetTracksBar` (22) tall.
///
/// **Drives `TimelinePreviewWiring.crossFadeTo`, not a value on the
/// document.** How long a preview crossfade takes is not a fact `PoseJoint`
/// or any other command would ever need to undo — the same reason the
/// weights sub-mode's own brush radius and strength are plain fields on
/// `_ModelerScreenState` rather than something [onPreview] and its sibling
/// callbacks route through [ModelHistory].
library;

import 'package:flutter/material.dart' hide Material;

import '../../../l10n/app_localizations.dart';

/// A clip's own name, the blend-duration slider, and a "Preview" button —
/// one row, 22 logical pixels tall.
class ClipTracksBar extends StatelessWidget {
  const ClipTracksBar({
    super.key,
    required this.clipName,
    required this.blendSeconds,
    required this.onBlendChanged,
    required this.onPreview,
  });

  /// The retargeted clip's own name, once one has actually landed — null
  /// disables the row rather than drawing a slider for nothing to preview.
  final String? clipName;

  /// The crossfade's own duration, in seconds — `TimelinePlayback.
  /// crossFadeTo`'s own `duration` argument.
  final double blendSeconds;
  final ValueChanged<double> onBlendChanged;

  /// "Preview" was pressed — null when [clipName] is null, the same
  /// disabled state the row's own controls already show.
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = clipName != null;
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              clipName ?? 'No retargeted clip yet',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: enabled ? null : FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(l.clipBlend, style: theme.textTheme.bodySmall),
          Expanded(
            flex: 3,
            child: Slider(
              value: blendSeconds.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              onChanged: enabled ? onBlendChanged : null,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${blendSeconds.toStringAsFixed(2)}s',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onPreview, child: Text(l.clipPreview)),
        ],
      ),
    );
  }
}
