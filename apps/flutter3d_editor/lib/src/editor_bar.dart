import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'editor_cubit.dart';

/// The strip across the top: which document is open, what is selected, and
/// the last thing that happened.
///
/// A `StatelessWidget` reading straight off an [EditorReady], not a
/// `BlocBuilder` of its own — `_EditorScreenState` already holds the current
/// state at the point it builds this, from the one `BlocBuilder` around the
/// whole screen, and a second subscription here would be a second place to
/// keep in step with the first.
final class EditorBar extends StatelessWidget {
  const EditorBar({
    super.key,
    required this.state,
    this.onFewerLights,
    this.onBehaviours,
    this.onCutscenes,
    this.actions = const <Widget>[],
  });

  final EditorReady state;

  /// Runs the light optimizer; the button is left out when null, and
  /// disabled while the level has no lights to optimise.
  final VoidCallback? onFewerLights;

  /// Opens the level's behaviour trees; the button is left out when null.
  final VoidCallback? onBehaviours;

  /// Opens the level's cutscenes; the button is left out when null.
  final VoidCallback? onCutscenes;

  /// The toolbar's buttons, at the end of the strip.
  ///
  /// **In the strip, not over the level.** They were `Positioned` at hand-
  /// picked offsets from the window's right edge, and one of those offsets
  /// once put the Play button under the step panel's, which took every press.
  /// A row cannot lay one button over another.
  final List<Widget> actions;

  /// Below this width the buttons go on a row of their own. In one row, a
  /// window this narrow left the path and the selection a few letters each.
  static const double oneRow = 1100.0;

  @override
  Widget build(BuildContext context) {
    final editing = state.editing;
    final info = <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${editing.path}${editing.isDirty ? '  — unsaved' : ''}',
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _selection,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: editing.piece == null
                    ? const Color(0xFF9AA4B2)
                    : const Color(0xFF7ED957),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      // Flexible, so a long sentence is cut short rather than pushing the
      // toolbar's buttons off the end of the strip. The whole of it is in
      // the console.
      Flexible(
        child: Text(
          state.said,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFFFB74D)),
        ),
      ),
    ];
    final compact = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    final buttons = <Widget>[
      if (onFewerLights case final VoidCallback run)
        TextButton(
          style: compact,
          onPressed: editing.level.lights.isEmpty ? null : run,
          child: const Text('Fewer lights'),
        ),
      if (onBehaviours case final VoidCallback run)
        TextButton(
          style: compact,
          onPressed: run,
          child: const Text('Behaviours'),
        ),
      if (onCutscenes case final VoidCallback run)
        TextButton(
          style: compact,
          onPressed: run,
          child: const Text('Cutscenes'),
        ),
      if (actions.isNotEmpty) const SizedBox(width: 4),
      ...actions,
    ];
    return Container(
      color: const Color(0xCC0E1013),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE6EAF0), fontSize: 13),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                constraints.maxWidth >= oneRow
                ? Row(children: <Widget>[...info, ...buttons])
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(children: info),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(children: buttons),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// What is selected, for the strip that always says it.
  ///
  /// **Separate from the message**, because the two answer different
  /// questions and one used to overwrite the other: after pressing G the
  /// corner said "off the grid" and the fact that a brush was selected at all
  /// had scrolled away.
  String get _selection {
    final editing = state.editing;
    final at = editing.where;
    if (at == null) return editing.says;
    return '${editing.says} · at ${_meters(at)}'
        '${editing.brush == null ? '' : ' · ${_meters(editing.brush!.size)}'}';
  }

  static String _meters(Vector3 v) =>
      '${v.x.toStringAsFixed(2)}, '
      '${v.y.toStringAsFixed(2)}, ${v.z.toStringAsFixed(2)}';
}
