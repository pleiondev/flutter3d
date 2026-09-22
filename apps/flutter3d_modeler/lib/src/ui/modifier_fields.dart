/// One control per field a modifier has — `ux-13`.
///
/// **`hintsForModifier` has named every field of every kind since `mesh-40`
/// and the panel drew one of them.** An array's count had a box; its offset,
/// its merge distance, a mirror's whole four, a subdivision's two levels and
/// a boolean's operation were all in the document, editable over MCP, and
/// unreachable from the interface that shows the stack.
///
/// **A control per `ParamHint`, not per modifier kind.** The alternative is a
/// switch over five kinds with a hand-written form in each, which is where
/// the missing fields came from in the first place: a kind added later gets
/// its fields for free here, and a field added to a kind gets a control the
/// moment the hint names it.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

/// Every field of [modifier], each with the control its hint calls for.
///
/// [onSet] takes `SetModifierField`'s own vocabulary — the field's name and
/// the value in the shape that command reads back: an `int` for an
/// [IntHint], a `double` for a [DoubleHint], a three-element `List<double>`
/// for a [Vector3Hint], the enum's own name for an [EnumHint].
class ModifierFields extends StatelessWidget {
  const ModifierFields({
    super.key,
    required this.modifier,
    required this.onSet,
  });

  final Modifier modifier;
  final void Function(String field, Object? value) onSet;

  /// What the field is called in the panel — the hint's key with its camel
  /// case opened out, so `mergeDistance` reads as "Merge distance" rather
  /// than being written down a second time in a table that can drift.
  static String labelFor(String field) {
    final StringBuffer out = StringBuffer();
    for (var at = 0; at < field.length; at++) {
      final String character = field[at];
      final bool upper =
          character.toUpperCase() == character &&
          character.toLowerCase() != character;
      if (at == 0) {
        out.write(character.toUpperCase());
      } else if (upper) {
        out.write(' ${character.toLowerCase()}');
      } else {
        out.write(character);
      }
    }
    return out.toString();
  }

  /// What [modifier] holds for [field] right now, read out of its own JSON —
  /// the same door `hintsForModifier` names the fields through, so nothing
  /// here has to know which kind it is holding.
  Object? valueOf(String field) => modifier.toJson()[field];

  @override
  Widget build(BuildContext context) {
    final Map<String, ParamHint> hints = hintsForModifier(modifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final MapEntry<String, ParamHint> each in hints.entries)
          _control(context, each.key, each.value),
      ],
    );
  }

  Widget _control(BuildContext context, String field, ParamHint hint) {
    final String label = labelFor(field);
    switch (hint) {
      // **The hint's own min/max are not clamped here.** `NumberField` has
      // no range of its own, deliberately — see `RangeSliderField`'s note
      // that a hint describes a control and never constrains what a
      // document may say — and the command is what refuses a value out of
      // range, in one place rather than in every control that can send one.
      case IntHint():
        return NumberField(
          label: label,
          semanticLabel: label,
          value: ((valueOf(field) as num?) ?? 0).toDouble(),
          step: 1,
          // Back as an `int`, because that is what `fromJson` matches on and
          // a `2.0` where a `2` was expected reads back as null — the same
          // trap the operation card's own amend documents.
          onChanged: (double to) => onSet(field, to.round()),
        );
      case DoubleHint(:final step, :final unit):
        return NumberField(
          label: label,
          semanticLabel: label,
          value: ((valueOf(field) as num?) ?? 0).toDouble(),
          step: step ?? 0.1,
          unit: unit == 'm' ? NumberUnit.metres : NumberUnit.plain,
          onChanged: (double to) => onSet(field, to),
        );
      case BoolHint():
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: Theme.of(context).textTheme.bodySmall),
          value: valueOf(field) == true,
          onChanged: (bool to) => onSet(field, to),
        );
      case EnumHint(:final values):
        final String now = '${valueOf(field)}';
        return Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            DropdownButton<String>(
              value: values.contains(now) ? now : values.first,
              isDense: true,
              items: <DropdownMenuItem<String>>[
                for (final String value in values)
                  DropdownMenuItem<String>(value: value, child: Text(value)),
              ],
              onChanged: (String? to) {
                if (to != null) onSet(field, to);
              },
            ),
          ],
        );
      case Vector3Hint(:final step, :final unit):
        // Three boxes that travel together: a change to one sends all three,
        // since `SetModifierField` takes the whole vector rather than a
        // component — a command that set one axis would be a command that
        // reads the other two out of a document that may have moved. The
        // field's own name goes above them, since three boxes each wearing
        // "Offset" would say it three times and X/Y/Z is what tells them
        // apart.
        final List<double> now = <double>[
          for (final Object? each
              in (valueOf(field) as List<Object?>?) ?? const <Object?>[0, 0, 0])
            ((each as num?) ?? 0).toDouble(),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Row(
              children: <Widget>[
                for (var axis = 0; axis < 3; axis++)
                  // The axis letters are the same in both languages, and the
                  // name in front of them is whatever the caller passed. Both
                  // halves are read out above the string: a quote inside an
                  // interpolation reads as the end of the string to every
                  // scanner that is not a Dart parser, `ux-22`'s own literal
                  // check included.
                  if (<String>['X', 'Y', 'Z'][axis] case final String letter)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: axis == 2 ? 0 : 4),
                        child: NumberField(
                          label: letter,
                          semanticLabel: '$label ${letter.toLowerCase()}',
                          value: now.length > axis ? now[axis] : 0,
                          step: step ?? 0.1,
                          unit: unit == 'm'
                              ? NumberUnit.metres
                              : NumberUnit.plain,
                          onChanged: (double to) => onSet(field, <double>[
                            for (var each = 0; each < 3; each++)
                              each == axis
                                  ? to
                                  : (now.length > each ? now[each] : 0),
                          ]),
                        ),
                      ),
                    ),
              ],
            ),
          ],
        );
    }
  }
}
