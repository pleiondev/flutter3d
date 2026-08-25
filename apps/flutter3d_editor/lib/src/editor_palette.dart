import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'editor_cubit.dart';
import 'palette_items.dart';

/// What can be put into this level, and what is holding.
///
/// Down the left, always there, and built from the document — so it lists
/// exactly what this level is made of and nothing a different game would
/// have. The count beside each is worth its space: a level with no exit and a
/// level with three are both worth noticing before playing it.
final class EditorPalette extends StatelessWidget {
  const EditorPalette({super.key, required this.state});

  final EditorReady state;

  @override
  Widget build(BuildContext context) {
    final editing = state.editing;
    return Container(
      width: 168,
      color: const Color(0xCC0E1013),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              'PLACE',
              style: TextStyle(
                color: Color(0xFF6F7885),
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // **Scrolls, because a level decides how long this is.** The crypt
          // has nine kinds in it and the platformer's ascent has more than fit
          // on the screen — a plain column overflows and, in Flutter, the
          // rows past the bottom simply do not exist.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final it in paletteOf(editing.level, declared: state.looks.types))
                    PaletteRow(
                      it: it,
                      held: state.placing?.what == it.what,
                      hidden: state.hidden.contains(it.what),
                      // **Alt-click hides the type.** A separate gesture
                      // rather than a second column of buttons: the palette is
                      // a list somebody reads, and a row of eyes down the side
                      // of it is a row of eyes to read past every time.
                      onHide: () => context
                          .read<EditorCubit>()
                          .toggleHidden(it.what, label: it.label),
                      onTap: () {
                        // Tapping what is already held puts it down, which is
                        // the only way out somebody will guess at before they
                        // find Escape.
                        final cubit = context.read<EditorCubit>();
                        cubit.setPlacing(state.placing?.what == it.what ? null : it);
                      },
                    ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              'click a row, then click in the level · esc puts it down\n'
              'alt-click a row to hide that type',
              style: TextStyle(color: Color(0xFF6F7885), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the palette: a swatch, a word, and how many the level has.
final class PaletteRow extends StatelessWidget {
  const PaletteRow({
    super.key,
    required this.it,
    required this.held,
    required this.hidden,
    required this.onTap,
    required this.onHide,
  });

  final Placeable it;

  /// Whether this is what the next click will put down.
  final bool held;

  /// Whether this type is currently not drawn.
  final bool hidden;

  final VoidCallback onTap;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => HardwareKeyboard.instance.isAltPressed ? onHide() : onTap(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: held ? const Color(0x33FFB74D) : null,
          foregroundDecoration: hidden
              ? const BoxDecoration(color: Color(0x99000000))
              : null,
          child: Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    (it.tint.x * 255).round().clamp(0, 255),
                    (it.tint.y * 255).round().clamp(0, 255),
                    (it.tint.z * 255).round().clamp(0, 255),
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  it.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: held
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE6EAF0),
                    fontSize: 12,
                    fontWeight: held ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                '${it.count}',
                style: const TextStyle(color: Color(0xFF6F7885), fontSize: 11),
              ),
            ],
          ),
        ),
      );
}
