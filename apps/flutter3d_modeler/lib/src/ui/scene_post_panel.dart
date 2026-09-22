/// `mat-24`'s own post panel: bloom, and the exposure the picture is
/// composited at.
///
/// **Exposure lives on `SceneLighting`, not `ScenePostSettings`** — see
/// `scene_lighting.dart`'s own doc comment for why the row's "пост" is
/// narrower than `RenderSettings`' own `LookSettings`/`BloomSettings` pair —
/// but a person reads it as one thing with bloom, "how the picture looks
/// once everything is lit," so this panel draws both fields together rather
/// than splitting a single mental knob across two panels because of where
/// the document happens to keep it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../../l10n/app_localizations.dart';

/// Bloom, and exposure.
final class ScenePostPanel extends StatelessWidget {
  const ScenePostPanel({
    super.key,
    required this.post,
    required this.exposure,
    required this.onBloomChanged,
    required this.onExposureChanged,
  });

  final ScenePostSettings post;

  /// `SceneLighting.exposure`.
  final double exposure;

  final ValueChanged<bool> onBloomChanged;
  final ValueChanged<double> onExposureChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(AppLocalizations.of(context).scenePostSectionLabel),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.postBloom),
          value: post.bloomEnabled,
          onChanged: onBloomChanged,
        ),
        NumberField(
          label: l.postExposure,
          value: exposure,
          onChanged: onExposureChanged,
        ),
      ],
    );
  }
}
