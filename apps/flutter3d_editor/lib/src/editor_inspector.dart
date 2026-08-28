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
library;

import 'package:flutter/material.dart' hide Material;

import 'editor_cubit.dart';

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
                    _FieldRow(
                      key: ValueKey<String>('field:$key'),
                      name: key,
                      value: fields[key],
                      onWrite: (Object? value) {
                        if (editing.setField(key, value)) onChanged(key);
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
                      _FieldRow(
                        key: ValueKey<String>('field:$key'),
                        name: key,
                        value: absent[key],
                        // Dimmed, because what is shown is what the format
                        // would use rather than what the document says — and
                        // the difference matters to somebody reading a diff.
                        faded: true,
                        onWrite: (Object? value) {
                          if (editing.setField(key, value)) onChanged(key);
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

/// One field: its name, and whatever editor its current value calls for.
final class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.name,
    required this.value,
    required this.onWrite,
    this.faded = false,
  });

  final String name;
  final Object? value;
  final void Function(Object? value) onWrite;

  /// Whether this row shows what the format would use rather than what the
  /// document says. Writing it is what puts the key in the document.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final editor = switch (value) {
      final bool it => _BoolField(value: it, onWrite: onWrite),
      final num it => _TextField(
        text: _numberText(it),
        onWrite: (String text) {
          final parsed = num.tryParse(text);
          if (parsed != null) onWrite(parsed);
        },
      ),
      // **Emptying a text field removes the key.** `surface`, a light's `name`
      // and an entity's are all "not set" by being absent, and writing `""`
      // instead gives a brush a surface called nothing — a value the format
      // reads happily and no game means. Clearing a box is how a person says
      // "no value", so it is what it does.
      final String it => _TextField(
        text: it,
        onWrite: (String text) => onWrite(text.isEmpty ? null : text),
      ),
      // A list of numbers is a position, a size, a colour or a direction, and
      // all four are worth seeing and worth typing exactly — a colour picked by
      // eye is a colour nobody can reproduce from the document.
      final List<Object?> it when it.every((Object? e) => e is num) =>
        _NumbersField(
          values: it.cast<num>(),
          onWrite: (List<num> next) => onWrite(next),
        ),
      // Anything else — a nested object, a mixed list — has no honest editor
      // here. Shown, so nobody thinks the field is missing, and not editable,
      // because a text box over a structure is a way to write a document that
      // will not load.
      _ => _ReadOnly(text: '$value'),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            name,
            style: TextStyle(
              color: faded ? const Color(0xFF5E6672) : const Color(0xFF8A93A0),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          editor,
        ],
      ),
    );
  }

  /// Whole numbers without a trailing `.0`, which is what the generators write
  /// and what a diff of one of these documents should stay readable as.
  static String _numberText(num it) =>
      it is int || it == it.roundToDouble() ? '${it.toInt()}' : '$it';
}

final class _BoolField extends StatelessWidget {
  const _BoolField({required this.value, required this.onWrite});

  final bool value;
  final void Function(Object? value) onWrite;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    // Scaled down to the height of a text row, so a panel of mixed fields
    // reads as one list rather than as rows of two different sizes.
    child: Transform.scale(
      scale: 0.75,
      alignment: Alignment.centerLeft,
      child: Switch(
        value: value,
        onChanged: onWrite,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// A box that writes when the field is left or Enter is pressed.
///
/// **Not on every keystroke.** A document rebuilt per character would put an
/// undo step behind each one, and half a typed word is usually not a value the
/// format can read — so the panel would spend most of a rename refusing.
final class _TextField extends StatefulWidget {
  const _TextField({required this.text, required this.onWrite});

  final String text;
  final void Function(String text) onWrite;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    // The document is the source of truth: an undo, or an edit from a gizmo,
    // has to show here. Only when it actually differs, or typing would fight
    // the rebuild for the cursor.
    if (widget.text != _controller.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    // Keystrokes belong to the box while it has the focus, and the editor's
    // own `Focus` above would otherwise read W, A, S and D as flying the
    // camera while somebody types a material name.
    onKeyEvent: (FocusNode node, KeyEvent event) =>
        KeyEventResult.skipRemainingHandlers,
    child: TextField(
      controller: _controller,
      onSubmitted: widget.onWrite,
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (_controller.text != widget.text) widget.onWrite(_controller.text);
      },
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        filled: true,
        fillColor: Color(0xFF171A1F),
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
    ),
  );
}

/// Three or four numbers side by side: a position, a size, a colour.
final class _NumbersField extends StatelessWidget {
  const _NumbersField({required this.values, required this.onWrite});

  final List<num> values;
  final void Function(List<num> values) onWrite;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (var i = 0; i < values.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: _TextField(
            text: _FieldRow._numberText(values[i]),
            onWrite: (String text) {
              final parsed = num.tryParse(text);
              if (parsed == null) return;
              onWrite(<num>[
                for (var j = 0; j < values.length; j++)
                  j == i ? parsed : values[j],
              ]);
            },
          ),
        ),
      ],
    ],
  );
}

final class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: Color(0xFF5E6672), fontSize: 11),
  );
}
