/// A colour hint's own row: a swatch that opens [ColorPaletteDialog], and
/// the numbers beside it.
///
/// The numbers stay for the reason [FieldRow]'s own by-type fallback already
/// makes for any vector: a colour picked by eye is a colour nobody can
/// reproduce from the document. The swatch is there because reading four
/// numbers is not how anybody finds out that the wall is slightly green.
///
/// **Not [ColorField].** [ColorField] is a full HSV picker with a hex box,
/// built for a caller that wants that whole surface inline; this is the
/// level editor's own lighter row — a swatch, a grid dialog, and the numbers
/// [FieldRow] already draws for any vector — kept as its own widget because
/// the level format's colour hint never asked for hue and saturation
/// sliders, only for "pick roughly the right paint, then type the exact
/// number".
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart' show ColorHint;

import 'hint_text_box.dart';

/// A colour: a swatch that opens [ColorPaletteDialog], and the numbers
/// beside it.
final class ColorSwatchField extends StatelessWidget {
  const ColorSwatchField({
    super.key,
    required this.hint,
    required this.values,
    required this.onWrite,
  });

  final ColorHint hint;
  final List<num> values;
  final void Function(Object? value) onWrite;

  Color get _shown =>
      Color.fromARGB(255, _byte(values[0]), _byte(values[1]), _byte(values[2]));

  static int _byte(num it) => (it.toDouble().clamp(0.0, 1.0) * 255).round();

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      GestureDetector(
        onTap: () async {
          final picked = await showDialog<List<double>>(
            context: context,
            builder: (BuildContext context) => const ColorPaletteDialog(),
          );
          if (picked == null) return;
          // The channel count is the hint's, not the dialog's: a swatch that
          // wrote an alpha for `emissive` would be setting a number the
          // shader never reads. A fourth component the document already
          // carries is kept — opacity is not something a hue picker has an
          // opinion about.
          onWrite(<num>[
            ...picked,
            if (hint.channels > 3 && values.length > 3) values[3],
          ]);
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _shown,
            border: Border.all(color: const Color(0xFF2A2F37)),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: NumbersRow(
          values: values,
          onWrite: (List<num> next) => onWrite(next),
        ),
      ),
    ],
  );
}

/// The swatches a colour is picked from.
///
/// A grid rather than a wheel: a wheel is a gesture nobody can repeat, and
/// what this is for is finding roughly the right paint before the numbers
/// beside it are typed exactly. Twelve hues across, four brightnesses down,
/// and a row of greys — which is where most of a level's walls actually
/// live.
final class ColorPaletteDialog extends StatelessWidget {
  const ColorPaletteDialog({super.key});

  static const List<double> _levels = <double>[1.0, 0.72, 0.45, 0.2];

  @override
  Widget build(BuildContext context) => SimpleDialog(
    backgroundColor: const Color(0xFF15181D),
    title: const Text(
      'Colour',
      style: TextStyle(color: Color(0xFF8A93A0), fontSize: 13),
    ),
    contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    children: <Widget>[
      for (final level in _levels)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var hue = 0; hue < 12; hue++)
              _swatch(context, _fromHue(hue / 12.0, level)),
          ],
        ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var grey = 0; grey < 12; grey++)
            _swatch(context, <double>[grey / 11.0, grey / 11.0, grey / 11.0]),
        ],
      ),
    ],
  );

  Widget _swatch(BuildContext context, List<double> rgb) => GestureDetector(
    onTap: () => Navigator.of(context).pop(rgb),
    child: Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.all(1),
      color: Color.fromARGB(
        255,
        ColorSwatchField._byte(rgb[0]),
        ColorSwatchField._byte(rgb[1]),
        ColorSwatchField._byte(rgb[2]),
      ),
    ),
  );

  /// A colour at [hue], dimmed to [level].
  static List<double> _fromHue(double hue, double level) {
    final sector = hue * 6.0;
    final rise = sector - sector.floorToDouble();
    final fall = 1.0 - rise;
    final rgb = switch (sector.floor() % 6) {
      0 => <double>[1.0, rise, 0.0],
      1 => <double>[fall, 1.0, 0.0],
      2 => <double>[0.0, 1.0, rise],
      3 => <double>[0.0, fall, 1.0],
      4 => <double>[rise, 0.0, 1.0],
      _ => <double>[1.0, 0.0, fall],
    };
    return <double>[
      for (final channel in rgb)
        double.parse((channel * level).toStringAsFixed(3)),
    ];
  }
}
