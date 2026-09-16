/// The object list as a tree — `ux-14`.
///
/// **`parent` has been on `ModelObject` since the format's first version and
/// the list drew a flat column anyway.** A rig is forty bones under a root
/// and an imported scene is a dozen nodes under a few groups, and both read
/// as one long alphabetical-by-accident list — so the one thing a person
/// wants from an outliner, "what is under what", was the one thing it could
/// not say.
///
/// **The order is the project's, not sorted.** `ModelProject.objects` is the
/// order things were added in, which is the order the rest of the
/// application already speaks about them in; sorting the outliner would make
/// the list disagree with every id an agent quotes and every index a journal
/// names. Children follow their parent, and that is the only rearranging.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' as m show Material;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../theme.dart';
import 'object_row.dart';

/// How many levels of hierarchy the outliner steps right for before it stops
/// — see the row's own `padding` for what happens without a cap.
///
/// **Six, because a rig is deeper than a scene and both have to fit.** A
/// humanoid runs hips → spine → chest → shoulder → arm → hand → finger and
/// past it; a panel two hundred and fifty pixels wide cannot spend twelve of
/// them per level and still have room for a name.
const int _deepestIndent = 6;

/// One object and how deep it hangs.
typedef OutlinerRow = ({ModelObject object, int depth});

/// [objects] in tree order: every object after its parent, children indented
/// by one.
///
/// **Orphans are kept, at the top level.** An object whose parent is not in
/// the project is a document somebody has edited by hand or a bug this has
/// not found yet; dropping it from the outliner would hide the very object a
/// person needs to reach to fix it. A cycle is bounded the same way
/// [ModelProject.isVisible] bounds its own walk, and for the same reason.
List<OutlinerRow> outlinerRows(List<ModelObject> objects) {
  final Map<int?, List<ModelObject>> under = <int?, List<ModelObject>>{};
  final Set<int> ids = <int>{for (final ModelObject it in objects) it.id};
  for (final ModelObject object in objects) {
    final int? parent = object.parent;
    // An orphan hangs at the top, beside the objects that really are there.
    under
        .putIfAbsent(
          parent != null && ids.contains(parent) ? parent : null,
          () => <ModelObject>[],
        )
        .add(object);
  }
  final out = <OutlinerRow>[];
  final walked = <int>{};
  void descend(int? parent, int depth) {
    for (final ModelObject object in under[parent] ?? const <ModelObject>[]) {
      if (!walked.add(object.id)) continue;
      out.add((object: object, depth: depth));
      descend(object.id, depth + 1);
    }
  }

  descend(null, 0);
  return out;
}

/// What a click on a row asks for — `ux-14`.
enum OutlinerPick {
  /// A bare click: this one and nothing else.
  only,

  /// Shift: everything from the last one picked to this one.
  through,

  /// Control or the command key: this one in or out of what is selected.
  toggle,
}

/// What the modifiers held right now ask a click for — `ux-14`.
///
/// **Read at the click rather than handed down through the widget tree**,
/// the same place `SelectionBoxMode.forModifiers` and `ux-28`'s own
/// `ElementPickIntent` read theirs: a modifier is a fact about the instant
/// the button went down, and carrying it as state would be carrying
/// something that is already stale by the time it arrives.
///
/// Shift wins over control, unlike the box's own rule, and for a different
/// reason: a range is what a person means by shift in every list in every
/// application, and a list is what this is.
OutlinerPick pickFromKeyboard() {
  if (HardwareKeyboard.instance.isShiftPressed) return OutlinerPick.through;
  if (HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed) {
    return OutlinerPick.toggle;
  }
  return OutlinerPick.only;
}

/// What [how] leaves selected, given what was selected and the order the
/// outliner draws them in.
///
/// **Its own function, so a test can ask about a shift-click without a
/// window.** Three modifiers over a list is exactly the arithmetic that is
/// easy to get almost right — the range that goes the wrong way, the toggle
/// that empties the selection, the bare click that drops an anchor nobody
/// can shift from afterwards.
List<int> outlinerSelection({
  required List<int> current,
  required List<OutlinerRow> rows,
  required int id,
  required OutlinerPick how,
  int? anchor,
}) {
  switch (how) {
    case OutlinerPick.only:
      return <int>[id];
    case OutlinerPick.toggle:
      return current.contains(id)
          ? <int>[
              for (final int each in current)
                if (each != id) each,
            ]
          : <int>[...current, id];
    case OutlinerPick.through:
      // From the last one picked, or from whatever is selected when nothing
      // has been picked yet — a shift-click with no anchor at all is a plain
      // click, which is the only answer that is not a guess.
      final int? from = anchor ?? (current.isEmpty ? null : current.last);
      if (from == null) return <int>[id];
      final int a = rows.indexWhere((OutlinerRow it) => it.object.id == from);
      final int b = rows.indexWhere((OutlinerRow it) => it.object.id == id);
      if (a < 0 || b < 0) return <int>[id];
      final int low = a < b ? a : b;
      final int high = a < b ? b : a;
      return <int>[for (var at = low; at <= high; at++) rows[at].object.id];
  }
}

/// The object list, as a tree.
class Outliner extends StatelessWidget {
  const Outliner({
    super.key,
    required this.objects,
    required this.selected,
    required this.onPick,
    required this.onVisible,
    required this.onLocked,
    required this.onRename,
    required this.onReparent,
    this.unshowable = const <int, String>{},
    this.hiddenByParent = const <int>{},
  });

  final List<ModelObject> objects;
  final List<int> selected;

  /// A row was clicked, with whatever modifier was held.
  final void Function(int id, OutlinerPick how) onPick;

  final void Function(int id, bool to) onVisible;
  final void Function(int id, bool to) onLocked;

  /// A row was renamed in place — `ux-14`'s own double-click.
  final void Function(int id, String to) onRename;

  /// A row was dragged onto another, or onto the empty space below the list
  /// (null, meaning the top level).
  final void Function(int id, int? to) onReparent;

  /// `ux-02`'s own sentences, by object id.
  final Map<int, String> unshowable;

  /// The objects a parent is hiding rather than their own flag — drawn
  /// faded, since their own toggle is still on and pressing it would say
  /// nothing.
  final Set<int> hiddenByParent;

  @override
  Widget build(BuildContext context) {
    final List<OutlinerRow> rows = outlinerRows(objects);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final OutlinerRow row in rows)
          _Row(
            key: ValueKey<int>(row.object.id),
            row: row,
            selected: selected.contains(row.object.id),
            hiddenByParent: hiddenByParent.contains(row.object.id),
            unshowable: unshowable[row.object.id],
            onPick: onPick,
            onVisible: onVisible,
            onLocked: onLocked,
            onRename: onRename,
            onReparent: onReparent,
          ),
        // The top level, as somewhere to drop. **A target rather than a
        // gesture**: without it the only way to take an object out of a
        // group would be a menu, and the whole point of dragging one in is
        // that dragging it out is the same movement backwards.
        DragTarget<int>(
          onAcceptWithDetails: (DragTargetDetails<int> it) =>
              onReparent(it.data, null),
          builder:
              (BuildContext context, List<int?> over, List<dynamic> rejected) =>
                  Container(
                    height: rowHeightOf(context),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 8),
                    color: over.isEmpty
                        ? null
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: over.isEmpty
                        ? null
                        : Text(
                            'to the top level',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                  ),
        ),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.row,
    required this.selected,
    required this.hiddenByParent,
    required this.unshowable,
    required this.onPick,
    required this.onVisible,
    required this.onLocked,
    required this.onRename,
    required this.onReparent,
  });

  final OutlinerRow row;
  final bool selected;
  final bool hiddenByParent;
  final String? unshowable;
  final void Function(int id, OutlinerPick how) onPick;
  final void Function(int id, bool to) onVisible;
  final void Function(int id, bool to) onLocked;
  final void Function(int id, String to) onRename;
  final void Function(int id, int? to) onReparent;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  /// The controller for the in-place rename, or null when the row is showing
  /// its name rather than editing it.
  TextEditingController? _editing;

  @override
  void dispose() {
    _editing?.dispose();
    super.dispose();
  }

  void _startRename() => setState(() {
    _editing = TextEditingController(text: widget.row.object.name);
  });

  void _finishRename() {
    final TextEditingController? box = _editing;
    if (box == null) return;
    final String said = box.text.trim();
    setState(() {
      box.dispose();
      _editing = null;
    });
    // An empty name is a person clearing the box rather than asking for an
    // object with no name — the same rule `NameField` already keeps.
    if (said.isEmpty || said == widget.row.object.name) return;
    widget.onRename(widget.row.object.id, said);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ModelObject object = widget.row.object;
    final bool dimmed = !object.visible || widget.hiddenByParent;
    return DragTarget<int>(
      // An object dropped on itself, or on one of its own descendants, is
      // refused by `SetParent` — this refuses it a step earlier so the row
      // does not light up as a target it is going to say no to.
      onWillAcceptWithDetails: (DragTargetDetails<int> it) =>
          it.data != object.id,
      onAcceptWithDetails: (DragTargetDetails<int> it) =>
          widget.onReparent(it.data, object.id),
      builder:
          (BuildContext context, List<int?> over, List<dynamic> rejected) =>
              Draggable<int>(
                data: object.id,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: m.Material(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(object.name, style: theme.textTheme.bodySmall),
                  ),
                ),
                child: ColoredBox(
                  color: over.isEmpty
                      ? Colors.transparent
                      : theme.colorScheme.primaryContainer,
                  child: Padding(
                    // **The indent, which is the whole point of the tree —
                    // and capped, which is the point of this comment.**
                    // Uncapped it is `depth × 12` taken off the front of the
                    // row before anything is drawn, and the two buttons at
                    // the end have fixed widths: a rig ten joints deep spent
                    // the panel on whitespace and pushed the eye and the lock
                    // off the edge. `tutorial_case_screenshots_test.dart`
                    // caught it as a `RenderFlex` overflow on every
                    // screenshot of a character.
                    //
                    // Past [_deepestIndent] the rows stop stepping right. A
                    // tree that deep is already read by its order and its
                    // disclosure, not by counting pixels from the left.
                    padding: EdgeInsets.only(
                      left: math.min(widget.row.depth, _deepestIndent) * 12.0,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _editing == null
                              ? Opacity(
                                  opacity: dimmed ? 0.45 : 1.0,
                                  child: ObjectRow(
                                    object: object,
                                    selected: widget.selected,
                                    onTap: () => widget.onPick(
                                      object.id,
                                      pickFromKeyboard(),
                                    ),
                                    onDoubleTap: _startRename,
                                    unshowable: widget.unshowable,
                                  ),
                                )
                              : SizedBox(
                                  height: rowHeightOf(context),
                                  child: TextField(
                                    controller: _editing,
                                    autofocus: true,
                                    style: theme.textTheme.bodyMedium,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (_) => _finishRename(),
                                    onTapOutside: (_) => _finishRename(),
                                  ),
                                ),
                        ),
                        _Toggle(
                          on: object.visible,
                          // A row a parent is hiding shows the eye as it is —
                          // its own flag — and says so in the tooltip, since
                          // pressing it would change nothing anybody can see.
                          tooltip: widget.hiddenByParent
                              ? 'Hidden by its parent'
                              : (object.visible ? 'Hide' : 'Show'),
                          onIcon: Icons.visibility_outlined,
                          offIcon: Icons.visibility_off_outlined,
                          onPressed: () =>
                              widget.onVisible(object.id, !object.visible),
                        ),
                        _Toggle(
                          on: !object.locked,
                          tooltip: object.locked ? 'Unlock' : 'Lock',
                          onIcon: Icons.lock_open_outlined,
                          offIcon: Icons.lock_outline,
                          onPressed: () =>
                              widget.onLocked(object.id, !object.locked),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}

/// One of the two little buttons at the end of a row.
class _Toggle extends StatelessWidget {
  const _Toggle({
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
    // `ui-23`'s own pass, the same shape the rail keeps: a tooltip alone
    // lands in `SemanticsNode.tooltip` rather than `.label`.
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
