/// What is wrong with the mesh, and the one press that fixes each — `ux-16`.
///
/// **`MeshChecks` has found all of this since `mesh-80n` and nothing showed
/// it.** The status line said "1 vertex where two pieces of surface meet" and
/// the export screen said it again, and neither could say *which* vertex or
/// do anything about it — so the way to find a hole in a model was to orbit
/// until the inside showed through.
///
/// **Each row selects its own elements and offers its own fix.** That is the
/// whole of the row: a count nobody can act on is a count people learn to
/// ignore, and the fix has to be the command the rail already runs so that
/// it lands on the undo stack like everything else.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'theme.dart';

/// The fix a kind of issue calls for — `ux-16`.
///
/// **A rail tool id rather than a command**, so the panel presses the same
/// door the button and the palette press: a triangulate reached from here
/// arms, runs and lands exactly as one reached from the rail, and there is
/// one place that knows what "triangulate" means.
///
/// Null where a kind has no one-press answer: an inverted shell is a
/// recalculate with `flip`, an isolated vertex is a delete of things nothing
/// is drawing, and neither is a thing to do to a mesh without being asked.
String? fixToolFor(MeshIssueKind kind) => switch (kind.name) {
  'n-gon' => 'mesh.triangulate',
  'boundary edge' => 'mesh.fillHoles',
  'duplicate vertex' => 'mesh.merge',
  'inverted shell' => 'mesh.normals',
  _ => null,
};

/// What the button beside a row says.
String fixLabelFor(MeshIssueKind kind) => switch (kind.name) {
  'n-gon' => 'Triangulate',
  'boundary edge' => 'Fill',
  'duplicate vertex' => 'Merge',
  'inverted shell' => 'Recalculate',
  _ => 'Fix',
};

/// The mesh's own health, a row per thing that is wrong.
class MeshHealthPanel extends StatelessWidget {
  const MeshHealthPanel({
    super.key,
    required this.issues,
    required this.onSelect,
    required this.onFix,
  });

  /// `MeshChecks.all()`, worst first — the order that class already sorts in.
  final List<MeshIssue> issues;

  /// Select what this issue names, at the level its kind is about.
  final void Function(ElementLevel level, List<int> ids) onSelect;

  /// Press the rail tool [fixToolFor] names.
  final ValueChanged<String> onFix;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (issues.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Nothing wrong with it',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final MeshIssue issue in issues)
          _Row(issue: issue, onSelect: onSelect, onFix: onFix),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.issue,
    required this.onSelect,
    required this.onFix,
  });

  final MeshIssue issue;
  final void Function(ElementLevel level, List<int> ids) onSelect;
  final ValueChanged<String> onFix;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // The same three levels the status line and the console paint in, for the
    // same reason: an error is the one row somebody has to notice.
    final Color colour = switch (issue.severity) {
      IssueSeverity.error => theme.colorScheme.error,
      IssueSeverity.warning => theme.colorScheme.tertiary,
      IssueSeverity.note => theme.colorScheme.onSurfaceVariant,
    };
    final String? tool = fixToolFor(issue.kind);
    return SizedBox(
      height: rowHeightOf(context),
      child: Row(
        children: <Widget>[
          Expanded(
            // The whole row selects, because the count is the interesting
            // part and "show me" is what a person wants from it first.
            child: MergeSemantics(
              child: Semantics(
                button: true,
                label: '${issue.message}, select them',
                child: InkWell(
                  onTap: () => onSelect(
                    issue.kind.level,
                    <int>[...issue.ids],
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      issue.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colour,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (tool != null)
            TextButton(
              onPressed: () => onFix(tool),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: panelButtonMinimum(context),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.labelSmall,
              ),
              child: Text(fixLabelFor(issue.kind)),
            ),
        ],
      ),
    );
  }
}
