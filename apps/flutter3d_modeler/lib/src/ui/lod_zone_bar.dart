/// The 96-tall strip a level of detail's screen-size thresholds are set
/// against — `pro-lod-04`'s own row, and the literal "widget test on the
/// slider" its acceptance asks for.
///
/// **A dumb, callback-driven strip, the same shape `NumberField` and
/// `operation_card.dart`'s own slider already are.** [LodZoneBar] never
/// writes to [LodZoneBar.lods] itself — every drag calls
/// [LodZoneBar.onThresholdChanged] and waits for a new [LodSpec] list to come
/// back down, the same round trip a `SetLodRatio`-shaped command would carry
/// through `ModelHistory`. `amend`-on-every-frame is `MoveBy`'s own reasoning
/// in `command.dart`: reporting live while a marker moves, rather than only
/// once it is let go, is what makes the strip feel like it is being dragged
/// rather than typed into.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// Up to how many zones this bar tells apart by eye before two share a
/// colour — the three roles `kModelerScheme` already gives a dark theme,
/// plus outline for whatever falls off the end of that list. Reused rather
/// than invented, so a level of detail's own zone is the same family of
/// colour the rest of the modeller already answers "which one is this" with.
Color _zoneColor(BuildContext context, int lodIndex) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return switch (lodIndex % 4) {
    0 => scheme.primary,
    1 => scheme.tertiary,
    2 => scheme.secondary,
    _ => scheme.outline,
  };
}

/// One 96-tall strip: a coloured zone per level of [lods], each ending where
/// its own [LodSpec.maxScreenFraction] says, and a draggable marker at that
/// edge.
///
/// The axis reads left to right as the screen fraction an object is drawn
/// at, `0` at the left (an object shrunk to nothing) to `1` at the right (an
/// object filling the frame) — [LodSpec.maxScreenFraction]'s own scale,
/// carried straight onto the strip with nothing remapped, so a marker's
/// position on screen is the number it reports.
class LodZoneBar extends StatelessWidget {
  const LodZoneBar({
    super.key,
    required this.lods,
    required this.onThresholdChanged,
  });

  /// One threshold per level, in the same order `ModelObject.lods` holds
  /// them.
  final List<LodSpec> lods;

  /// A marker moved to a new [LodSpec.maxScreenFraction] for [lodIndex],
  /// reported live through the drag rather than only once it ends.
  final void Function(int lodIndex, double maxScreenFraction)
  onThresholdChanged;

  /// Fixed, and the number the plan's own row states.
  static const double height = 96;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(child: _ZoneBands(lods: lods)),
                for (int i = 0; i < lods.length; i++)
                  _Marker(
                    key: ValueKey<int>(i),
                    lodIndex: i,
                    fraction: lods[i].maxScreenFraction.clamp(0.0, 1.0),
                    width: width,
                    color: _zoneColor(context, i),
                    onChanged: onThresholdChanged,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The coloured bands behind the markers, one per level of [lods].
///
/// Built as flex segments between consecutive thresholds rather than
/// absolutely positioned rectangles: a `Row` of `Expanded` children always
/// sums to the strip's own width whatever [lods] holds, where an absolute
/// layout would have to be told separately what to do about the gap before
/// the first threshold and the one after the last.
class _ZoneBands extends StatelessWidget {
  const _ZoneBands({required this.lods});

  final List<LodSpec> lods;

  @override
  Widget build(BuildContext context) {
    if (lods.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      );
    }

    // Coarsest zone (smallest `maxScreenFraction`) first, so the bands are
    // laid out left to right in the same order the axis reads in.
    final List<int> byThreshold = List<int>.generate(lods.length, (i) => i)
      ..sort(
        (int a, int b) =>
            lods[a].maxScreenFraction.compareTo(lods[b].maxScreenFraction),
      );

    final List<Widget> segments = <Widget>[];
    double previousEdge = 0.0;
    for (final int i in byThreshold) {
      final double edge = lods[i].maxScreenFraction.clamp(previousEdge, 1.0);
      final double span = edge - previousEdge;
      if (span > 0) {
        segments.add(
          Expanded(
            flex: (span * 1000).round().clamp(1, 1000),
            child: ColoredBox(
              color: _zoneColor(context, i).withValues(alpha: 0.28),
            ),
          ),
        );
      }
      previousEdge = edge;
    }
    if (previousEdge < 1.0) {
      segments.add(
        Expanded(
          flex: ((1.0 - previousEdge) * 1000).round().clamp(1, 1000),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
          ),
        ),
      );
    }
    return Row(children: segments);
  }
}

/// One draggable marker, at [fraction] of [width] along the strip.
class _Marker extends StatefulWidget {
  const _Marker({
    super.key,
    required this.lodIndex,
    required this.fraction,
    required this.width,
    required this.color,
    required this.onChanged,
  });

  final int lodIndex;
  final double fraction;
  final double width;
  final Color color;
  final void Function(int lodIndex, double maxScreenFraction) onChanged;

  /// How wide the whole handle is, hit area included — big enough for a
  /// finger, the same reasoning `ModelerMetrics.railButton` states for every
  /// other control in this application meant to be pressed rather than read.
  static const double handleWidth = 36;

  @override
  State<_Marker> createState() => _MarkerState();
}

class _MarkerState extends State<_Marker> {
  /// The value this marker reports while a drag is in progress.
  ///
  /// Seeded from [_Marker.fraction] at the start of each drag and moved from
  /// there by every subsequent delta, rather than re-derived from
  /// [_Marker.fraction] on every callback: [LodZoneBar] does not write back
  /// into its own widget synchronously mid-gesture the way `ModelHistory`
  /// does not either, so a marker that trusted the widget's own value on
  /// every frame would answer each delta against the position it started the
  /// whole drag at and undercount it.
  double? _dragFraction;

  void _dragStart(DragStartDetails details) {
    _dragFraction = widget.fraction;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (widget.width <= 0) return;
    final double next =
        ((_dragFraction ?? widget.fraction) + details.delta.dx / widget.width)
            .clamp(0.0, 1.0);
    _dragFraction = next;
    widget.onChanged(widget.lodIndex, next);
  }

  void _dragEnd(DragEndDetails details) {
    _dragFraction = null;
  }

  @override
  Widget build(BuildContext context) {
    final double x = widget.fraction * widget.width;
    return Positioned(
      left: (x - _Marker.handleWidth / 2).clamp(
        0.0,
        (widget.width - _Marker.handleWidth).clamp(0.0, widget.width),
      ),
      top: 0,
      bottom: 0,
      width: _Marker.handleWidth,
      child: Semantics(
        label: 'LOD ${widget.lodIndex} threshold',
        value: '${(widget.fraction * 100).round()}%',
        slider: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          child: Center(
            child: Container(
              width: 8,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black26),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
