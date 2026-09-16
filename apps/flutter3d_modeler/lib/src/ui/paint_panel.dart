/// Screen 18 — `pro-pt-05`: the texture-painting panel.
///
/// **The canvas is on the panel because that is where a person looks when
/// the brush is on the model.** A stroke lands on the surface and on the
/// flattened texture at once, and only one of those shows whether the stroke
/// went where the UVs put it — which is the question a seam raises and the
/// viewport cannot answer.
///
/// **Layers, a palette and masks, in that order.** The layer is what a
/// stroke lands on, the colour is what it lands in, and a mask is the thing
/// somebody reaches for last, once both of those are settled.
library;

import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

/// The panel's own width — `pro-pt-05`'s own 300.
const double kPaintPanelWidth = 300;

/// The paint brush's own cursor diameter, in logical pixels —
/// `pro-pt-05`'s own ⌀96.
///
/// **Smaller than the sculpting brush's own ⌀140** (`kSculptCursorDiameter`)
/// and that is the row's own number rather than an oversight: a sculpting
/// stroke moves a region of the surface and wants to be seen at the scale of
/// the form, and a painting stroke puts a mark on it and wants to be aimed.
const double kPaintCursorDiameter = 96;

/// One layer, as the panel lists it.
typedef PaintLayerRow = ({String name, String blend, bool visible});

/// Screen 18's own panel: the flattened canvas, the layers, the palette and
/// the masks.
class PaintPanel extends StatelessWidget {
  const PaintPanel({
    super.key,
    required this.layers,
    required this.selectedLayer,
    required this.onSelectLayer,
    required this.onAddLayer,
    required this.colour,
    required this.onColour,
    required this.radius,
    required this.onRadius,
    required this.strength,
    required this.onStrength,
    required this.masks,
    required this.mask,
    required this.onMask,
    this.canvas,
    this.refusal,
  });

  /// Bottom-first, the same order the stack itself is in.
  final List<PaintLayerRow> layers;

  /// Which layer a stroke lands on.
  final int selectedLayer;
  final ValueChanged<int> onSelectLayer;

  /// Add an empty layer above the stack.
  final VoidCallback onAddLayer;

  /// The brush's own colour, straight-alpha RGBA `0..1`.
  final List<double> colour;
  final ValueChanged<List<double>> onColour;

  /// In logical pixels, the cursor's own diameter.
  final double radius;
  final ValueChanged<double> onRadius;

  final double strength;
  final ValueChanged<double> onStrength;

  /// The masks this project has, by the name their image carries — the
  /// occlusion and curvature bakes `pro-rt-05` produces.
  final List<String> masks;

  /// Which one gates the stroke, or null for none.
  final String? mask;
  final ValueChanged<String?> onMask;

  /// The flattened canvas as it stands, or null before anything is painted.
  ///
  /// **A `ui.Image`, decoded by whoever owns the device.** This widget draws
  /// what it is handed; decoding a PNG needs `dart:ui`'s own codec and a
  /// frame to await it on, and a panel that did that would rebuild into a
  /// blank square every time its parent rebuilt.
  final ui.Image? canvas;

  /// Why a stroke cannot land — no object, no UVs, no material.
  final String? refusal;

  /// The palette a person picks from without opening a colour wheel.
  static const List<List<double>> swatches = <List<double>>[
    <double>[1, 1, 1, 1],
    <double>[0, 0, 0, 1],
    <double>[0.85, 0.2, 0.2, 1],
    <double>[0.95, 0.65, 0.15, 1],
    <double>[0.35, 0.65, 0.3, 1],
    <double>[0.25, 0.45, 0.85, 1],
  ];

  static Color _colourOf(List<double> rgba) => Color.fromARGB(
    (rgba[3] * 255).round(),
    (rgba[0] * 255).round(),
    (rgba[1] * 255).round(),
    (rgba[2] * 255).round(),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: kPaintPanelWidth,
      child: ListView(
        primary: false,
        children: <Widget>[
          if (refusal != null)
            Text(
              refusal!,
              key: const ValueKey<String>('paintRefusal'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          SectionLabel('Canvas'),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              key: const ValueKey<String>('paintCanvas'),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: canvas == null
                  ? Center(
                      child: Text(
                        'Nothing painted yet',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : RawImage(image: canvas, fit: BoxFit.contain),
            ),
          ),
          SectionLabel('Layers'),
          for (var i = layers.length - 1; i >= 0; i--)
            ListTile(
              key: ValueKey<String>('paintLayer-$i'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: i == selectedLayer,
              leading: Icon(
                layers[i].visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              title: Text(layers[i].name, style: theme.textTheme.bodySmall),
              subtitle: Text(
                layers[i].blend,
                style: theme.textTheme.labelSmall,
              ),
              onTap: () => onSelectLayer(i),
            ),
          TextButton.icon(
            key: const ValueKey<String>('paintAddLayer'),
            onPressed: onAddLayer,
            icon: const Icon(Icons.add),
            label: const Text('Add a layer'),
          ),
          SectionLabel('Colour'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < swatches.length; i++)
                InkWell(
                  key: ValueKey<String>('paintSwatch-$i'),
                  onTap: () => onColour(swatches[i]),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _colourOf(swatches[i]),
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                      border: Border.all(
                        color: _sameColour(swatches[i], colour)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: _sameColour(swatches[i], colour) ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          RangeSliderField(
            label: 'Size',
            value: radius,
            min: 8,
            max: 400,
            onChanged: onRadius,
          ),
          RangeSliderField(
            label: 'Strength',
            value: strength,
            min: 0,
            max: 1,
            step: 0.05,
            onChanged: onStrength,
          ),
          SectionLabel('Mask'),
          DropdownButton<String?>(
            key: const ValueKey<String>('paintMask'),
            isExpanded: true,
            value: mask,
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(child: Text('None')),
              for (final String each in masks)
                DropdownMenuItem<String?>(value: each, child: Text(each)),
            ],
            onChanged: onMask,
          ),
        ],
      ),
    );
  }

  static bool _sameColour(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-6) return false;
    }
    return true;
  }
}
