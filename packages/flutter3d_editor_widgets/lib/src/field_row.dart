/// One field: its name, and whatever editor a [MaterialHint] calls for — or,
/// failing that, its current value's own type.
///
/// **One row for both panels**, which is why it is public. The level editor
/// and a material panel are the same problem asked twice — a name, a value,
/// and a way to write it back — and two rows would be two places for
/// "emptying a box clears the key" and "a change goes through the history"
/// to drift apart. `apps/flutter3d_editor`'s own `EditorInspector` and
/// `MaterialPanel` are the two ends of that.
///
/// **Typed by the value, unless something can say better.** [FieldRow] asks
/// a [MaterialHint] first and falls back to the value's own type, which is
/// what lets one row serve two panels: a level has no schema and goes on
/// being edited exactly as it was, while a material — which does have one —
/// gets a slider where the range is known, a picker where the value is a
/// colour, a file field where it is a path and a list where the choices are
/// finite.
///
/// Assembled from the rest of this package: [RangeSliderField] and
/// [EnumField] for a hinted number and a hinted word, [ColorSwatchField] and
/// [TexturePathField] for a hinted colour and a hinted path, and this file's
/// own [HintTextBox]/[NumbersRow] fallback for a value nothing has hinted.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart'
    show ColorHint, EnumHint, MaterialHint, RangeHint, TextureHint;

import 'color_swatch_field.dart';
import 'enum_field.dart';
import 'hint_text_box.dart';
import 'range_slider_field.dart';
import 'texture_path_field.dart';

/// One field: its name, and whatever editor a [MaterialHint] — or, failing
/// that, the value itself — calls for.
final class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.name,
    required this.value,
    required this.onWrite,
    this.hint,
    this.faded = false,
    this.offers = nothingToOffer,
  });

  final String name;
  final Object? value;
  final void Function(Object? value) onWrite;

  /// What a control for this value should look like, when anything knows.
  ///
  /// Null for every field of a level, and that is the whole reason
  /// [_hinted] and [_byType] both exist: the level format has no schema to
  /// ask, so a document nothing has hinted goes on being edited by the type
  /// of what is there.
  final MaterialHint? hint;

  /// Whether this row shows what the format would use rather than what the
  /// document says. Writing it is what puts the key in the document.
  final bool faded;

  /// See [PathOffers]. Only a [TextureHint] reads it.
  final PathOffers offers;

  @override
  Widget build(BuildContext context) {
    final editor = _hinted() ?? _byType();

    final label = hint?.label ?? name;
    final help = hint?.help;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The sentence a hint carries is shown on hover rather than under
          // the name: it is a paragraph and a panel this narrow that
          // printed every one of them would be four fields tall and
          // unscrollable to the fifth.
          Tooltip(
            message: help ?? '',
            excludeFromSemantics: help == null,
            child: Text(
              label,
              style: TextStyle(
                color: faded
                    ? const Color(0xFF5E6672)
                    : const Color(0xFF8A93A0),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 2),
          editor,
        ],
      ),
    );
  }

  /// The control the hint asks for, or null.
  ///
  /// **Null when the value is not the shape the hint describes**, and that
  /// matters more than it looks: a hint may come from a file written by
  /// another tool, so a `range` over a string or a `color` over a single
  /// number is a thing that can arrive. Falling back to [_byType] there
  /// shows the value as it is, which is the only honest thing to do with a
  /// field whose description and whose content disagree.
  Widget? _hinted() => switch ((hint?.kind, value)) {
    (final RangeHint it, final num at) => RangeSliderField(
      value: at.toDouble(),
      min: it.min,
      max: it.max,
      step: it.step,
      editable: true,
      onChanged: onWrite,
    ),
    (final ColorHint it, final List<Object?> at)
        when at.length >= 3 && at.every((Object? e) => e is num) =>
      ColorSwatchField(hint: it, values: at.cast<num>(), onWrite: onWrite),
    (final TextureHint it, final String at) => TexturePathField(
      hint: it,
      path: at,
      offers: offers,
      onWrite: onWrite,
    ),
    (final EnumHint it, final String at) => EnumField(
      value: at,
      options: it.values,
      onChanged: onWrite,
    ),
    _ => null,
  };

  /// The editor the value's own type calls for — the panel as it was before
  /// anything was hinted, and what a level still gets.
  Widget _byType() => switch (value) {
    final bool it => _BoolField(value: it, onWrite: onWrite),
    final num it => HintTextBox(
      text: numberText(it),
      onWrite: (String text) {
        final parsed = num.tryParse(text);
        if (parsed != null) onWrite(parsed);
      },
    ),
    // **Emptying a text field removes the key.** `surface`, a light's
    // `name` and an entity's are all "not set" by being absent, and writing
    // `""` instead gives a brush a surface called nothing — a value the
    // format reads happily and no game means. Clearing a box is how a
    // person says "no value", so it is what it does.
    final String it => HintTextBox(
      text: it,
      onWrite: (String text) => onWrite(text.isEmpty ? null : text),
    ),
    // A list of numbers is a position, a size, a colour or a direction, and
    // all four are worth seeing and worth typing exactly — a colour picked
    // by eye is a colour nobody can reproduce from the document.
    final List<Object?> it when it.every((Object? e) => e is num) => NumbersRow(
      values: it.cast<num>(),
      onWrite: (List<num> next) => onWrite(next),
    ),
    // Anything else — a nested object, a mixed list — has no honest editor
    // here. Shown, so nobody thinks the field is missing, and not
    // editable, because a text box over a structure is a way to write a
    // document that will not load.
    _ => _ReadOnly(text: '$value'),
  };
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
