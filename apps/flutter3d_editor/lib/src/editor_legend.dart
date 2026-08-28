import 'package:flutter/material.dart' hide Material;

import 'editor_cubit.dart';

/// The strip across the bottom: every key this editor answers to.
///
/// **Getting about comes first and never leaves the screen.** It was said
/// once, in the message line, and the first thing anybody does replaced it —
/// so the one thing somebody needs before they can do anything at all was the
/// one thing they could not read.
final class EditorLegend extends StatelessWidget {
  const EditorLegend({super.key, required this.state});

  final EditorReady state;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xCC0E1013),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'W A S D fly · Q E down and up · shift faster · '
          'scroll forward · drag to look · click to select · '
          'fields on the right',
          style: TextStyle(color: Color(0xFFCBD3DD), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          'arrows move · R F raise · 1 2 3 axis (${state.axis.name}) '
          '· − = size or brightness · , . turn '
          '· ⌘D copy · ⌫ delete '
          '· G grid ($_gridSaid) · B lamp (${state.lampOn ? 'on' : 'off'}) '
          '· ⌘Z undo · ⇧⌘Z redo · ⌘S save · ⇧⌘S save a copy',
          style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
        ),
      ],
    ),
  );

  String get _gridSaid {
    final grid = state.editing.grid;
    return grid == 0.0 ? 'off' : '$grid m';
  }
}
