/// The level as a tree, every row of it a way to select what it names.
///
/// **The viewport only selects what can be seen and clicked.** A trigger
/// inside a wall, a light behind the camera, the one torch out of six that
/// is mis-named — each needed flying to before it could be picked, and some
/// could not be picked at all. The outliner lists everything the document
/// holds (`outlineOf` in `flutter3d_editor_core` decides how) and selects by
/// the same `Editing.select` the viewport's click ends in, so either one
/// changing the selection shows in the other: the outliner reads the
/// selection off the document every time it is drawn.
///
/// A command- or control-click adds a row to the selection rather than
/// replacing it (`Editing.toggle`), and the arrow keys and Delete then act
/// on all of it. A double-click flies the camera to the row.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

final class Outliner extends StatefulWidget {
  const Outliner({
    super.key,
    required this.editing,
    required this.onSelect,
    this.onFrame,
    this.adding,
  });

  final Editing editing;

  /// A row was clicked: [picked] is the row, and [add] whether it joins the
  /// selection rather than replacing it.
  final void Function(Picked picked, {required bool add}) onSelect;

  /// A row was double-clicked: bring it into view.
  final ValueChanged<Picked>? onFrame;

  /// Whether a click adds to the selection. The command and control keys,
  /// unless a test says otherwise.
  final bool Function()? adding;

  @override
  State<Outliner> createState() => _OutlinerState();
}

class _OutlinerState extends State<Outliner> {
  final TextEditingController _filter = TextEditingController();

  /// Headings somebody folded. By title, so a heading folded stays folded
  /// as the level changes under it.
  final Set<String> _folded = <String>{};

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _adding() =>
      widget.adding?.call() ??
      (HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed);

  /// Whether ⌘ was down when the row was pressed.
  ///
  /// **Read at the press, not at the tap.** A row that also answers a
  /// double-click hears about a single one only once the double-click has
  /// had its chance — a third of a second later — and by then a quick hand
  /// has let go of ⌘. Read then, the second row replaced the first instead
  /// of joining it. State, because the press and the tap are two calls.
  bool _addOnTap = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.editing;
    final groups = outlineOf(editing.level, filter: _filter.text);
    final rows = <Widget>[
      for (final group in groups) ...<Widget>[
        _Heading(
          group: group,
          folded: _folded.contains(group.title),
          onTap: () => setState(() {
            if (!_folded.remove(group.title)) _folded.add(group.title);
          }),
        ),
        if (!_folded.contains(group.title))
          for (final entry in group.entries)
            _Row(
              entry: entry,
              selected: editing.isSelected(entry.kind, entry.index),
              primary:
                  editing.kind == entry.kind && editing.selected == entry.index,
              onTapDown: () => _addOnTap = _adding(),
              onTap: () => widget.onSelect(entry.picked, add: _addOnTap),
              onDoubleTap: widget.onFrame == null
                  ? null
                  : () => widget.onFrame!(entry.picked),
            ),
      ],
    ];
    final count = editing.selection.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: SizedBox(
            height: 28,
            child: TextField(
              key: const ValueKey<String>('outliner.filter'),
              controller: _filter,
              style: TextStyle(color: scheme.onSurface, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Find in the level',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 14),
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: (String _) => setState(() {}),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey<String>('outliner.rows'),
            children: rows,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: Text(
            count > 1
                ? '$count selected · ⌘-click to add or remove'
                : '⌘-click to select more than one · double-click to fly there',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
          ),
        ),
      ],
    );
  }
}

final class _Heading extends StatelessWidget {
  const _Heading({
    required this.group,
    required this.folded,
    required this.onTap,
  });

  final OutlineGroup group;
  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey<String>('outliner.group.${group.title}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 2),
        child: Row(
          children: <Widget>[
            Icon(
              folded ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                group.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${group.entries.length}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

final class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.selected,
    required this.primary,
    required this.onTapDown,
    required this.onTap,
    required this.onDoubleTap,
  });

  final OutlineEntry entry;
  final bool selected;

  /// Whether this is the one the inspector shows.
  final bool primary;
  final VoidCallback onTapDown;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The pointer itself rather than `onTapDown`, which the double-click
    // recogniser holds back for as long as it holds back the tap.
    return Listener(
      onPointerDown: (PointerDownEvent _) => onTapDown(),
      child: _ink(scheme),
    );
  }

  Widget _ink(ColorScheme scheme) {
    return InkWell(
      key: ValueKey<String>('outliner.${entry.kind.name}.${entry.index}'),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        color: selected
            ? scheme.primary.withValues(alpha: primary ? 0.30 : 0.16)
            : null,
        padding: const EdgeInsets.fromLTRB(26, 3, 10, 3),
        child: Row(
          children: <Widget>[
            Icon(
              switch (entry.kind) {
                Piece.brush => Icons.crop_square,
                Piece.light => Icons.lightbulb_outline,
                Piece.entity => Icons.place_outlined,
              },
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (entry.detail.isNotEmpty)
              Flexible(
                child: Text(
                  entry.detail,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
