/// `S9`'s own HUD: fps, draw calls, triangles and bones, pinned over the
/// top-right corner of screen 19's preview — the same "a card over the
/// picture" shape `measurement_report_overlay.dart` already draws for the
/// top-left corner, at the hand-over's own `rgba(11, 14, 15, 0.72)`.
///
/// A dumb widget over four numbers, the same discipline every panel in this
/// app keeps: `GamePreviewScreen` decides what they are — reading a
/// `FrameResult` for [drawCalls]/[triangles], a rolling average of its own
/// frame times for [fps], and `ProfileBudgetReport.joints.used` for [bones],
/// the same number `BudgetBars`' own joints row reads — and this only draws
/// them.
///
/// **[passes] is `gfx-01n`'s own half.** Four numbers say the frame got
/// slower; they do not say which pass did it, and "the frame is up twelve
/// draws" reads the same whether the shadow map gained a cascade or somebody
/// added an overlay. `FrameResult.passes` answers per pass, so the card
/// lists them under the totals — and lists nothing when the renderer handed
/// back an empty list, which is what a card over a picture should do with a
/// section it has nothing to put in.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show FramePass;

import '../../../l10n/app_localizations.dart';
import 'status_line.dart' show grouped;

/// The card's own background — the hand-over's `rgba(11, 14, 15, 0.72)`,
/// `0xB8` being `0.72 × 255` rounded.
const Color kMetricsOverlayBackground = Color(0xB80B0E0F);

/// Screen 19's own fps/draw-calls/triangles/bones card.
class MetricsOverlay extends StatelessWidget {
  const MetricsOverlay({
    super.key,
    required this.fps,
    required this.drawCalls,
    required this.triangles,
    required this.bones,
    this.passes = const <FramePass>[],
  });

  final double fps;
  final int drawCalls;
  final int triangles;
  final int bones;

  /// What each pass of the frame cost, in the order it ran. Empty hides the
  /// section rather than showing an empty heading.
  final List<FramePass> passes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    const TextStyle style = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      fontFamily: 'monospace',
      fontFamilyFallback: <String>['Courier'],
    );
    // The heading is the same face a shade quieter, so the breakdown reads as
    // a section of the card rather than as four more totals.
    final TextStyle heading = style.copyWith(color: Colors.white70);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMetricsOverlayBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.metricsFps(fps.round()), style: style),
            Text(l.metricsDrawCalls(grouped(drawCalls)), style: style),
            Text(l.metricsTriangles(grouped(triangles)), style: style),
            Text(l.metricsBones(grouped(bones)), style: style),
            if (passes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(l.metricsPasses, style: heading),
              for (final FramePass pass in passes)
                Text(
                  l.metricsPassLine(
                    pass.name,
                    (pass.micros / 1000).toStringAsFixed(2),
                    grouped(pass.drawCalls),
                    grouped(pass.triangles),
                  ),
                  style: style,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
