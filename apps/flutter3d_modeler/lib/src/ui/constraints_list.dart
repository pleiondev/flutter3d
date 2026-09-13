/// `anim-07`'s own `ConstraintsList`: [ProjectSkeleton.constraints], the way
/// `anim-15`'s row already models them — a two-bone [IkConstraint] per
/// entry, root → mid → effector. Thin on purpose: a skeleton's own
/// constraint list is empty for almost every rig, the same "ordinary case"
/// [ProjectSkeleton.constraints]'s own doc comment states, and this panel
/// does not invent a bigger concept than the one the model already carries.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'theme.dart';

/// One row per [IkConstraint] in [constraints]. Tapping a row reports its
/// index through [onSelect]; [onRemove], when given, adds a trailing delete
/// action per row — left off entirely, rather than disabled, when a caller
/// has nothing to wire it to yet.
class ConstraintsList extends StatelessWidget {
  const ConstraintsList({
    super.key,
    required this.constraints,
    this.nameOf,
    this.selected,
    required this.onSelect,
    this.onRemove,
  });

  final List<IkConstraint> constraints;

  /// A joint id's own display name — [ModelObject.name] wherever a caller
  /// has objects to read it from. Falls back to the bare id.
  final String Function(int jointId)? nameOf;

  final int? selected;

  final ValueChanged<int> onSelect;

  final ValueChanged<int>? onRemove;

  String _jointLabel(int jointId) => nameOf?.call(jointId) ?? '$jointId';

  @override
  Widget build(BuildContext context) {
    if (constraints.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No constraints',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: constraints.length,
      itemBuilder: (BuildContext context, int index) {
        final constraint = constraints[index];
        return ListTile(
          dense: true,
          selected: index == selected,
          selectedTileColor: kModelerScheme.primaryContainer,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${_jointLabel(constraint.rootJointId)} → '
            '${_jointLabel(constraint.midJointId)} → '
            '${_jointLabel(constraint.effectorJointId)}',
            overflow: TextOverflow.ellipsis,
          ),
          trailing: onRemove == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => onRemove!(index),
                ),
          onTap: () => onSelect(index),
        );
      },
    );
  }
}
