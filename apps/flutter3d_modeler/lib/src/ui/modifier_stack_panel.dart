/// The modifier stack: what runs, in what order, on or off — and, since
/// `ux-13`, every field each one has.
///
/// **`mat-20` drew one field and said so.** `count` was the one field that
/// row's acceptance named, and the panel's own comment called the rest
/// honest later work; `hintsForModifier` has named every field of every kind
/// since `mesh-40`, so "later" meant that an array's offset, a mirror's
/// whole four, a subdivision's two levels and a boolean's operation were in
/// the document, editable over MCP, and unreachable from the panel that
/// shows the stack. [ModifierFields] draws them all now, from the hints.
///
/// **Two switches, not one — `ux-13`.** The eye is the viewport and the box
/// is the file: a subdivision at four levels is what the model is for and is
/// not what anybody wants while they work, and a cage a boolean cuts with
/// has to be drawn and must not reach the GLB.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4, Vector3;

import '../../l10n/app_localizations.dart';
import 'modifier_fields.dart';
import 'theme.dart';

/// Every kind this build can add, with a starting value for each — `ux-13`.
///
/// **Values rather than a list of names, so the picker cannot offer a kind
/// nothing can build.** The alternative is a menu of five strings and a
/// switch somewhere else that turns four of them into a modifier and the
/// fifth into nothing.
///
/// A boolean needs an operand and there is no sensible default one, so it is
/// built against [operandId] — the other selected object, when there is one.
/// With none it is left out of the picker rather than offered and refused.
List<({String label, Modifier modifier})> addableModifiers(
  AppLocalizations l, {
  int? operandId,
}) => <({String label, Modifier modifier})>[
  (
    label: l.modifierMirror,
    modifier: MirrorModifier(normal: vm.Vector3(1, 0, 0)),
  ),
  (
    label: l.modifierArray,
    modifier: ArrayModifier(count: 3, offset: vm.Vector3(1, 0, 0)),
  ),
  (label: l.modifierSmooth, modifier: const SmoothModifier(iterations: 2)),
  (
    label: l.modifierSubdivision,
    modifier: const SubdivisionModifier(levels: 1),
  ),
  if (operandId != null)
    (
      label: l.modifierBoolean,
      // Subtract, because that is what a boolean is reached for: the
      // other two are the same gesture with a different sign and the
      // menu's own field changes it in one press.
      modifier: BooleanModifier(
        operation: CsgOperation.subtract,
        operandId: operandId,
        operandTransform: vm.Matrix4.identity(),
      ),
    ),
];

/// The active object's own stack, empty or not.
final class ModifierStackPanel extends StatelessWidget {
  const ModifierStackPanel({
    super.key,
    required this.slots,
    required this.onToggle,
    required this.onReorder,
    required this.onAdd,
    this.onSetField,
    this.onToggleExport,
    this.onRemove,
    this.operandId,
    this.trianglesIn,
    this.trianglesOut,
  });

  final List<ModifierSlot> slots;

  /// The modifier at [index] had its viewport switch flipped.
  final ValueChanged<int> onToggle;

  /// The modifier at [index] had its export switch flipped — `ux-13`. Null
  /// draws no export switch, for a caller with no command to run.
  final ValueChanged<int>? onToggleExport;

  /// The modifier at [index] was dropped from the stack.
  final ValueChanged<int>? onRemove;

  /// The modifier at [from] belongs at [to] now.
  final void Function(int from, int to) onReorder;

  /// A field of the modifier at [index] committed — `SetModifierField`'s own
  /// vocabulary. Null hides the field controls this panel would otherwise
  /// draw, so a caller can still show the stack's own shape without wiring
  /// edits.
  final void Function(int index, String field, Object? value)? onSetField;

  /// The "Add" menu's own choice — `ux-13`. What used to be a link that
  /// silently added a mirror is a menu of every kind this build can make.
  final ValueChanged<Modifier> onAdd;

  /// Another selected object, for a boolean to cut with. Null leaves Boolean
  /// out of the menu rather than offering one nothing can build.
  final int? operandId;

  /// `ux-13`'s own counter: the triangles the object's own geometry has, and
  /// the triangles the stack leaves. Both null hides the line — a caller
  /// with no evaluator behind it, and every object with no stack.
  final int? trianglesIn;
  final int? trianglesOut;

  static String _labelOf(Modifier modifier) => switch (modifier) {
    ArrayModifier() => 'Array',
    MirrorModifier() => 'Mirror',
    SmoothModifier() => 'Smooth',
    SubdivisionModifier() => 'Subdivision',
    BooleanModifier() => 'Boolean',
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l.modifierNone,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
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
            itemBuilder: (BuildContext context, int index) =>
                _slot(context, theme, index),
          ),
        // `ux-13`: what the stack costs, in the one number a person budgets
        // in. Under the list rather than per slot — the interesting figure
        // is what comes out of the whole stack, and a per-slot count would
        // mean folding the stack once per slot to find out.
        if ((trianglesIn, trianglesOut) case (
          final int before,
          final int after,
        ))
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              l.modifierTriangles(before, after),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        // A menu rather than a link — `ux-13`. What was here added a mirror
        // on the X axis without asking, which is one of five kinds and was
        // never the one anybody meant more than a fifth of the time.
        PopupMenuButton<Modifier>(
          tooltip: l.modifierAdd,
          onSelected: onAdd,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<Modifier>>[
            for (final ({String label, Modifier modifier}) each
                in addableModifiers(l, operandId: operandId))
              PopupMenuItem<Modifier>(
                value: each.modifier,
                child: Text(each.label),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              l.modifierAddShort,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _slot(BuildContext context, ThemeData theme, int index) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ModifierSlot slot = slots[index];
    return Padding(
      key: ValueKey<int>(index),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, size: 18),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _labelOf(slot.modifier),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              _StackToggle(
                on: slot.enabled,
                tooltip: slot.enabled
                    ? 'Do not show it in the viewport'
                    : 'Show it in the viewport',
                onIcon: Icons.visibility_outlined,
                offIcon: Icons.visibility_off_outlined,
                onPressed: () => onToggle(index),
              ),
              if (onToggleExport case final ValueChanged<int> toggle)
                _StackToggle(
                  on: slot.inExport,
                  tooltip: slot.inExport
                      ? 'Leave it out of the export'
                      : 'Put it in the export',
                  onIcon: Icons.save_alt_outlined,
                  offIcon: Icons.block_outlined,
                  onPressed: () => toggle(index),
                ),
              if (onRemove case final ValueChanged<int> remove)
                _StackToggle(
                  on: true,
                  tooltip: l.modifierRemove,
                  onIcon: Icons.close,
                  offIcon: Icons.close,
                  onPressed: () => remove(index),
                ),
            ],
          ),
          if (onSetField case final void Function(int, String, Object?) set)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: ModifierFields(
                modifier: slot.modifier,
                onSet: (String field, Object? value) =>
                    set(index, field, value),
              ),
            ),
        ],
      ),
    );
  }
}

/// One of the little buttons at the end of a stack row.
class _StackToggle extends StatelessWidget {
  const _StackToggle({
    required this.on,
    required this.tooltip,
    required this.onIcon,
    required this.offIcon,
    required this.onPressed,
  });

  final bool on;
  final String tooltip;
  final IconData onIcon;
  final IconData offIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // `ui-23`'s own pass, the same shape the rail and the outliner keep.
    return MergeSemantics(
      child: Semantics(
        label: tooltip,
        button: true,
        child: IconButton(
          tooltip: tooltip,
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints.tightFor(
            width: rowHeightOf(context) - 8,
            height: rowHeightOf(context) - 8,
          ),
          padding: EdgeInsets.zero,
          icon: Icon(
            on ? onIcon : offIcon,
            color: on
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.primary,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
