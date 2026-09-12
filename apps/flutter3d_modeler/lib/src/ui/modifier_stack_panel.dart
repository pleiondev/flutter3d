/// `ui-08`'s own modifier stack: what runs, in what order, on or off.
///
/// **Fields are a later row's own work.** `doc-23`'s `SetModifierField`
/// already exists and `mat-19` is where a control for it lands; what this
/// panel offers today is the stack's own shape — which steps exist, whether
/// each runs, and the order they run in — the three things `ToggleModifier`
/// and `ReorderModifier` already commit to history without a field editor
/// anywhere near them.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// The active object's own stack, empty or not.
///
/// A phase-one project's stack is ordinarily empty — the only modifier this
/// build's own commands can add is `mesh-41`'s mirror — so this draws nothing
/// beyond its own heading when [slots] is empty rather than an empty list
/// with nothing in it to explain why.
final class ModifierStackPanel extends StatelessWidget {
  const ModifierStackPanel({
    super.key,
    required this.slots,
    required this.onToggle,
    required this.onReorder,
  });

  final List<ModifierSlot> slots;

  /// The modifier at [index] had its enabled switch flipped.
  final ValueChanged<int> onToggle;

  /// The modifier at [from] belongs at [to] now.
  final void Function(int from, int to) onReorder;

  static String _labelOf(Modifier modifier) => switch (modifier) {
    ArrayModifier() => 'Array',
    MirrorModifier() => 'Mirror',
    SmoothModifier() => 'Smooth',
    SubdivisionModifier() => 'Subdivision',
    BooleanModifier() => 'Boolean',
  };

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No modifiers',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: slots.length,
      // `onReorderItem`, not the deprecated `onReorder`: its own `toIndex` is
      // already adjusted for the removed item at `fromIndex`, which is what
      // `ReorderModifier` itself expects — an index into the list as it will
      // be once `fromIndex` is gone, not as it is now.
      onReorderItem: onReorder,
      itemBuilder: (BuildContext context, int index) {
        final slot = slots[index];
        return ListTile(
          key: ValueKey<int>(index),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle, size: 18),
          ),
          title: Text(_labelOf(slot.modifier)),
          trailing: Switch(
            value: slot.enabled,
            onChanged: (_) => onToggle(index),
          ),
        );
      },
    );
  }
}
