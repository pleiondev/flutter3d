/// `ui-08`'s own modifier stack: what runs, in what order, on or off.
///
/// **`mat-20`'s own field: an array's own `count`.** The stack's own shape —
/// which steps exist, whether each runs, and the order they run in — is
/// `ToggleModifier`/`ReorderModifier`'s work, committed with no field editor
/// anywhere near them. `count` is the one field `mat-20`'s own acceptance
/// names ("`count` массива — одна `SetModifierField`"), so it is the one
/// this panel draws a control for; a card for every other modifier's own
/// fields (`HintRow` tokens, the `M3` "Дополнительно" section the plan's
/// fuller description asks for) is still later work, the same honest gap
/// `mat-04a-n`'s own file draws around the rest of `mat-04`'s row.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'theme.dart';

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
    required this.onAdd,
    this.onSetField,
  });

  final List<ModifierSlot> slots;

  /// The modifier at [index] had its enabled switch flipped.
  final ValueChanged<int> onToggle;

  /// The modifier at [from] belongs at [to] now.
  final void Function(int from, int to) onReorder;

  /// A field of the modifier at [index] committed — `SetModifierField`'s own
  /// vocabulary (`'count'`, today). Null hides the field control this panel
  /// would otherwise draw, so a caller can still show the stack's own shape
  /// without wiring edits.
  final void Function(int index, String field, Object? value)? onSetField;

  /// The hand-over's own "Add" link at the foot of the stack. Phase one's
  /// own commands can only ever build one kind (`mesh-41`'s mirror), so
  /// there is no picker to offer yet — a real, if currently one-item, choice
  /// point, not a stand-in for one.
  final VoidCallback onAdd;

  static String _labelOf(Modifier modifier) => switch (modifier) {
    ArrayModifier() => 'Array',
    MirrorModifier() => 'Mirror',
    SmoothModifier() => 'Smooth',
    SubdivisionModifier() => 'Subdivision',
    BooleanModifier() => 'Boolean',
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (slots.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'No modifiers',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        )
      else
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: slots.length,
          // `onReorderItem`, not the deprecated `onReorder`: its own
          // `toIndex` is already adjusted for the removed item at
          // `fromIndex`, which is what `ReorderModifier` itself expects — an
          // index into the list as it will be once `fromIndex` is gone, not
          // as it is now.
          onReorderItem: onReorder,
          itemBuilder: (BuildContext context, int index) {
            final slot = slots[index];
            final ArrayModifier? array = onSetField == null
                ? null
                : switch (slot.modifier) {
                    final ArrayModifier m => m,
                    _ => null,
                  };
            return ListTile(
              key: ValueKey<int>(index),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, size: 18),
              ),
              title: Text(_labelOf(slot.modifier)),
              subtitle: array == null
                  ? null
                  : SizedBox(
                      width: 96,
                      child: NumberField(
                        label: 'Count',
                        semanticLabel: 'Array count',
                        value: array.count.toDouble(),
                        onChanged: (double value) =>
                            onSetField!(index, 'count', value.round()),
                      ),
                    ),
              trailing: Switch(
                value: slot.enabled,
                onChanged: (_) => onToggle(index),
              ),
            );
          },
        ),
      TextButton(
        onPressed: onAdd,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, ModelerMetrics.row - 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Add'),
      ),
    ],
  );
}
