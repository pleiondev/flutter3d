/// One line of the object list: the name, what it is made of, and whether it is
/// selected.
///
/// **The kind is shown, because it decides what the rail can do.** An object
/// that is still a cylinder refuses every mesh command with a sentence about
/// converting it; showing which objects are parametric is what stops that
/// sentence being a surprise.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../theme.dart';

/// One line of the object list: the name, what it is made of, and whether it
/// is selected.
class ObjectRow extends StatelessWidget {
  const ObjectRow({
    super.key,
    required this.object,
    required this.selected,
    required this.onTap,
  });

  final ModelObject object;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `ui-23`'s own pass: the row already showed selection with colour and
    // weight, which a screen reader cannot read. `button: true` names what a
    // tap here does; `MergeSemantics` folds it onto `InkWell`'s own inner
    // node, the one that actually carries the tap action, rather than
    // leaving it on a separate parent node.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: object.name,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: ModelerMetrics.row,
            child: Row(
              children: <Widget>[
                Icon(
                  switch (object.geometry) {
                    ParametricGeometry() => Icons.category_outlined,
                    EditedGeometry() => Icons.hexagon_outlined,
                    ImportedGeometry() => Icons.download_outlined,
                    // A socket carries no geometry at all: it is a place on
                    // the model that something else is attached to, which is
                    // what an anchor says and what no shape glyph would.
                    SocketGeometry() => Icons.anchor_outlined,
                  },
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      object.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
