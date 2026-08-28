import 'package:flutter/material.dart' hide Material;
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
  const EditorBar({super.key, required this.state});

  final EditorReady state;

  @override
  Widget build(BuildContext context) {
    final editing = state.editing;
    return Container(
      color: const Color(0xCC0E1013),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE6EAF0), fontSize: 13),
        child: Row(
          children: <Widget>[
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
            Text(state.said, style: const TextStyle(color: Color(0xFFFFB74D))),
          ],
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
    return '${editing.says} · at ${_metres(at)}'
        '${editing.brush == null ? '' : ' · ${_metres(editing.brush!.size)}'}';
  }

  static String _metres(Vector3 v) =>
      '${v.x.toStringAsFixed(2)}, '
      '${v.y.toStringAsFixed(2)}, ${v.z.toStringAsFixed(2)}';
}
