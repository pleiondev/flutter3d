/// A strip showing how much of a simulation bake is actually cached —
/// `pro-sim-03`'s own "полоса кэша".
///
/// **Presentational only, the same split every other control in this shell
/// keeps.** `SimulationCache.coverage` in `flutter3d_model_core` is the pure
/// number this reads; nothing here knows about a `SimulationCache`, a
/// `BakeSimulationCommand`, or where either one lives — the same way
/// `JobButton` reads a bare `double?` rather than a `Job` itself.
library;

import 'package:flutter/material.dart';

/// A thin horizontal bar, filled from the left by [bakedFrameCount] out of
/// [targetFrameCount] — an empty strip for a bake nobody has started, and a
/// fully filled one once every target frame is cached.
final class SimulationCacheStrip extends StatelessWidget {
  const SimulationCacheStrip({
    super.key,
    required this.bakedFrameCount,
    required this.targetFrameCount,
  }) : assert(
         bakedFrameCount >= 0,
         'a negative frame count is not a coverage this strip can draw',
       );

  /// How many frames a `SimulationCache` actually holds — its own
  /// `frameCount`.
  final int bakedFrameCount;

  /// How many frames the bake is aiming for — a `BakeSimulationCommand`'s
  /// own `frameCount`.
  final int targetFrameCount;

  /// [bakedFrameCount] out of [targetFrameCount], from 0 to 1 — the same
  /// clamp `SimulationCache.coverage` applies, kept here too since this
  /// widget takes the two counts apart rather than a cache and a target
  /// together.
  double get _coverage {
    if (targetFrameCount <= 0) return bakedFrameCount > 0 ? 1.0 : 0.0;
    return (bakedFrameCount / targetFrameCount).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverage = _coverage;
    return Semantics(
      label:
          'Simulation cache: $bakedFrameCount of $targetFrameCount frames baked',
      value: '${(coverage * 100).round()}%',
      child: Tooltip(
        message: '$bakedFrameCount / $targetFrameCount frames cached',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Stack(
                  children: <Widget>[
                    ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: SizedBox.expand(),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: constraints.maxWidth * coverage,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
