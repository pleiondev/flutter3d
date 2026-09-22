/// Mesh mode on something that has no mesh — `ux-16`.
///
/// **An empty viewport reads as a broken window.** Entering mesh mode on a
/// cylinder draws no wireframe, no handles and nothing to click, because
/// there is no topology to draw; the only thing that said so was a refusal
/// in the status line, and only once somebody had pressed a tool. This says
/// it where the missing thing is, and offers the one press that fixes it.
library;

import 'package:flutter/material.dart' as m show Material;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

/// The banner, and the button that makes the mesh.
class NoMeshBanner extends StatelessWidget {
  const NoMeshBanner({
    super.key,
    required this.object,
    required this.onConvert,
    required this.onBuildTopology,
  });

  /// What is selected, or null when nothing is.
  final ModelObject? object;

  /// Presses a rail tool — `object.bake`, for a shape.
  final ValueChanged<String> onConvert;

  /// Builds topology for an imported object, by id.
  final ValueChanged<int> onBuildTopology;

  /// What to say and what to offer, for what is selected.
  ///
  /// **Three different answers, because they are three different
  /// situations.** A shape converts, an import welds, and nothing selected
  /// is not a problem with the document at all — a banner that said "convert
  /// this" over an empty selection would be telling somebody to press a
  /// button that is not there.
  static ({String said, String? button}) says(ModelObject? object) =>
      switch (object?.geometry) {
        null => (said: 'Nothing is selected to edit', button: null),
        ParametricGeometry(:final shape) => (
          said: 'This is still a ${shape.name}',
          button: 'Convert to a mesh (B)',
        ),
        ImportedGeometry() => (
          said: 'This came from a file and has no topology yet',
          button: 'Build topology',
        ),
        SocketGeometry() => (
          said: 'A socket has no shape to edit',
          button: null,
        ),
        EditedGeometry() => (said: '', button: null),
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({String said, String? button}) what = says(object);
    if (what.said.isEmpty) return const SizedBox.shrink();
    return m.Material(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(what.said, style: theme.textTheme.bodySmall),
            if (what.button case final String label) ...<Widget>[
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () {
                  final ModelObject? it = object;
                  if (it == null) return;
                  if (it.geometry is ImportedGeometry) {
                    onBuildTopology(it.id);
                  } else {
                    onConvert('object.bake');
                  }
                },
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelMedium,
                ),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
