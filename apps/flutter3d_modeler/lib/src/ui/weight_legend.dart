/// `view-18`'s own legend: "0" through "1" over a 140×8 bar, the five stops
/// `weight_gradient.dart` paints the mesh with — `screen 13`'s own top-right
/// chip.
///
/// **A standalone widget, not yet placed in the viewport.** Deciding when the
/// weights view is actually on is `S5`'s own row — the sub-mode's panel and
/// brush live there — so nothing in this pass adds this to `ready_parts.
/// dart`'s own `Stack`; this file is built and tested on its own, ready for
/// that row to drop in beside `MeasurementReportOverlay`.
library;

import 'package:flutter/material.dart';

/// The gradient bar's own size, `screen 13`'s own "140×8".
const double kWeightLegendWidth = 140;
const double kWeightLegendHeight = 8;

/// The five stops as sRGB `Color`s, for a widget to paint directly — a
/// `LinearGradient` here wants exactly the hex the design named, none of
/// `weight_gradient.dart`'s own sRGB→linear step, which is there for a vertex
/// buffer and not for a screen.
const List<Color> kWeightLegendColors = <Color>[
  Color(0xFF2A3A7A),
  Color(0xFF4AA3FF),
  Color(0xFF7EE081),
  Color(0xFFFFB347),
  Color(0xFFFF3B5C),
];

/// "0 [gradient bar] 1", pinned to the viewport's top-right corner the way
/// `MeasurementReportOverlay` pins its own card to the top-left — a direct
/// child of the `Stack` that holds the viewport, not a widget a caller wraps
/// in `Positioned` itself.
class WeightLegend extends StatelessWidget {
  const WeightLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 12,
      right: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('0', style: TextStyle(fontSize: 11, color: scheme.outline)),
              const SizedBox(width: 10),
              Container(
                width: kWeightLegendWidth,
                height: kWeightLegendHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kWeightLegendHeight / 2),
                  gradient: const LinearGradient(colors: kWeightLegendColors),
                ),
              ),
              const SizedBox(width: 10),
              Text('1', style: TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
