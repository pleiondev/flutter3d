/// A box that holds one number.
///
/// **It takes a comma and it takes a full stop.** A person with a Russian or a
/// German keyboard types `1,5`; the numeric keypad on the same machine types
/// `1.5`. Refusing either is a field that silently ignores what somebody just
/// typed, and refusing it *quietly* — by leaving the old value — is the version
/// nobody notices until a model is the wrong size.
///
/// **It reports when the person has finished, not while they are typing.** A
/// field that emitted on every keystroke turns `1.5` into a move to `1` and
/// then a move to `1.5`, which is two steps of history and one visible jump.
/// Enter and leaving the field are both "finished"; Escape puts back what was
/// there.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_widgets_theme.dart';
import 'number_expression.dart';

/// One labelled number.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showLabel = true,
    this.semanticLabel,
    this.labelWidth = 18,
    this.unit = NumberUnit.plain,
    this.step = 0.1,
  });

  /// What this field's own numbers mean, so `10cm` typed into a field of
  /// metres commits 0.1 — `ux-15`. [NumberUnit.plain] refuses suffixes,
  /// which is right for a count or a factor.
  final NumberUnit unit;

  /// How much one press of an arrow key, or one pixel of a scrub on the
  /// label, is worth. `Shift` is ten of these and `Ctrl` a tenth.
  final double step;

  /// What it is: `X`, `Y`, `Segments`.
  final String label;

  /// How much room the drawn [label] gets, in logical pixels.
  ///
  /// Eighteen fits the single letter a transform grid's own rows carry, which
  /// is what every caller wanted until one arrived with a word: the
  /// last-operation card labels its field with the parameter's own name, and
  /// "distance" in eighteen pixels wrapped to two lines reading "dis" and
  /// "ta". A caller with a word passes the room it needs; the label is kept
  /// to one line either way, so the worst case is a name cut short rather
  /// than a row twice the height of the ones above it.
  final double labelWidth;

  /// Whether [label] draws as the field's own visible left-hand text.
  ///
  /// A grid that already carries the label as a column header (`Position`
  /// `Rotation` `Scale` × `X` `Y` `Z`) does not want it repeated inside every
  /// cell — but a screen reader, which never sees the header's own row/column
  /// position, still needs to be told which cell this is. That is
  /// [semanticLabel]'s job, kept independent of whether [label] is drawn.
  final bool showLabel;

  /// What a screen reader announces this field as, when it needs to say more
  /// than [label] alone would — `"Position X"` rather than a bare `"X"`
  /// repeated nine times across a grid with nothing else to tell the fields
  /// apart. Falls back to [label] when not given.
  final String? semanticLabel;

  /// What it holds now. A field whose value arrives from outside rather than
  /// being kept here: the document is the truth, and a field that remembered
  /// its own would go on showing a number an undo had taken away.
  final double value;

  /// Called with the new number when the person has finished.
  final ValueChanged<double> onChanged;

  final bool enabled;

  /// What [said] means as a number, or null.
  ///
  /// Static and public because the rules — a comma is a decimal point, `1/3`
  /// is a third, `10cm` in a field of metres is 0.1 — are the thing worth
  /// testing, and testing them through a widget would mean pumping one to ask
  /// what `1,5` is.
  ///
  /// Infinity and NaN are refused along with everything else that is not a
  /// number: a transform holding either draws nothing, and every later number
  /// computed from it is a NaN as well — so the failure would arrive far from
  /// the field somebody typed it into.
  static double? parse(String said, {NumberUnit unit = NumberUnit.plain}) {
    final String trimmed = said.trim();
    if (trimmed.isEmpty) return null;
    return evaluateNumber(trimmed, unit: unit);
  }

  /// How a number is shown: enough places to be exact, none of them noise.
  ///
  /// A position of `1` reads as `1` rather than `1.000`, and one of `0.3333…`
  /// stops at three places — which is a tenth of a millimetre at the scale
  /// models are built at, and is where a field stops being readable.
  ///
  /// The decimal point stops the trailing-zero strip, so a whole number needs
  /// no case of its own: `100.000` loses three zeros and then the point, and
  /// `1000.000` loses the same three rather than six. A branch for whole
  /// numbers was written and taken back out — it answered the same thing for
  /// every value that reaches a field, which makes it a branch no test can
  /// tell from its absence.
  ///
  /// **The places follow the magnitude**, which is `ux-15`'s own live
  /// finding: an STL read in at a scale of 0.001 put numbers in these fields
  /// that three places round to zero, so a field showed `0` for a value that
  /// was not zero and typing what it showed would have destroyed the model.
  /// Three places is right at the scale things are built at and wrong four
  /// decades below it, so the small end gets more of them.
  static String show(double value) {
    final double size = value.abs();
    // Three places down to a hundredth, which is where a field stops being
    // readable and is the whole range things are normally built at; below
    // that, enough places to show a value three would round away.
    final int places = size == 0 || size >= 0.01
        ? 3
        : size >= 1e-4
        ? 6
        : 8;
    return value
        .toStringAsFixed(places)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _text = TextEditingController(
    text: NumberField.show(widget.value),
  );
  final FocusNode _focus = FocusNode();

  /// The last number this reported, or the one it was given.
  ///
  /// **Not `widget.value`, and the difference is a whole extra step of
  /// history.** Pressing Enter both submits and takes the focus away, so the
  /// commit runs twice; the second run still sees the *old* `widget.value`,
  /// because the document has not come back round through a rebuild yet, and
  /// reports the same number a second time. One press, two commands, two
  /// presses of ⌘Z to get back.
  late double _reported = widget.value;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    // Only while nobody is typing in it. Rewriting the text under a cursor is
    // how a field eats a keystroke, and the value arrives from the document
    // every frame — including the frames in the middle of a drag.
    if (!_focus.hasFocus && widget.value != old.value) {
      _text.text = NumberField.show(widget.value);
      _reported = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// What one press of an arrow key, or one pixel of a scrub, is worth right
  /// now — `ux-15`.
  ///
  /// Shift is ten of the field's own step and Ctrl a tenth, which is the pair
  /// every application in the field agrees on. The command key counts as Ctrl
  /// because on a Mac it is the one under the same finger.
  double get _stepNow {
    final HardwareKeyboard keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return widget.step * 10;
    if (keys.isControlPressed || keys.isMetaPressed) return widget.step * 0.1;
    return widget.step;
  }

  /// Moves the value by [by] and reports it, the way a commit does.
  ///
  /// Reported as it goes rather than when the drag ends: the document takes
  /// these as one step anyway — a transform panel runs them through the same
  /// `amend`/transaction the sliders already use — and a scrub that showed
  /// nothing until it was let go would be a scrub nobody could aim.
  void _nudge(double by) {
    if (!widget.enabled || by == 0) return;
    final double from =
        NumberField.parse(_text.text, unit: widget.unit) ?? widget.value;
    final double to = from + by;
    if (!to.isFinite) return;
    _text.text = NumberField.show(to);
    if (to == _reported) return;
    _reported = to;
    widget.onChanged(to);
  }

  /// Up and down nudge the value; everything else is the field's own.
  KeyEventResult _arrowKeys(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final double direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => 1,
      LogicalKeyboardKey.arrowDown => -1,
      _ => 0,
    };
    if (direction == 0) return KeyEventResult.ignored;
    _nudge(direction * _stepNow);
    return KeyEventResult.handled;
  }

  void _commit() {
    final double? read = NumberField.parse(_text.text, unit: widget.unit);
    if (read == null) {
      // Put back what the document says rather than leaving whatever was
      // typed: a field showing `1,5,` after a slip is a field a person will
      // read as a value.
      _text.text = NumberField.show(widget.value);
      return;
    }
    if (read != _reported) {
      _reported = read;
      widget.onChanged(read);
    }
    _text.text = NumberField.show(read);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EditorWidgetsTheme editorTheme = EditorWidgetsTheme.of(context);
    final field = Focus(
      // Ancestor of the box rather than a handler on it: a single-line
      // `TextField` does not use up or down, so the key arrives here after it
      // has passed on it — which is exactly the order that lets the box keep
      // left, right, home and end for the text.
      onKeyEvent: _arrowKeys,
      canRequestFocus: false,
      child: Semantics(
        // The visible label is one `Text` widget among several in a row or a
        // grid cell; nothing ties it to this specific `TextField` in the
        // semantics tree unless something here says so explicitly — a screen
        // reader otherwise announces a bare number with no idea what it is a
        // number of.
        label: widget.semanticLabel ?? widget.label,
        textField: true,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          enabled: widget.enabled,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
          // A keyboard on a handset, and nothing on a desktop. `signed` and
          // `decimal` both, because a coordinate is either.
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(
            isDense: editorTheme.denseFields,
            // The hand-over's own metric: padding 6×8-10, radius 6 — this file
            // had the two axes swapped and the corner square until now. Both
            // now come off the row height, so a panel handed a taller row
            // gets a field that fills it rather than one floating in it.
            contentPadding: editorTheme.fieldPadding(),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(editorTheme.fieldRadius),
              ),
            ),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _focus.unfocus(),
        ),
      ),
    );
    return SizedBox(
      height: editorTheme.rowHeight,
      child: widget.showLabel
          ? Row(
              children: <Widget>[
                SizedBox(
                  width: widget.labelWidth,
                  // Excluded from the semantics tree: the `Semantics` wrapping
                  // `field` above already announces this same text, and a
                  // screen reader that also finds this plain `Text` widget
                  // would say "X" twice for one field.
                  child: ExcludeSemantics(
                    // `ux-15`: the label is a scrub handle. Dragging sideways
                    // on it moves the value a step a pixel, which is how a
                    // number gets set by eye against what is on screen rather
                    // than by typing and looking and typing again. On the
                    // label rather than the box, so selecting text in the box
                    // still works.
                    child: MouseRegion(
                      cursor: widget.enabled
                          ? SystemMouseCursors.resizeLeftRight
                          : MouseCursor.defer,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (DragUpdateDetails it) =>
                            _nudge(it.delta.dx * _stepNow),
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: field),
              ],
            )
          : field,
    );
  }
}
