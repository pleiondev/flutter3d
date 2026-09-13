/// `ui-16`'s own import screen: the warnings a decoded file carries, its
/// bounds read in whichever unit a person picks, and the three cleanup
/// flags `import_plan.dart` already knows how to turn into real options.
///
/// **A dialog, not a route**, the same call `export_screen.dart` and
/// `ui-13`'s own not-yet-built `lathe_dialog.dart` already make for this
/// single-screen application.
///
/// **What decides lives in `import_plan.dart`, not here.** This widget
/// reads an already-built [ImportPlan] and asks for the two things only a
/// person can supply — the unit and the up axis — plus the three
/// checkboxes; every number and every warning it shows is `ImportPlan`'s
/// own, so `import_plan_test` proves the truth of what this screen only
/// displays.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../import_plan.dart';
import 'theme.dart';

/// What a person chose on the import screen, or null from
/// [showImportScreen] when they backed out.
///
/// **`weld`/`fixNormals`/`triangulate` all gate the same real step**:
/// `BakeToMesh`'s own doc comment names it directly — "building topology
/// for [imported vertex buffers] is an import option rather than a
/// conversion", which is `importMeshData`. Any of the three true builds
/// real `EditMesh` topology via `importMeshData` in place of the file's own
/// raw `MeshData`; `weld` alone decides the epsilon that call uses.
/// Leaving all three off keeps the object as `ImportedGeometry`,
/// byte-for-byte, which is this project's own stated default.
final class ImportChoice {
  const ImportChoice({
    required this.unit,
    required this.upAxis,
    required this.weld,
    required this.fixNormals,
    required this.triangulate,
  });

  final ImportUnit unit;
  final UpAxis upAxis;
  final bool weld;
  final bool fixNormals;
  final bool triangulate;
}

/// Shows the import screen for [document], already decoded, against
/// [profile]. Returns the person's own choice, or null if they cancelled —
/// the caller still holds the document either way, since deciding not to
/// import it yet is not deciding to lose it.
Future<ImportChoice?> showImportScreen(
  BuildContext context, {
  required ModelDocument document,
  required ProjectProfile profile,
}) => showDialog<ImportChoice>(
  context: context,
  builder: (BuildContext context) =>
      _ImportScreen(document: document, profile: profile),
);

class _ImportScreen extends StatefulWidget {
  const _ImportScreen({required this.document, required this.profile});

  final ModelDocument document;
  final ProjectProfile profile;

  @override
  State<_ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<_ImportScreen> {
  ImportUnit _unit = ImportUnit.metres;
  UpAxis _upAxis = UpAxis.y;
  bool _weld = false;
  bool _fixNormals = false;
  bool _triangulate = false;

  ImportPlan get _plan => ImportPlan(
    document: widget.document,
    profile: widget.profile,
    unit: _unit,
    weld: _weld,
    fixNormals: _fixNormals,
    triangulate: _triangulate,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final bounds = plan.scaledBounds;
    final size = bounds.max - bounds.min;

    return AlertDialog(
      title: const Text('Import'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Row('Triangles', '${plan.triangleCount}'),
              _Row(
                'Bounds',
                '${size.x.toStringAsFixed(2)} × '
                    '${size.y.toStringAsFixed(2)} × '
                    '${size.z.toStringAsFixed(2)} m',
              ),
              if (plan.exceedsTriangleBudget)
                _Warning(
                  'Over this project\'s own ${plan.profile.maxTriangles} '
                  'triangle budget.',
                ),
              if (plan.exceedsMobileTriangleBudget &&
                  !plan.exceedsTriangleBudget)
                _Warning(
                  'Over the mobile preset\'s ${ProjectProfile.mobile.maxTriangles} '
                  'triangle budget, even though this project\'s own budget '
                  'allows it.',
                ),
              const SizedBox(height: 12),
              const Text('Unit', style: TextStyle(fontWeight: FontWeight.w500)),
              SegmentedButton<ImportUnit>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<ImportUnit>>[
                  ButtonSegment<ImportUnit>(
                    value: ImportUnit.millimetres,
                    label: Text('mm'),
                  ),
                  ButtonSegment<ImportUnit>(
                    value: ImportUnit.centimetres,
                    label: Text('cm'),
                  ),
                  ButtonSegment<ImportUnit>(
                    value: ImportUnit.metres,
                    label: Text('m'),
                  ),
                ],
                selected: <ImportUnit>{_unit},
                onSelectionChanged: (Set<ImportUnit> picked) =>
                    setState(() => _unit = picked.first),
              ),
              const SizedBox(height: 12),
              const Text(
                'Up axis',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SegmentedButton<UpAxis>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<UpAxis>>[
                  ButtonSegment<UpAxis>(value: UpAxis.y, label: Text('Y')),
                  ButtonSegment<UpAxis>(value: UpAxis.z, label: Text('Z')),
                ],
                selected: <UpAxis>{_upAxis},
                onSelectionChanged: (Set<UpAxis> picked) =>
                    setState(() => _upAxis = picked.first),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Weld coincident vertices'),
                subtitle: const Text(
                  'Builds real mesh topology; leave off to keep the file\'s '
                  'own data exactly as it arrived.',
                ),
                value: _weld,
                onChanged: (bool? to) => setState(() => _weld = to ?? _weld),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Recalculate normals'),
                value: _fixNormals,
                onChanged: (bool? to) =>
                    setState(() => _fixNormals = to ?? _fixNormals),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Triangulate n-gons'),
                value: _triangulate,
                onChanged: (bool? to) =>
                    setState(() => _triangulate = to ?? _triangulate),
              ),
              if (plan.warningCount > 0) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  '${plan.warningCount} warning'
                  '${plan.warningCount == 1 ? '' : 's'}',
                  style: theme.textTheme.titleSmall,
                ),
                for (final String warning in plan.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      warning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ImportChoice(
              unit: _unit,
              upAxis: _upAxis,
              weld: _weld,
              fixNormals: _fixNormals,
              triangulate: _triangulate,
            ),
          ),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ModelerMetrics.row,
    child: Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
    ),
  );
}
