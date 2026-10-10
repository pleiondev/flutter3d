/// Every field of the selected thing, editable, in the components it makes.
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
/// **Grouped into components, and the grouping is only a reading aid.** Where
/// a thing is (`at`, `size`, `yaw`), what it looks like, how it collides,
/// what a light does, and an entity's own properties — the sections a person
/// scans for, rather than one alphabetical column of everything. [components]
/// names the keys each section knows; a key no section names lands in the
/// last one (an entity's properties, or "other"), so the grouping can never
/// hide a field. Every row writes through `SetField` on the history, so every
/// edit is one step of undo named after the field it wrote. An entity can be
/// given a property it does not have yet, and lose one it does, the same way.
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
/// to change its own import. The panel's own title and its "not set" heading
/// are `SectionLabel` too (`ui-27`'s `E2`), each with the `style`/`padding`
/// override that reproduces this panel's own look — the reason those two
/// parameters exist on `SectionLabel` at all.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show MaterialHint;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import 'editor_cubit.dart';

export 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show FieldRow, PathOffers, nothingToOffer;

/// The sections of a [kind]'s inspector and the keys each one knows, in the
/// order they are shown. The last section takes every key none names.
///
/// The editor's own, from `builtInComponents`; with [pieces], a plugin's
/// components for an entity of [type] land before the last.
List<(String, Set<String>)> components(
  Piece kind, {
  String? type,
  EditorPieces? pieces,
}) => <(String, Set<String>)>[
  for (final component in inspectorComponents(kind, type: type, pieces: pieces))
    (component.title, component.fields),
];

/// [keys] sorted into [components] of [kind]: each section with the keys it
/// holds, in order, and sections left empty dropped. `inspectorSections`
/// decides; this is its name in the app.
List<(String, List<String>)> sectionsOf(
  Piece kind,
  Iterable<String> keys, {
  String? type,
  EditorPieces? pieces,
}) => inspectorSections(kind, keys, type: type, pieces: pieces);

final class EditorInspector extends StatelessWidget {
  const EditorInspector({
    super.key,
    required this.state,
    required this.onChanged,
    this.width,
    this.pieces,
  });

  final EditorReady state;

  /// What the installed plugins add: their components, as sections of their
  /// own, with the fields they offer listed under "not set". Null shows the
  /// editor's own sections alone.
  final EditorPieces? pieces;

  /// Called after a field was actually written, so the screen can rebuild and
  /// the scene can be rebuilt from the document.
  final void Function(String what) onChanged;

  /// How wide the panel is, or null to fill what it is given — a docked
  /// side, which the person sizes.
  final double? width;

  static const TextStyle _heading = TextStyle(
    color: Color(0xFF525A66),
    fontSize: 10,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final editing = state.editing;
    final fields = editing.fields;
    final kind = editing.kind;
    if (fields.isEmpty || kind == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Nothing selected — click something in the level or the outliner',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      );
    }

    // **What the document does not say, and could.** A brush is solid and casts
    // a shadow by omission, so the crypt's every wall carries neither key — and
    // a one-way platform or a piece of non-solid decoration is made by adding
    // one. A panel built purely from the row would show three fields and offer
    // no way to reach the two that matter.
    final type = editing.entity?.type;
    final absent = <String, Object?>{
      ...?pieces?.offersFor(kind, fields.keys, type),
      ...editing.offerable,
    };
    final more = absent.keys.toList()..sort();
    final others = editing.selection.length - 1;

    void write(String key, Object? value) {
      // Through the history, like every other change: one row written is one
      // step back, named after the field it wrote. `run` answers what
      // `setField` answers, so a value the format cannot read still rebuilds
      // nothing.
      if (editing.history.run(SetField(key, value))) onChanged(key);
    }

    // An entity's own properties can be taken away; the fields every entity
    // has cannot, and neither can anything of a brush or a light, whose
    // formats decide what they carry.
    final reserved = <String>{
      for (final (_, known) in components(Piece.entity)) ...known,
    };

    return Container(
      width: width,
      // **Nearly opaque, where the palette is translucent.** This is numbers
      // somebody reads exactly and boxes somebody types into, and a coordinate
      // you have to squint at is a coordinate you retype.
      color: const Color(0xF20D0F12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionLabel(
            editing.says,
            style: const TextStyle(
              color: Color(0xFF6F7885),
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          ),
          if (others > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                '$others more selected — the arrows and delete reach all of '
                'them; these fields are the first one\'s',
                key: const ValueKey<String>('inspector.more'),
                style: const TextStyle(color: Color(0xFF8A93A0), fontSize: 11),
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
                  for (final (title, keys) in sectionsOf(
                    kind,
                    fields.keys,
                    type: type,
                    pieces: pieces,
                  )) ...<Widget>[
                    SectionLabel(
                      title,
                      key: ValueKey<String>('component:$title'),
                      style: _heading,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                    ),
                    for (final key in keys)
                      _Removable(
                        key: ValueKey<String>('row:$key'),
                        onRemove:
                            kind == Piece.entity && !reserved.contains(key)
                            ? () => write(key, null)
                            : null,
                        name: key,
                        child: FieldRow(
                          key: ValueKey<String>('field:$key'),
                          name: key,
                          value: fields[key],
                          onWrite: (Object? value) => write(key, value),
                        ),
                      ),
                  ],
                  if (more.isNotEmpty) ...<Widget>[
                    const SectionLabel(
                      'not set',
                      style: _heading,
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
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
                        onWrite: (Object? value) => write(key, value),
                      ),
                  ],
                  if (kind == Piece.entity) _AddProperty(onAdd: write),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row with a button that takes its key out of the document, when it may.
final class _Removable extends StatelessWidget {
  const _Removable({
    super.key,
    required this.name,
    required this.child,
    required this.onRemove,
  });

  final String name;
  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove;
    if (remove == null) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: child),
        IconButton(
          key: ValueKey<String>('remove:$name'),
          tooltip: 'Take $name out of this entity',
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: Color(0xFF6F7885)),
          onPressed: remove,
        ),
      ],
    );
  }
}

/// A name and a value, written into the selected entity as a new property.
///
/// **The value is read as JSON when it is JSON**, so `3` is a number, `true`
/// a flag and `[1, 2, 3]` a list, and as the text typed otherwise — which is
/// what a word like `goblin` was meant to be. The editor knows no game's
/// vocabulary, so it cannot say what a property should be; it can only make
/// sure what is typed arrives as the kind of value it looks like.
final class _AddProperty extends StatefulWidget {
  const _AddProperty({required this.onAdd});

  final void Function(String key, Object? value) onAdd;

  @override
  State<_AddProperty> createState() => _AddPropertyState();
}

class _AddPropertyState extends State<_AddProperty> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _value = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  static Object? _read(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  void _add() {
    final name = _name.text.trim();
    final text = _value.text.trim();
    if (name.isEmpty || text.isEmpty) return;
    widget.onAdd(name, _read(text));
    _name.clear();
    _value.clear();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Color(0xFFE6EAF0), fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const ValueKey<String>('inspector.addName'),
              controller: _name,
              style: style,
              decoration: const InputDecoration(
                hintText: 'new property',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const ValueKey<String>('inspector.addValue'),
              controller: _value,
              style: style,
              decoration: const InputDecoration(
                hintText: 'value',
                isDense: true,
              ),
              onSubmitted: (String _) => _add(),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('inspector.add'),
            tooltip: 'Add this property',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, color: Color(0xFF8A93A0)),
            onPressed: _add,
          ),
        ],
      ),
    );
  }
}
