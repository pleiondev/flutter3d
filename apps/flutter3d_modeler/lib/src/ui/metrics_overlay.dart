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
library;

import 'package:flutter/material.dart';

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
  });

  final double fps;
  final int drawCalls;
  final int triangles;
  final int bones;

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
          ],
        ),
      ),
    );
  }
}
