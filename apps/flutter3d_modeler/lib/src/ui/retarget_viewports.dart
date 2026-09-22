/// Screen 14's own two viewports, side by side: the source rig (mocap
/// skeleton, greyed) on the left, the live target on the right — `anim-18`'s
/// row. `material_studio_dialog.dart` is the precedent for the one piece
/// this needs that the rest of the app never has: a second `ModelerStage`
/// built off the same `Renderer.device` the document's own viewport already
/// uses, rather than a whole second document merged into anything.
///
/// **Picking is off in both.** The source is read-only by construction —
/// nothing here ever edits it, so there is nothing a click on it could mean.
/// The target reuses the very [ModelerStage] the rest of the shell already
/// draws, but this screen shows no object list of its own to pick *into*:
/// which object is being retargeted onto is whatever was already selected
/// before switching into the retarget sub-mode, the same convention the
/// weights and morphs sub-modes already keep for "the held object" with no
/// picker of their own either.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../../l10n/app_localizations.dart';
import '../modeler_viewport.dart';
import '../staging.dart';

/// The source (left) and target (right) viewports, both non-interactive —
/// `overlay: false` on both, since neither has a gizmo, a wireframe or a
/// floor grid to spend a `MeshOverlay` on.
class RetargetViewports extends StatefulWidget {
  const RetargetViewports({
    super.key,
    required this.renderer,
    required this.targetStage,
    required this.source,
  });

  /// The one device every viewport in this application draws through —
  /// `material_studio_dialog.dart`'s own precedent for a second `Scene` on
  /// it.
  final Renderer renderer;

  /// The live document's own stage — read, never rebuilt: [SceneSync] keeps
  /// it in step with the project the same way the shell's own primary
  /// viewport already relies on.
  final ModelerStage targetStage;

  /// The imported file, or null before `retarget.import` has run.
  final RetargetSource? source;

  @override
  State<RetargetViewports> createState() => _RetargetViewportsState();
}

class _RetargetViewportsState extends State<RetargetViewports> {
  ModelerStage? _sourceStage;

  /// Which [RetargetSource] [_sourceStage] was built for — compared by
  /// identity, since a fresh import always hands over a genuinely new
  /// [RetargetSource] and this widget is rebuilt on every tick of the
  /// application's own render loop regardless of whether the source ever
  /// changed.
  RetargetSource? _builtFor;

  @override
  void initState() {
    super.initState();
    _rebuildSourceStageIfNeeded();
  }

  @override
  void didUpdateWidget(RetargetViewports old) {
    super.didUpdateWidget(old);
    _rebuildSourceStageIfNeeded();
  }

  void _rebuildSourceStageIfNeeded() {
    final RetargetSource? source = widget.source;
    if (identical(source, _builtFor)) return;
    _builtFor = source;
    if (source == null) {
      _sourceStage = null;
      return;
    }
    final ModelerStage stage = ModelerStage.fromProject(
      device: widget.renderer.device,
      project: source.project,
    );
    stage.frameSubject();
    _sourceStage = stage;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ModelerStage? sourceStage = _sourceStage;
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: sourceStage == null
              ? Center(
                  child: Text(
                    l.retargetImportSource,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ModelerViewport(
                  renderer: widget.renderer,
                  stage: sourceStage,
                  onFrame: () {},
                  grid: null,
                  overlay: false,
                ),
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: ModelerViewport(
            renderer: widget.renderer,
            stage: widget.targetStage,
            onFrame: () {},
            grid: null,
            overlay: false,
          ),
        ),
      ],
    );
  }
}
