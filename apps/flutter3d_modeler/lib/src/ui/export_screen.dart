/// `ui-17`'s own export screen: a format, every readiness issue with a way
/// to see what it is about, the triangle budget as a bar rather than a
/// number, and the flags that change what gets written.
///
/// **A dialog, not a route.** This is a single-screen application — nothing
/// else here pushes a `Navigator` route for a panel, `ui-13`'s own
/// not-yet-built `lathe_dialog.dart` is described the same way, and a modal
/// keeps the document's own state (the selection a "show" action changes)
/// on the one screen behind it rather than splitting it across two.
///
/// **The issue list shown here is read once, against the project as it
/// stands** — not recomputed against a baked copy when "bake node
/// transforms" is ticked. Baking can only ever collapse a transform into
/// geometry that already existed at that placement; nothing about *this*
/// project's own readiness changes because of where its vertices are
/// written down, and a live re-check on every checkbox toggle would cost a
/// whole project's worth of `ApplyTransform` calls for a preview nobody
/// asked to see move.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../l10n/app_localizations.dart';

/// What the person chose, or null from [showExportScreen] when they backed
/// out without exporting.
final class ExportChoice {
  const ExportChoice({
    required this.format,
    required this.bakeTransforms,
    this.textureEncoding = TextureEncoding.png,
    this.acknowledgedWarnings = false,
    this.selectionOnly = false,
    this.applyModifiers = true,
  });

  /// Write only what is selected, and whatever hangs under it — `ux-18`.
  final bool selectionOnly;

  /// Fold the modifier stacks into the geometry — `ux-18`. On, because that
  /// is what the file has carried since `ux-13`.
  final bool applyModifiers;

  final ExportFormat format;

  /// `ui-17`'s own "запечь трансформации узлов": [bakeAllTransforms] runs
  /// before the write when true.
  final bool bakeTransforms;

  /// `mat-30`'s own "an option de export": [TextureEncoding.ktx2] asks
  /// [planExport] to recompress every texture through `fmt-22`'s own
  /// encoders. Only [ExportFormat.f3d] reads it — see [TextureEncoding]'s own
  /// doc comment for why glTF and OBJ always stay PNG.
  final TextureEncoding textureEncoding;

  /// True when this screen's own Export button already read as "Export
  /// anyway" — the person has already seen every issue in the list above
  /// before pressing it, so the caller should write straight through
  /// (`planExport(force: true)`) rather than asking again with a second
  /// dialog that repeats the same list. Meaningless when the project is
  /// empty: that case never reaches a pressable button at all.
  final bool acknowledgedWarnings;
}

/// Opens `ui-17`'s own export screen over [project]. [onShow] is called with
/// an object's id when a person presses "Show" beside an issue naming it —
/// the caller's job is to select that object, this screen does not touch
/// selection itself.
///
/// [format] is which one the screen opens on — `ux-18`'s own "the Export
/// menu opens this screen with the format preselected". The top bar used to
/// export straight from its own menu, which meant two export paths that could
/// disagree about everything this screen asks; now the menu is a shortcut
/// into here.
///
/// [hasSelection] is whether "selection only" is offerable at all: a checkbox
/// that would write nothing is worse than no checkbox.
Future<ExportChoice?> showExportScreen(
  BuildContext context, {
  required ModelProject project,
  required ValueChanged<int> onShow,
  ExportFormat format = ExportFormat.glb,
  bool hasSelection = false,
}) => showDialog<ExportChoice>(
  context: context,
  builder: (BuildContext context) => _ExportScreen(
    project: project,
    onShow: onShow,
    format: format,
    hasSelection: hasSelection,
  ),
);

class _ExportScreen extends StatefulWidget {
  const _ExportScreen({
    required this.project,
    required this.onShow,
    this.format = ExportFormat.glb,
    this.hasSelection = false,
  });

  final ModelProject project;
  final ValueChanged<int> onShow;
  final ExportFormat format;
  final bool hasSelection;

  @override
  State<_ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<_ExportScreen> {
  late ExportFormat _format = widget.format;
  bool _bakeTransforms = false;
  bool _selectionOnly = false;
  bool _applyModifiers = true;
  TextureEncoding _textureEncoding = TextureEncoding.png;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final readiness = ExportReadiness.check(widget.project);
    final triangles = widget.project.triangleCount;
    final budget = widget.project.profile.maxTriangles;
    final overBudget = budget > 0 && triangles > budget;
    // Mirrors `planExport`'s own two-step refusal exactly: an empty project
    // is refused outright regardless of `force`, and is the ONLY case that
    // is — the row's own "отказ только при пустой геометрии." Anything else
    // `readiness` flags is the soft, force-overridable case, which this
    // screen now represents as a relabeled button rather than a second
    // dialog repeating the same issue list.
    final isEmpty = widget.project.objects.isEmpty;
    final blocked = !isEmpty && !readiness.canExport;

    return AlertDialog(
      title: Text(l.exportTitle),
      // **The whole body scrolls, rather than the issue list alone** —
      // `ux-18`. Explaining each checkbox underneath it costs two lines
      // apiece, which is what turned a dialog that just fitted into one that
      // overflowed its own content box on a short window. A scroll here is
      // the cheap answer: nothing has to be dropped, and a laptop with the
      // keyboard open sees the same screen a desktop does.
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SegmentedButton<ExportFormat>(
                showSelectedIcon: false,
                segments: <ButtonSegment<ExportFormat>>[
                  for (final ExportFormat format in ExportFormat.values)
                    ButtonSegment<ExportFormat>(
                      value: format,
                      label: Text(format.label),
                      tooltip: format.says,
                    ),
                ],
                selected: <ExportFormat>{_format},
                onSelectionChanged: (Set<ExportFormat> picked) => setState(() {
                  _format = picked.first;
                  // A toggle nobody can see any more should not still be "on"
                  // in the answer, even though `planExport` itself ignores it
                  // for every format but `.f3d`.
                  if (_format != ExportFormat.f3d) {
                    _textureEncoding = TextureEncoding.png;
                  }
                }),
              ),
              const SizedBox(height: 12),
              Text(l.exportTriangles, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: budget > 0 ? (triangles / budget).clamp(0.0, 1.0) : 0.0,
                color: overBudget ? theme.colorScheme.error : null,
              ),
              const SizedBox(height: 4),
              Text(
                l.exportOfBudget(
                  triangles,
                  budget,
                  widget.project.profile.name,
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              // **Every checkbox says what it means underneath it** —
              // `ux-18`'s own review finding: "bake node transforms", "apply
              // modifiers" and "compress textures" are three phrases a person
              // who has never used a modeller has no way to guess at, and a
              // tooltip they have to hover to find is a sentence most people
              // never see.
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.exportBakeTransforms),
                subtitle: Text(l.exportBakeTransformsHelp),
                value: _bakeTransforms,
                onChanged: (bool? to) =>
                    setState(() => _bakeTransforms = to ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.exportApplyModifiers),
                subtitle: Text(l.exportApplyModifiersHelp),
                value: _applyModifiers,
                onChanged: (bool? to) =>
                    setState(() => _applyModifiers = to ?? true),
              ),
              if (widget.hasSelection)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.exportSelectionOnly),
                  subtitle: Text(l.exportSelectionOnlyHelp),
                  value: _selectionOnly,
                  onChanged: (bool? to) =>
                      setState(() => _selectionOnly = to ?? false),
                ),
              // Only `.f3d` ever reads `textureEncoding` — see `TextureEncoding`'s
              // own doc comment — so the toggle disappears rather than sitting
              // there disabled for a format it can never change.
              if (_format == ExportFormat.f3d)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.exportCompressTextures),
                  subtitle: Text(l.exportCompressTexturesHelp),
                  value: _textureEncoding == TextureEncoding.ktx2,
                  onChanged: (bool? to) => setState(
                    () => _textureEncoding = (to ?? false)
                        ? TextureEncoding.ktx2
                        : TextureEncoding.png,
                  ),
                ),
              const SizedBox(height: 8),
              if (readiness.issues.isEmpty)
                Text(l.exportReady, style: theme.textTheme.bodySmall)
              else
                // Plain rows now that the scroll is outside them: a
                // `Flexible` `ListView` inside a `SingleChildScrollView` has
                // no bounded height to be flexible within.
                for (final ExportIssue issue in readiness.issues)
                  _IssueRow(issue: issue, onShow: widget.onShow),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  ExportChoice(
                    format: _format,
                    bakeTransforms: _bakeTransforms,
                    textureEncoding: _textureEncoding,
                    acknowledgedWarnings: blocked,
                    selectionOnly: _selectionOnly,
                    applyModifiers: _applyModifiers,
                  ),
                ),
          child: Text(
            isEmpty
                ? l.exportNothing
                : (blocked ? l.exportAnyway : l.exportTitle),
          ),
        ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.onShow});

  final ExportIssue issue;
  final ValueChanged<int> onShow;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colour = issue.severity == ExportSeverity.error
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            issue.severity == ExportSeverity.error
                ? Icons.error_outline
                : Icons.warning_amber_outlined,
            size: 16,
            color: colour,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              issue.message,
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ),
          // Only an issue naming an object has anywhere to go — the budget
          // and material issues are about the project as a whole, and a
          // "Show" button that selected nothing would be a button that lied.
          if (issue.object case final ModelObject object)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                // From the theme's own label role: a fresh `TextStyle`
                // carries no family — see `theme.dart`.
                textStyle: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontSize: 12),
              ),
              // Closes the dialog after selecting, rather than changing the
              // selection behind it where nobody could see it happen — the
              // review's own finding. `bakeTransforms`/`_format` are lost on
              // reopening, the same as `Cancel` already costs; going to fix
              // a flagged object is worth more than a checkbox somebody can
              // tick again in two taps.
              onPressed: () {
                onShow(object.id);
                Navigator.of(context).pop();
              },
              child: Text(l.exportShow),
            ),
        ],
      ),
    );
  }
}
