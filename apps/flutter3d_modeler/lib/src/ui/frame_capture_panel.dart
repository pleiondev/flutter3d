/// `gfx-70n`'s own half of the editor: a captured frame, pass by pass.
///
/// **What the metrics card next to it cannot do.** `MetricsOverlay` lists what
/// each pass cost, which answers "which pass is slow". It cannot answer "why is
/// the frame black", and no amount of timing will: a pass that ran in the usual
/// microseconds and wrote nothing looks exactly like one that worked. This
/// lists what each pass read, what it wrote, and whether what it wrote came
/// back black — which is the chain a reader walks from the finished picture
/// back to the pass that broke it.
///
/// A dumb widget over a `FrameCapture`, the same discipline every panel in this
/// app keeps: the screen decides when to take one and this only draws it. The
/// pixels themselves are not drawn here — a thumbnail per resource per pass is
/// a `ui.Image` decode per tile and a real piece of work — and `captureBlack`
/// is the one thing read off them, because a black output is what sends
/// somebody to a capture in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show CapturedPass, FrameCapture;

import '../../../l10n/app_localizations.dart';
import 'metrics_overlay.dart' show kMetricsOverlayBackground;

/// The capture panel, in the state the screen has it in.
class FrameCapturePanel extends StatelessWidget {
  const FrameCapturePanel({
    super.key,
    required this.capture,
    required this.waiting,
    required this.onCapture,
  });

  /// The last capture taken, or null when none has been.
  final FrameCapture? capture;

  /// Whether a capture has been asked for and has not answered.
  final bool waiting;

  final VoidCallback onCapture;

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
    final TextStyle quiet = style.copyWith(color: Colors.white70);
    // Amber rather than red: a black output is where to look, not a verdict.
    // The shadow atlases are legitimately black in a scene with no casters.
    final TextStyle alarm = style.copyWith(color: const Color(0xFFFFC46B));

    final FrameCapture? taken = capture;

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
            Text(l.captureTitle, style: quiet),
            const SizedBox(height: 4),
            TextButton(
              onPressed: waiting ? null : onCapture,
              child: Text(waiting ? l.captureWaiting : l.captureTake),
            ),
            if (taken == null)
              Text(l.captureEmpty, style: quiet)
            else
              for (final CapturedPass pass in taken.passes) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  pass.active
                      ? l.capturePassLine(pass.name, '${pass.images.length}')
                      : l.captureInactive(pass.name),
                  style: pass.active ? style : quiet,
                ),
                if (pass.reads.isNotEmpty)
                  Text(l.captureReads(pass.reads.join(', ')), style: quiet),
                if (pass.writes.isNotEmpty)
                  Text(l.captureWrites(pass.writes.join(', ')), style: quiet),
                for (final image in pass.images)
                  if (image.refused != null)
                    Text(
                      l.captureRefused(image.resource, image.refused!),
                      style: quiet,
                    )
                  else if (image.isBlack)
                    Text(l.captureBlack(image.resource), style: alarm),
              ],
          ],
        ),
      ),
    );
  }
}
