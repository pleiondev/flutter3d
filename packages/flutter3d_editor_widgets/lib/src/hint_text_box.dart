/// A number's own text, and the two small widgets [FieldRow] falls back to
/// when nothing has hinted a value's shape: one box, and a row of them for a
/// vector.
///
/// **Not on every keystroke.** [HintTextBox] reports when the person has
/// finished — Enter, or leaving the field — never mid-word: a field that
/// wrote on every keystroke would turn `1.5` into a move to `1` and then a
/// move to `1.5`, two steps of undo history for one number typed.
///
/// **Keystrokes belong to the box while it has the focus.** [HintTextBox]'s
/// own `Focus(onKeyEvent: ...)` swallows every key event reaching it rather
/// than letting it fall through — an ancestor `Focus` reading bare letters as
/// tool shortcuts must not see `W`, `A`, `S`, `D` while a name is being
/// typed into this box.
library;

import 'package:flutter/material.dart';

/// [it] with no trailing `.0` — a whole number stays a whole number and a
/// fraction keeps exactly what it is. What [FieldRow]'s own by-type fallback
/// and [NumbersRow] both print a number as; kept apart from
/// `NumberField.show`, which right-trims a fixed three decimal places for an
/// ordinary field instead — see the package README.
String numberText(num it) =>
    it is int || it == it.roundToDouble() ? '${it.toInt()}' : '$it';

/// A box that writes [onWrite] when the field is left or Enter is pressed.
final class HintTextBox extends StatefulWidget {
  const HintTextBox({super.key, required this.text, required this.onWrite});

  final String text;
  final void Function(String text) onWrite;

  @override
  State<HintTextBox> createState() => _HintTextBoxState();
}

class _HintTextBoxState extends State<HintTextBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(HintTextBox old) {
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
    // Keystrokes belong to the box while it has the focus, and an ancestor's
    // own `Focus` would otherwise read W, A, S and D as flying the camera
    // while somebody types a name.
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
final class NumbersRow extends StatelessWidget {
  const NumbersRow({super.key, required this.values, required this.onWrite});

  final List<num> values;
  final void Function(List<num> values) onWrite;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (var i = 0; i < values.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: HintTextBox(
            text: numberText(values[i]),
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
