/// Every field of the selected thing, editable.
///
/// **Most of the level format was unauthorable in the editor that exists to
/// author it.** The tools could move any of the three kinds, resize a brush,
/// brighten a light and turn an entity — and could not touch a brush's
/// material, `solid`, `castsShadow`, `layer` or `ramp`, a light's colour,
/// range or type, or an entity's properties. Those are the one-way platforms,
/// the non-solid decoration and the per-brush physics surfaces that the level
/// format's own documentation calls its point.
///
/// **Built from the document rather than from a list of fields.** One row per
/// key in `Editing.fields`, typed by the value that is there. That is why
/// there is no case per kind and no case per field, and why the day the format
/// grows a field this panel edits it — including a field this build has never
/// heard of, which `Level`'s write-through carries and which a hand-written
/// inspector would silently drop.
///
/// What it deliberately does not do is replace the gizmos. `at` and `size` are
/// shown because seeing the number matters, and they are also the two things
/// the arrow keys and the handles already move.
///
/// **Typed by the value, unless something can say better.** [FieldRow] asks a
/// [MaterialHint] first and falls back to the value's own type, which is what
/// lets one row serve two panels: the level has no schema and goes on being
/// edited exactly as it was, while a material — which does have one, in
/// `builtInMaterialHints` and in a `.fmat`'s own `hints` — gets a slider where
/// the range is known, a picker where the value is a colour, a file field where
/// it is a path and a list where the choices are finite. See
/// `material_panel.dart`, which is the panel on the other end of that.
///
/// [FieldRow] itself, and the controls it is built from, live in
/// `flutter3d_editor_widgets` (`ui-27`) — shared with `apps/flutter3d_modeler`
/// so the two editors stop keeping their own copies. Re-exported here so
/// nothing that already imports this file for [FieldRow] or [PathOffers] has
/// to change its own import.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' show MaterialHint;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import 'editor_cubit.dart';

export 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show FieldRow, PathOffers, nothingToOffer;

final class EditorInspector extends StatelessWidget {
  const EditorInspector({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final EditorReady state;

  /// Called after a field was actually written, so the screen can rebuild and
  /// the scene can be rebuilt from the document.
  final void Function(String what) onChanged;

  @override
  Widget build(BuildContext context) {
    final editing = state.editing;
    final fields = editing.fields;
    if (fields.isEmpty) return const SizedBox.shrink();

    final keys = fields.keys.toList()..sort();
    // **What the document does not say, and could.** A brush is solid and casts
    // a shadow by omission, so the crypt's every wall carries neither key — and
    // a one-way platform or a piece of non-solid decoration is made by adding
    // one. A panel built purely from the row would show three fields and offer
    // no way to reach the two that matter.
    final absent = editing.offerable;
    final more = absent.keys.toList()..sort();

    return Container(
      width: 232,
      // **Nearly opaque, where the palette is translucent.** Both sit over the
      // level, and the palette is labels somebody glances at while the picture
      // behind it matters. This is numbers somebody reads exactly and boxes
      // somebody types into, over whatever the level happens to be lit like —
      // and a coordinate you have to squint at is a coordinate you retype.
      color: const Color(0xF20D0F12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              editing.says.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6F7885),
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Scrolls for the reason the palette does: how many rows there are is
          // the document's decision, and a column that overflows in Flutter
          // does not draw the rows past the bottom at all.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final key in keys)
                    FieldRow(
                      key: ValueKey<String>('field:$key'),
                      name: key,
                      value: fields[key],
                      // Through the history, like every other change: one row
                      // written is one step back, named after the field it
                      // wrote. `run` answers what `setField` answers, so a
                      // value the format cannot read still rebuilds nothing.
                      onWrite: (Object? value) {
                        if (editing.history.run(SetField(key, value))) {
                          onChanged(key);
                        }
                      },
                    ),
                  if (more.isNotEmpty) ...<Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
                      child: Text(
                        'NOT SET',
                        style: TextStyle(
                          color: Color(0xFF525A66),
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final key in more)
                      FieldRow(
                        key: ValueKey<String>('field:$key'),
                        name: key,
                        value: absent[key],
                        // Dimmed, because what is shown is what the format
                        // would use rather than what the document says — and
                        // the difference matters to somebody reading a diff.
                        faded: true,
                        onWrite: (Object? value) {
                          if (editing.history.run(SetField(key, value))) {
                            onChanged(key);
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
