/// `anim-24`'s own measurement report, drawn over the top-left corner of the
/// viewport while one is on.
library;

import 'package:flutter/material.dart';

/// The measurement report overlay: a monospace card pinned to the viewport's
/// top-left corner.
class MeasurementReportOverlay extends StatelessWidget {
  const MeasurementReportOverlay({super.key, required this.said});

  /// The report's own text, already assembled.
  final String said;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 12,
    top: 12,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          said,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: <String>['Courier'],
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    ),
  );
}
