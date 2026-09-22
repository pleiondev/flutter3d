/// What one pass actually did to a frame — `gfx-42n`.
///
/// **Two frames that differ by exactly one pass, differenced exactly.**
/// `RenderSettings.disabledPasses` produces the pair from one settings value,
/// and a deterministic software rasteriser makes the difference arithmetic
/// rather than a screenshot comparison. Both halves are needed, which is why
/// this is a thing this engine can answer and the engines it is measured
/// against cannot: a per-pass switch without a reference implementation gives
/// two pictures somebody has to eyeball, and a reference implementation
/// without the switch gives no pair to difference.
///
/// The question it answers is the one asked of every effect that ships off by
/// default: *what is this actually doing to my picture*. Not "is it on" and
/// not "does it look better", but how many pixels, how far, and where.
library;

import 'dart:typed_data';

/// Where a difference lives in the frame, in pixels.
typedef ChangedBounds = ({int left, int top, int right, int bottom});

/// The difference between two frames of the same size.
final class PassContribution {
  const PassContribution({
    required this.changedPixels,
    required this.totalPixels,
    required this.worstChannelDelta,
    required this.meanChannelDelta,
    required this.bounds,
  });

  /// How many pixels differ at all.
  final int changedPixels;

  /// How many there were, so [changedPixels] can be read as a share without
  /// the caller having to know the frame's size.
  final int totalPixels;

  /// The largest single-channel difference anywhere, 0 to 255.
  ///
  /// **Reported beside [changedPixels] because the two answer different
  /// questions and either alone misleads.** A pass that moves every pixel by
  /// one is a rounding; a pass that moves forty pixels to black is a hole in
  /// the picture. A count cannot tell those apart and neither can a maximum.
  final int worstChannelDelta;

  /// The mean difference over the pixels that changed — 0 when none did.
  ///
  /// Over the *changed* pixels rather than over the frame: an effect confined
  /// to a corner would otherwise report a mean near zero however strong it
  /// is, which says more about the frame's size than about the effect.
  final double meanChannelDelta;

  /// The rectangle the change is confined to, or null when nothing changed.
  ///
  /// What catches an effect leaking somewhere it should not be: a contact
  /// shadow that reaches the frame's edge, a glow that wraps. Inclusive on
  /// every side.
  final ChangedBounds? bounds;

  /// Whether the two frames are the same picture.
  bool get isIdentical => changedPixels == 0;

  /// The share of the frame that moved, from 0 to 1.
  double get changedFraction =>
      totalPixels == 0 ? 0.0 : changedPixels / totalPixels;

  @override
  String toString() =>
      'PassContribution($changedPixels/$totalPixels pixels, '
      'worst $worstChannelDelta, mean '
      '${meanChannelDelta.toStringAsFixed(2)}, bounds $bounds)';
}

/// Differences two RGBA frames of [width] by [height].
///
/// Alpha is deliberately not compared. Every frame this engine hands back is
/// opaque, so a difference there would be a bug in the readback rather than a
/// contribution from a pass, and counting it would put a constant under every
/// measurement.
PassContribution contributionBetween(
  ByteData without,
  ByteData with_, {
  required int width,
  required int height,
}) {
  final pixels = width * height;
  if (without.lengthInBytes != pixels * 4 ||
      with_.lengthInBytes != pixels * 4) {
    throw ArgumentError(
      'the two frames must both be $width x $height RGBA — got '
      '${without.lengthInBytes} and ${with_.lengthInBytes} bytes, and a '
      'difference between frames of different sizes is not a contribution',
    );
  }

  var changed = 0;
  var worst = 0;
  var sum = 0;
  var left = width;
  var top = height;
  var right = -1;
  var bottom = -1;

  for (var i = 0; i < pixels; i++) {
    final at = i * 4;
    var most = 0;
    for (var c = 0; c < 3; c++) {
      final delta = (without.getUint8(at + c) - with_.getUint8(at + c)).abs();
      if (delta > most) most = delta;
    }
    if (most == 0) continue;

    changed++;
    sum += most;
    if (most > worst) worst = most;

    final x = i % width;
    final y = i ~/ width;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }

  return PassContribution(
    changedPixels: changed,
    totalPixels: pixels,
    worstChannelDelta: worst,
    meanChannelDelta: changed == 0 ? 0.0 : sum / changed,
    bounds: changed == 0
        ? null
        : (left: left, top: top, right: right, bottom: bottom),
  );
}
