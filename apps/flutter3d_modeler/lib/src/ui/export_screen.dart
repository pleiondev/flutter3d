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

import '../exporting.dart';

/// What the person chose, or null from [showExportScreen] when they backed
/// out without exporting.
final class ExportChoice {
  const ExportChoice({
    required this.format,
    required this.bakeTransforms,
    this.textureEncoding = TextureEncoding.png,
    this.acknowledgedWarnings = false,
  });

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
Future<ExportChoice?> showExportScreen(
  BuildContext context, {
  required ModelProject project,
  required ValueChanged<int> onShow,
}) => showDialog<ExportChoice>(
  context: context,
  builder: (BuildContext context) =>
      _ExportScreen(project: project, onShow: onShow),
);

class _ExportScreen extends StatefulWidget {
  const _ExportScreen({required this.project, required this.onShow});

  final ModelProject project;
  final ValueChanged<int> onShow;

  @override
  State<_ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<_ExportScreen> {
  ExportFormat _format = ExportFormat.glb;
  bool _bakeTransforms = false;
  TextureEncoding _textureEncoding = TextureEncoding.png;

  @override
  Widget build(BuildContext context) {
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
      title: const Text('Export'),
      content: SizedBox(
        width: 420,
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
                    label: Text(format.suffix),
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
            Text('Triangles', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: budget > 0 ? (triangles / budget).clamp(0.0, 1.0) : 0.0,
              color: overBudget ? theme.colorScheme.error : null,
            ),
            const SizedBox(height: 4),
            Text(
              '$triangles of $budget (${widget.project.profile.name})',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Bake node transforms'),
              value: _bakeTransforms,
              onChanged: (bool? to) =>
                  setState(() => _bakeTransforms = to ?? false),
            ),
            // Only `.f3d` ever reads `textureEncoding` — see `TextureEncoding`'s
            // own doc comment — so the toggle disappears rather than sitting
            // there disabled for a format it can never change.
            if (_format == ExportFormat.f3d)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Compress textures (KTX2)'),
                value: _textureEncoding == TextureEncoding.ktx2,
                onChanged: (bool? to) => setState(
                  () => _textureEncoding = (to ?? false)
                      ? TextureEncoding.ktx2
                      : TextureEncoding.png,
                ),
              ),
            const SizedBox(height: 8),
            if (readiness.issues.isEmpty)
              Text('ready to export', style: theme.textTheme.bodySmall)
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final ExportIssue issue in readiness.issues)
                      _IssueRow(issue: issue, onShow: widget.onShow),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
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
                  ),
                ),
          child: Text(
            isEmpty ? 'Nothing to export' : (blocked ? 'Export anyway' : 'Export'),
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
                textStyle: const TextStyle(fontSize: 12),
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
              child: const Text('Show'),
            ),
        ],
      ),
    );
  }
}
