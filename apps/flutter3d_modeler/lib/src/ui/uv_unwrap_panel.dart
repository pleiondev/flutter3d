/// `pro-uv-07`'s own method/margin/list panel.
///
/// **Dumb and callback-driven, the same shape `ModifierStackPanel` already
/// gives a stack of steps** (`modifier_stack_panel.dart`'s own doc comment):
/// this file decides nothing about what a method or a margin means to the
/// document, only how the choice is laid out, and hands every change
/// straight back to whoever is holding the real `UnwrapCommand`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../l10n/app_localizations.dart';
import '../uv_unwrap_layout.dart';

/// The unwrap's own method, margin and island list, in one panel.
final class UvUnwrapPanel extends StatelessWidget {
  const UvUnwrapPanel({
    super.key,
    required this.methods,
    required this.method,
    required this.onMethodChanged,
    required this.margin,
    required this.onMarginChanged,
    required this.islands,
    this.selectedIslandId,
    this.onIslandSelected,
    this.autoPack,
    this.onAutoPackChanged,
    this.onUnwrap,
    this.unwrapRefusal,
  });

  /// Every method this build knows how to run — [UnwrapMethod.lscm] alone
  /// today. A list rather than a hard-coded segment for the same reason
  /// `UnwrapMethod` is a value class and not an enum: a second method later
  /// is another entry a caller hands over, not a change to this file.
  final List<UnwrapMethod> methods;

  final UnwrapMethod method;
  final ValueChanged<UnwrapMethod> onMethodChanged;

  /// [UnwrapCommand.margin]'s own units: the gap the packed `[0, 1]` square's
  /// own islands leave each other.
  final double margin;
  final ValueChanged<double> onMarginChanged;

  /// The unwrap's own islands, in the same order [UvLayoutView] draws them.
  final List<UvIslandData> islands;

  final int? selectedIslandId;

  /// A row in the list was tapped. Null leaves the list unselectable, the
  /// same convention [UvLayoutView.onTriangleTap] uses for its own tap.
  final ValueChanged<int>? onIslandSelected;

  /// [UnwrapCommand.autoPack] — screen 06's own "pack automatically" tick.
  /// Both this and [onAutoPackChanged] left null hides the row, which is what
  /// a caller with nowhere to keep the answer wants instead of a tick that
  /// does not stay ticked.
  final bool? autoPack;
  final ValueChanged<bool>? onAutoPackChanged;

  /// The Unwrap button under the three settings it reads. Null hides it: the
  /// rail's own `uv.unwrap` runs the same command, and this is here for the
  /// shells that have no rail on screen while the panel is — a tablet's own
  /// sheet covers it.
  final VoidCallback? onUnwrap;

  /// Why [onUnwrap] cannot run, or null. Shown under a disabled button, the
  /// bargain `BakePanel.refusal` already makes: a button that refuses after
  /// the press teaches nothing about what to fix first.
  final String? unwrapRefusal;

  static String _labelOf(UnwrapMethod method) =>
      method == UnwrapMethod.lscm ? 'LSCM' : method.name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(l.uvMethod),
        SegmentedButton<UnwrapMethod>(
          segments: <ButtonSegment<UnwrapMethod>>[
            for (final option in methods)
              ButtonSegment<UnwrapMethod>(
                value: option,
                label: Text(_labelOf(option)),
              ),
          ],
          selected: <UnwrapMethod>{method},
          showSelectedIcon: false,
          onSelectionChanged: (Set<UnwrapMethod> selection) =>
              onMethodChanged(selection.first),
        ),
        SectionLabel(l.uvMargin),
        NumberField(
          label: l.uvMargin,
          value: margin,
          onChanged: onMarginChanged,
        ),
        if (autoPack != null && onAutoPackChanged != null)
          CheckboxListTile(
            key: const ValueKey<String>('uvAutoPack'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l.uvAutoPack, style: theme.textTheme.bodySmall),
            value: autoPack,
            onChanged: (bool? on) => onAutoPackChanged!(on ?? false),
          ),
        if (onUnwrap != null) ...<Widget>[
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('uvUnwrap'),
            onPressed: unwrapRefusal == null ? onUnwrap : null,
            icon: const Icon(Icons.unfold_more_outlined),
            label: Text(l.uvUnwrap),
          ),
          if (unwrapRefusal != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                unwrapRefusal!,
                key: const ValueKey<String>('uvUnwrapRefusal'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
        SectionLabel(l.uvIslands),
        if (islands.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l.uvNoIslands,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final island in islands)
            _IslandRow(
              island: island,
              selected: island.id == selectedIslandId,
              onTap: onIslandSelected == null
                  ? null
                  : () => onIslandSelected!(island.id),
            ),
      ],
    );
  }
}

/// One island's own row: its swatch, its id and how stretched it reads.
final class _IslandRow extends StatelessWidget {
  const _IslandRow({required this.island, required this.selected, this.onTap});

  final UvIslandData island;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey<int>(island.id),
    dense: true,
    contentPadding: EdgeInsets.zero,
    selected: selected,
    onTap: onTap,
    leading: DecoratedBox(
      decoration: BoxDecoration(
        color: island.color,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: const SizedBox(width: 16, height: 16),
    ),
    title: Text(AppLocalizations.of(context).uvIsland(island.id)),
    trailing: Text(island.stretch.toStringAsFixed(2)),
  );
}
