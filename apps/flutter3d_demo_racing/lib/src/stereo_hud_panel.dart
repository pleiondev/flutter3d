/// `ls-x-02`'s own visor: the same [RaceHud] the flat screen draws as an
/// overlay, drawn instead on a `WidgetSurface` in front of the stereo
/// camera — the showcase this scenario names, Flutter widgets on a 3D
/// surface in the most demanding redraw context this repository has.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'hud.dart';
import 'race_readout.dart';

/// Reads whatever [reading] holds — null before a race exists to read, the
/// same "nothing to show yet" the flat overlay's own `if (_race != null &&
/// _started)` guard already keeps. Redrawn through [ValueListenableBuilder]
/// rather than a `setState` rebuild: a `WidgetSurface`'s own child is fixed
/// at construction (`WidgetSurfacePipeline`'s own doc comment), so this
/// widget tree is built once and ticks itself from here on rather than
/// being swapped for a new one.
final class StereoHud extends StatelessWidget {
  const StereoHud({super.key, required this.reading, required this.issueOf});

  final ValueListenable<RaceReadout?> reading;

  /// Read fresh every time [reading] notifies rather than its own
  /// [ValueListenable] — an issue message changes at the same moment a
  /// readout does in the flat overlay's own single `build()` call, so a
  /// second notifier would only double the bookkeeping for no new fidelity.
  final String? Function() issueOf;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RaceReadout?>(
    valueListenable: reading,
    builder: (context, readout, _) => readout == null
        ? const SizedBox.shrink()
        : RaceHud(readout: readout, issue: issueOf()),
  );
}
