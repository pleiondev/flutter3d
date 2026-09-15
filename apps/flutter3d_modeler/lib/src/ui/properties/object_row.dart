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
    this.unshowable,
  });

  final ModelObject object;
  final bool selected;
  final VoidCallback onTap;

  /// Why this object is in the document but not in the viewport, when it is
  /// — `SceneSync.unshowable`'s own sentence for this id, `ux-02`'s row.
  ///
  /// Null on every ordinary row. **The list is where this belongs as much as
  /// the status line is.** A status line says it once; a person who has
  /// scrolled past it is left with a project whose triangle count includes an
  /// object nothing draws, and no way to tell which one.
  final String? unshowable;

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
        label: unshowable == null
            ? object.name
            : '${object.name}, could not be shown',
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
                if (unshowable case final String says)
                  Tooltip(
                    message: says,
                    child: Icon(
                      Icons.visibility_off_outlined,
                      size: 14,
                      color: theme.colorScheme.tertiary,
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
