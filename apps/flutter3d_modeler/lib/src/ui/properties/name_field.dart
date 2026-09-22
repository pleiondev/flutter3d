/// The object's name, editable.
///
/// **Keyed by the object's id**, so selecting a different object builds a
/// different field rather than rewriting the text under a cursor — which is how
/// a rename ends up applied to whichever object happened to be selected when
/// the person pressed Enter.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../theme.dart';

/// The object's name, editable.
class NameField extends StatefulWidget {
  const NameField({super.key, required this.name, required this.onRenamed});

  final String name;
  final void Function(String to) onRenamed;

  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.name,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NameField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.name != old.name) _text.text = widget.name;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final String said = _text.text.trim();
    // An empty name is refused by the command with a sentence; putting the old
    // one back here as well means a person who clears the box and clicks away
    // is not left looking at a blank field for an object that still has a name.
    if (said.isEmpty || said == widget.name) {
      _text.text = widget.name;
      return;
    }
    widget.onRenamed(said);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // `ux-21`: a dense field is 31 tall however tall the box round it is —
    // `InputDecorator` sizes itself to its own padding, and a `SizedBox`
    // taller than that just leaves a gap the tap does not reach. So the
    // padding is what grows, and the field fills the finger-sized row.
    final double row = rowHeightOf(context);
    final bool dense = row < kTouchTarget;
    return SizedBox(
      height: row,
      child: Semantics(
        // The row it sits in already reads "Objects" above the list, but a
        // screen reader stepping field by field through the panel has no other
        // way to tell this box apart from a `NumberField`'s own bare value.
        label: l.nameField,
        textField: true,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: dense,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 6,
              vertical: dense ? 4 : 12,
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _focus.unfocus(),
        ),
      ),
    );
  }
}
