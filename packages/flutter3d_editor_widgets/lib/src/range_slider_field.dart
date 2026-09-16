/// A number chosen by dragging between two ends — a slider, paired with
/// either a live read-out beside it or a box that also accepts one typed in.
///
/// **Two shapes, one widget.** The level editor's own version always paired
/// the slider with a text box: a value a hint describes is not a value the
/// box stops printing exactly, and a number past the hint's own ends had to
/// stay typeable rather than being silently dragged back inside them. The
/// modeller's own version never had a box at all — a material's own field
/// always sits inside its range, and a two-decimal number beside the thumb
/// was enough. [RangeSliderField.editable] is which of the two a caller
/// gets, rather than forcing every caller through the heavier one.
///
/// **[RangeSliderField.step] chooses whether the value is quantised.** A step
/// snaps the value a drag ends on to the nearest increment and rounds it to
/// four decimal places, so a material file never carries
/// `0.30000000000000004`. A null step is the promise the other way: what
/// [RangeSliderField.onChanged] receives is exactly what the drag produced,
/// bit for bit — the shape a caller with no step of its own has to ask for,
/// rather than inheriting a rounding nobody asked for.
library;

import 'package:flutter/material.dart';

import 'editor_widgets_theme.dart';

/// A slider between [min] and [max].
final class RangeSliderField extends StatefulWidget {
  const RangeSliderField({
    super.key,
    this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step,
    required this.onChanged,
    this.enabled = true,
    this.editable = false,
  });

  /// Drawn in a column [EditorWidgetsTheme.labelWidth] wide before the
  /// slider — or, when null, not drawn at all. A caller that already lays
  /// out its own label column (`FieldRow`'s own row, once it arrives) passes
  /// null and keeps doing that itself.
  final String? label;

  /// The value right now. Shown wherever the slider itself cannot reach it
  /// — outside `[min, max]`, or between two steps — rather than clamped or
  /// rounded on the way in: the engine's own note on `RangeHint` is that a
  /// hint describes a control and never constrains what a document may say.
  final double value;

  final double min;
  final double max;

  /// The increment a drag lands on, or null for a value that stays exactly
  /// what the drag produced — see the library comment.
  final double? step;

  /// Called once, when a drag ends or a typed value is submitted — never
  /// while a finger is still on the thumb, the same bargain every history
  /// this engine keeps strikes for a drag.
  final ValueChanged<double> onChanged;

  final bool enabled;

  /// Whether the slider is paired with a text box that shows the exact
  /// value and accepts one typed in, with a line under the row when [value]
  /// sits outside `[min, max]`. False draws the modeller's own lighter row:
  /// a two-decimal number that only ever shows what the slider itself can
  /// reach.
  final bool editable;

  @override
  State<RangeSliderField> createState() => _RangeSliderFieldState();
}

class _RangeSliderFieldState extends State<RangeSliderField> {
  /// Where the thumb is while a finger is on it — null once the drag ends,
  /// so the slider then shows [RangeSliderField.value] itself, the same
  /// number every other reader of the document sees.
  double? _dragging;

  @override
  void didUpdateWidget(RangeSliderField old) {
    super.didUpdateWidget(old);
    // The document is the source of truth: an undo, or an edit from
    // somewhere else entirely, has to show here rather than under a stale
    // drag position.
    if (widget.value != old.value) _dragging = null;
  }

  void _commit(double raw) {
    final double? step = widget.step;
    if (step == null || step <= 0.0) {
      widget.onChanged(raw);
      return;
    }
    final double stepped = (raw / step).roundToDouble() * step;
    widget.onChanged(double.parse(stepped.toStringAsFixed(4)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EditorWidgetsTheme editorTheme = EditorWidgetsTheme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // `ux-23`: the label goes above the row where there is not room for
        // it beside one. **Measured rather than assumed**: the same panel is
        // 250 wide on a desktop and the whole window on a phone, and a row
        // that always stacked would waste a line everywhere one fitted.
        // Below this the slider is a stub nobody can aim at and the label is
        // the first thing the ellipsis eats — the review found "Ambient"
        // reading as "Am".
        //
        // **Everything else on the row counts, not the label alone.** The
        // read-out and the gap before it are as fixed as the label column
        // is, and leaving them out of the sum measured a slider forty pixels
        // wider than the one that actually gets drawn: the review's own
        // 250-wide panel, whose slider is 114 pixels, read as wide enough.
        final double besideSlider =
            editorTheme.labelWidth +
            _gapBeforeValue +
            _valueWidth(editable: widget.editable);
        final bool stacked =
            widget.label != null &&
            constraints.maxWidth < besideSlider + kLabelBesideFrom;
        return _row(context, theme, editorTheme, stacked: stacked);
      },
    );
  }

  Widget _row(
    BuildContext context,
    ThemeData theme,
    EditorWidgetsTheme editorTheme, {
    required bool stacked,
  }) {
    final double value = widget.value;
    final double shown = (_dragging ?? value).clamp(widget.min, widget.max);
    final double? step = widget.step;
    final int? divisions = step == null || step <= 0.0
        ? null
        : ((widget.max - widget.min) / step).round().clamp(1, 1000000);
    final bool outside = value < widget.min || value > widget.max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (stacked)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              widget.label!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: widget.enabled ? null : theme.disabledColor,
              ),
            ),
          ),
        Row(
          children: <Widget>[
            if (!stacked)
              if (widget.label case final String label)
                SizedBox(
                  width: editorTheme.labelWidth,
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.enabled ? null : theme.disabledColor,
                    ),
                  ),
                ),
            Expanded(
              // Track thickness and thumb size come from the ambient
              // `Theme.of(context).sliderTheme`, not a literal — see
              // `ColorField`'s own `_ChannelSlider` for the same choice and
              // why.
              child: Slider(
                // Keyed by label so a test can tell one field's slider from
                // another's sitting in the same panel.
                key: ValueKey<String>('slider-${widget.label}'),
                value: shown,
                min: widget.min,
                max: widget.max,
                divisions: divisions,
                onChanged: widget.enabled
                    ? (double v) => setState(() => _dragging = v)
                    : null,
                onChangeEnd: widget.enabled
                    ? (double v) {
                        setState(() => _dragging = null);
                        _commit(v);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: _gapBeforeValue),
            if (widget.editable)
              SizedBox(
                width: _valueWidth(editable: true),
                child: _ValueBox(
                  text: _numberText(value),
                  enabled: widget.enabled,
                  onSubmitted: widget.onChanged,
                ),
              )
            else
              SizedBox(
                width: _valueWidth(editable: false),
                child: Text(
                  shown.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.enabled ? null : theme.disabledColor,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (widget.editable && outside)
          Padding(
            padding: EdgeInsets.only(
              left: widget.label == null || stacked
                  ? 0
                  : editorTheme.labelWidth,
            ),
            child: Text(
              '${_numberText(value)} is outside '
              '${_numberText(widget.min)}–${_numberText(widget.max)}',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 10),
            ),
          ),
      ],
    );
  }
}

/// [value] with no trailing `.0` — a plain `0` or `0.75` rather than `0.000`
/// or `0.750`, the same rule the row's own outside-range line and text box
/// both read numbers by.
String _numberText(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';

/// The narrowest a row can be and still hold a label beside a slider a
/// person can aim at — `ux-23`.
///
/// A slider under about a hundred and fifty pixels is a stub: the thumb is
/// most of it, and the label beside it is the first thing the ellipsis eats.
/// Added to whatever the label column is, since that is the room the label
/// itself wants.
const double kLabelBesideFrom = 150;

/// The gap between the slider and whatever reports its value.
const double _gapBeforeValue = 6;

/// How wide that report is: a box somebody can type into needs more room
/// than a two-decimal number that only ever shows what the slider reached.
///
/// A function rather than two constants used in three places each, because
/// the width the row draws and the width [RangeSliderField.build] measures
/// against have to be the same number — they were not, and a row 250 wide
/// with a 114-pixel slider in it counted as having room.
double _valueWidth({required bool editable}) => editable ? 54 : 34;

/// A box that reports a number when the person has finished, and only then
/// — [RangeSliderField.editable]'s own fallback for a value that may sit
/// outside the slider's own ends.
final class _ValueBox extends StatefulWidget {
  const _ValueBox({
    required this.text,
    required this.enabled,
    required this.onSubmitted,
  });

  final String text;
  final bool enabled;
  final ValueChanged<double> onSubmitted;

  @override
  State<_ValueBox> createState() => _ValueBoxState();
}

class _ValueBoxState extends State<_ValueBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(_ValueBox old) {
    super.didUpdateWidget(old);
    if (widget.text != _controller.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final double? parsed = double.tryParse(text.trim().replaceAll(',', '.'));
    if (parsed != null) widget.onSubmitted(parsed);
  }

  @override
  Widget build(BuildContext context) => Focus(
    // Keystrokes belong to the box while it has the focus — an ancestor's
    // own `Focus` reading bare letters as camera or tool shortcuts must not
    // see them while a number is being typed.
    onKeyEvent: (FocusNode node, KeyEvent event) =>
        KeyEventResult.skipRemainingHandlers,
    child: TextField(
      controller: _controller,
      enabled: widget.enabled,
      onSubmitted: _submit,
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        _submit(_controller.text);
      },
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: EditorWidgetsTheme.of(context).denseFields,
        contentPadding: EditorWidgetsTheme.of(
          context,
        ).fieldPadding(horizontal: 6),
      ),
    ),
  );
}
