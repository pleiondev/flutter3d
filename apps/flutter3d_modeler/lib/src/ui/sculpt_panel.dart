/// Screen 08 — `pro-sc-08` and `ui-29`: the sculpting layout, which is the
/// one layout in this application with no rail and no properties panel.
///
/// **Panel-free, because a sculptor is looking at the model.** Every other
/// mode is about a document — a list of objects, a stack of modifiers, a
/// table of bones — and a panel down the side is where those live. Sculpting
/// is one surface and one brush, and the two controls it needs (which brush,
/// how big) are the only things that should be between a person and the
/// picture. So [SculptChrome] floats a 48-wide palette and a 250-wide card
/// over the viewport rather than docking anything beside it, and the shell
/// is asked to fold the rail and the panel away entirely.
///
/// **The palette arms rail tools, it does not hold a brush of its own.**
/// Pressing `Clay` runs the same `sculpt.clay` the keyboard and an agent's
/// own `ui.setTool` run — one armed tool, one place it lives, the same rule
/// `WeightPaintPanel`'s own mode segments already keep.
///
/// **Subdivide is a command, not a slider.** The hand-off's screen 08 has a
/// "brush density" control on it; B9 (closed 2026-09-09) chose
/// multiresolution over dynamic topology, and a multires stack has levels
/// rather than a density — so the control is a button that adds one, and
/// screen 08's design is amended to say so. See the plan's own `pro-sc-08`
/// row.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show BrushFalloff, BrushKind;

import 'theme.dart';

/// The brush palette's own width — `ui-29`'s own 48, which is also
/// `InputPolicy.touchTapTarget`: this strip is the one piece of chrome a
/// person reaches for mid-stroke, on a tablet as much as at a desk.
const double kSculptPaletteWidth = 48;

/// The settings card's own width — `ui-29`'s own 250, the same number
/// [ModelerMetrics.propertiesMin] gives the panel this layout does not have.
const double kSculptCardWidth = 250;

/// The brush cursor's own diameter in logical pixels, and the radius a
/// stroke starts at — `view-21`'s own ⌀140.
///
/// **A number a person changes, not a number they discover.** A brush that
/// opened at a few pixels would read as broken on the first stroke over a
/// dense mesh — nothing visible happens — and one that opened at half the
/// screen would swallow the model. 140 is a mark you can see land.
const double kSculptCursorDiameter = 140;

/// The eight brushes, in the order the palette shows them.
///
/// Build-up first (draw, clay, inflate), then the ones that take away or even
/// out (smooth, flatten), then the ones that move what is there (grab, pinch,
/// crease) — which is the order a person works in, not alphabetical.
const List<BrushKind> kSculptBrushes = <BrushKind>[
  BrushKind.draw,
  BrushKind.clay,
  BrushKind.inflate,
  BrushKind.smooth,
  BrushKind.flatten,
  BrushKind.grab,
  BrushKind.pinch,
  BrushKind.crease,
];

/// The icon each brush shows on the palette.
IconData sculptBrushIcon(BrushKind kind) => switch (kind.name) {
  'clay' => Icons.layers_outlined,
  'smooth' => Icons.blur_on_outlined,
  'flatten' => Icons.horizontal_rule_outlined,
  'inflate' => Icons.bubble_chart_outlined,
  'grab' => Icons.pan_tool_outlined,
  'pinch' => Icons.compress_outlined,
  'crease' => Icons.change_history_outlined,
  _ => Icons.brush_outlined,
};

/// What each brush is called on its own tooltip.
String sculptBrushLabel(BrushKind kind) => switch (kind.name) {
  'clay' => 'Clay',
  'smooth' => 'Smooth',
  'flatten' => 'Flatten',
  'inflate' => 'Inflate',
  'grab' => 'Grab',
  'pinch' => 'Pinch',
  'crease' => 'Crease',
  _ => 'Draw',
};

/// The 48-wide strip of brushes.
class SculptPalette extends StatelessWidget {
  const SculptPalette({super.key, required this.armed, required this.onBrush});

  /// Which brush the armed rail tool names.
  final BrushKind armed;

  /// A brush was pressed — the caller arms that brush's own rail tool.
  final ValueChanged<BrushKind> onBrush;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Material(
      color: colours.surfaceContainerHigh.withValues(alpha: 0.92),
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: SizedBox(
        width: kSculptPaletteWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final BrushKind kind in kSculptBrushes)
              Tooltip(
                message: sculptBrushLabel(kind),
                child: IconButton(
                  key: ValueKey<String>('sculptBrush-${kind.name}'),
                  isSelected: kind == armed,
                  selectedIcon: Icon(
                    sculptBrushIcon(kind),
                    color: colours.primary,
                  ),
                  icon: Icon(sculptBrushIcon(kind)),
                  onPressed: () => onBrush(kind),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The 250-wide settings card: how the brush behaves, and the one command
/// this mode offers.
class SculptPanel extends StatelessWidget {
  const SculptPanel({
    super.key,
    required this.radius,
    required this.onRadius,
    required this.strength,
    required this.onStrength,
    required this.falloff,
    required this.onFalloff,
    required this.symmetryX,
    required this.onSymmetryX,
    required this.onSubdivide,
    this.faces,
    this.subdivideRefusal,
  });

  /// In logical pixels — the diameter of the cursor, and what a stroke's own
  /// `radiusPixels` reads.
  final double radius;
  final ValueChanged<double> onRadius;

  /// 0 to 1, `SculptStroke.strength`'s own range.
  final double strength;
  final ValueChanged<double> onStrength;

  final BrushFalloff falloff;
  final ValueChanged<BrushFalloff> onFalloff;

  final bool symmetryX;
  final ValueChanged<bool> onSymmetryX;

  /// Adds a subdivision level to the mesh being sculpted.
  final VoidCallback onSubdivide;

  /// How many faces the mesh has now — what tells a person whether the next
  /// Subdivide is the one that makes the machine stop answering. Null before
  /// there is a mesh to count.
  final int? faces;

  /// Why Subdivide is not available, when it is not — a bound skeleton, a
  /// set of shape keys, or no mesh at all. The button is disabled and says
  /// this instead of doing nothing quietly.
  final String? subdivideRefusal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colours = theme.colorScheme;
    return Material(
      color: colours.surfaceContainerHigh.withValues(alpha: 0.92),
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: SizedBox(
        width: kSculptCardWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel('Brush'),
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
              const SizedBox(height: 8),
              SegmentedButton<BrushFalloff>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<BrushFalloff>>[
                  ButtonSegment<BrushFalloff>(
                    value: BrushFalloff.linear,
                    label: Text('Linear'),
                  ),
                  ButtonSegment<BrushFalloff>(
                    value: BrushFalloff.smooth,
                    label: Text('Smooth'),
                  ),
                  ButtonSegment<BrushFalloff>(
                    value: BrushFalloff.sharp,
                    label: Text('Sharp'),
                  ),
                ],
                selected: <BrushFalloff>{falloff},
                onSelectionChanged: (Set<BrushFalloff> picked) =>
                    onFalloff(picked.first),
              ),
              CheckboxListTile(
                key: const ValueKey<String>('sculptSymmetryCheckbox'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Symmetry (X)', style: theme.textTheme.bodySmall),
                value: symmetryX,
                onChanged: (bool? to) => onSymmetryX(to ?? false),
              ),
              SectionLabel('Surface'),
              if (faces != null)
                Text('$faces faces', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              // An empty message shows no tooltip at all, which is what a
              // button with nothing wrong with it should have.
              Tooltip(
                message: subdivideRefusal ?? '',
                child: FilledButton.tonalIcon(
                  key: const ValueKey<String>('sculptSubdivide'),
                  onPressed: subdivideRefusal == null ? onSubdivide : null,
                  icon: const Icon(Icons.grid_4x4_outlined),
                  label: const Text('Subdivide'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The whole sculpting layout: the viewport with the palette and the card
/// floating over it, and nothing docked beside either.
class SculptChrome extends StatelessWidget {
  const SculptChrome({
    super.key,
    required this.viewport,
    required this.palette,
    required this.panel,
  });

  final Widget viewport;
  final Widget palette;
  final Widget panel;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned.fill(child: viewport),
      Positioned(left: 8, top: 8, bottom: 8, child: Center(child: palette)),
      Positioned(right: 8, top: 8, child: panel),
    ],
  );
}
