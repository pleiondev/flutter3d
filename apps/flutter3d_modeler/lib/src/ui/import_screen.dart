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
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../l10n/app_localizations.dart';
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
    this.linkToSource = false,
  });

  final ImportUnit unit;
  final UpAxis upAxis;
  final bool weld;
  final bool fixNormals;
  final bool triangulate;

  /// Keep the file this came from, so it can be read again — `ux-48`.
  ///
  /// **Off by default, because the ordinary import is a copy.** Somebody
  /// pulling in a prop once wants it to stop owing anything to a file that
  /// may not be there tomorrow. A link is for the other case: the mesh being
  /// sculpted in another tool and checked here, where "read it again" is a
  /// thing somebody does ten times an hour.
  final bool linkToSource;
}

/// Shows the import screen for [document], already decoded, against
/// [profile]. Returns the person's own choice, or null if they cancelled —
/// the caller still holds the document either way, since deciding not to
/// import it yet is not deciding to lose it.
Future<ImportChoice?> showImportScreen(
  BuildContext context, {
  required ModelDocument document,
  required ProjectProfile profile,
  String? fileName,
}) => showDialog<ImportChoice>(
  context: context,
  builder: (BuildContext context) =>
      _ImportScreen(document: document, profile: profile, fileName: fileName),
);

/// What a file of this name most likely came out of — `ux-06`'s own
/// defaults by format.
///
/// **A mesh-exchange format has no unit in it, and a scan is in
/// millimetres.** STL carries no unit at all and is what a scanner and a
/// slicer both write, so millimetres is the answer for nearly every one that
/// reaches a modeller; glTF specifies metres and OBJ is unitless but is
/// authored in a package that was set to something. Defaulting everything to
/// metres was one guess applied to all of them, and it is the wrong guess
/// exactly where a person is least able to spot it: an eight-millimetre
/// teapot opened at metre scale is eight metres across, framed from far
/// enough away that it looks ordinary.
ImportUnit unitForFile(String? fileName) {
  final String name = (fileName ?? '').toLowerCase();
  if (name.endsWith('.stl')) return ImportUnit.millimetres;
  return ImportUnit.metres;
}

/// Whether a file of this name is likely to need topology built for it.
///
/// A triangle soup — STL, and most scans however they arrive — has no shared
/// vertices at all, so every mesh command refuses it until something welds
/// it. `ImportPlan`'s own default already said `weld = true`; the screen
/// that overrides it said false, which is the contradiction `ux-06` names.
bool weldForFile(String? fileName) =>
    (fileName ?? '').toLowerCase().endsWith('.stl');

/// A sentence about a size that does not look like a thing, or null when it
/// does — `ux-06`'s own plausibility hint under Bounds.
///
/// [diagonal] is the scaled bounding box's own diagonal, in metres, which is
/// what the unit picked above turns the file's own numbers into.
///
/// **Two thresholds, three orders of magnitude apart, and nothing in
/// between.** Almost everything a person models is between a centimetre and
/// ten metres across, and the two ways to be wrong about a unit are both
/// factors of a thousand: a millimetre file read as metres, and the reverse.
/// So a hint fires only where the answer is off by about that much, which
/// leaves every plausible model — a bolt, a chair, a building — silent. A
/// hint that fired on anything unusual would be a hint people learn to
/// dismiss, which is the same as no hint.
String? plausibilityHintFor(double diagonal) {
  if (diagonal <= 0) return null;
  if (diagonal < 0.005) {
    return 'That is under 5 mm across. If this was authored in millimetres, '
        'the unit above is set too small.';
  }
  if (diagonal > 500) {
    return 'That is over 500 m across. If this was authored in millimetres, '
        'pick mm above.';
  }
  return null;
}

class _ImportScreen extends StatefulWidget {
  const _ImportScreen({
    required this.document,
    required this.profile,
    this.fileName,
  });

  final ModelDocument document;
  final ProjectProfile profile;

  /// What the file was called, for the defaults to read a format off — null
  /// where a caller has no name to give, which falls back to what this
  /// screen always did.
  final String? fileName;

  @override
  State<_ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<_ImportScreen> {
  late ImportUnit _unit = unitForFile(widget.fileName);
  UpAxis _upAxis = UpAxis.y;
  late bool _weld = weldForFile(widget.fileName);
  bool _fixNormals = false;
  bool _triangulate = false;
  bool _linkToSource = false;

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
    final AppLocalizations l = AppLocalizations.of(context);
    final plan = _plan;
    final bounds = plan.scaledBounds;
    final size = bounds.max - bounds.min;

    return AlertDialog(
      title: Text(l.importTitle),
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
              if (plausibilityHintFor(size.length) case final String hint)
                _Warning(hint),
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
              Text(
                l.importUnit,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
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
              Text(
                l.importUpAxis,
                style: const TextStyle(fontWeight: FontWeight.w500),
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
                title: Text(l.importWeld),
                subtitle: Text(l.importWeldHelp),
                value: _weld,
                onChanged: (bool? to) => setState(() => _weld = to ?? _weld),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.importRecalculateNormals),
                value: _fixNormals,
                onChanged: (bool? to) =>
                    setState(() => _fixNormals = to ?? _fixNormals),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.importTriangulate),
                value: _triangulate,
                onChanged: (bool? to) =>
                    setState(() => _triangulate = to ?? _triangulate),
              ),
              // `ux-48`. Only where there is a path to keep: a file dropped
              // into a browser arrives as bytes and a name, and a link with
              // nowhere to point is a button that fails later rather than
              // now.
              if (widget.fileName != null)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.importLinkToSource),
                  subtitle: Text(l.importLinkToSourceHelp),
                  value: _linkToSource,
                  onChanged: (bool? to) =>
                      setState(() => _linkToSource = to ?? _linkToSource),
                ),
              if (plan.warningCount > 0) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  l.importWarnings(plan.warningCount),
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
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ImportChoice(
              unit: _unit,
              upAxis: _upAxis,
              weld: _weld,
              fixNormals: _fixNormals,
              triangulate: _triangulate,
              linkToSource: _linkToSource,
            ),
          ),
          child: Text(l.importTitle),
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
