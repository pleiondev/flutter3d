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
///
/// **It is not `flutter3d_editor_widgets` yet.** `ui-27` moves this and its
/// siblings into a package both editors share, and doing that before the level
/// editor's own fields are ready would be publishing an interface for one
/// caller.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// One labelled number.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  /// What it is: `X`, `Y`, `Segments`.
  final String label;

  /// What it holds now. A field whose value arrives from outside rather than
  /// being kept here: the document is the truth, and a field that remembered
  /// its own would go on showing a number an undo had taken away.
  final double value;

  /// Called with the new number when the person has finished.
  final ValueChanged<double> onChanged;

  final bool enabled;

  /// What [said] means as a number, or null.
  ///
  /// Static and public because the rule — a comma is a decimal point — is the
  /// thing worth testing, and testing it through a widget would mean pumping
  /// one to ask what `1,5` is.
  static double? parse(String said) {
    final String trimmed = said.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final double? read = double.tryParse(trimmed);
    // Infinity and NaN parse. A transform holding either draws nothing, and
    // every later number computed from it is a NaN as well — so the failure
    // arrives far from the field somebody typed it into.
    if (read == null || !read.isFinite) return null;
    return read;
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
  static String show(double value) => value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');

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

  void _commit() {
    final double? read = NumberField.parse(_text.text);
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
    final theme = Theme.of(context);
    return SizedBox(
      height: ModelerMetrics.row,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            child: Text(
              widget.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
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
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _focus.unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three of them, for a vector.
class VectorField extends StatelessWidget {
  const VectorField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<double> value;

  /// Called with the whole vector, not the component that changed: what the
  /// document takes is a transform, and reassembling one from three separate
  /// callbacks is three chances to use a stale pair.
  final void Function(List<double> to) onChanged;

  final bool enabled;

  static const List<String> _labels = <String>['X', 'Y', 'Z'];

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (var axis = 0; axis < 3; axis++)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: NumberField(
            label: _labels[axis],
            value: value[axis],
            enabled: enabled,
            onChanged: (double to) => onChanged(<double>[
              for (var i = 0; i < 3; i++) i == axis ? to : value[i],
            ]),
          ),
        ),
    ],
  );
}
