import 'dart:typed_data';

/// What two frames of the same size disagree about.
///
/// **Four places had counted this by hand**, with three different ideas of how
/// far apart two channels have to be before a pixel counts as changed: eight in
/// the cross-backend comparison, twelve in two games' frame tests, and two in
/// the editor's. Nothing wrong with three answers — a golden comparison and a
/// "did the picture move at all" check are asking different questions — but
/// three answers to a question nobody wrote down is how a threshold ends up
/// being whatever the file it was copied from happened to say.
///
/// The default is eight, which is what `tool/golden.sh` uses, so a comparison
/// that says nothing about its threshold means the same thing the goldens do.
final class FrameDifference {
  const FrameDifference({
    required this.differing,
    required this.pixels,
    required this.worstChannel,
  });

  /// How many pixels differ by more than the threshold.
  final int differing;

  /// How many pixels there were, so a share can be taken without the caller
  /// dividing by four again.
  final int pixels;

  /// The largest single-channel distance anywhere in the frame.
  ///
  /// The number that tells a reader whether a comparison passed comfortably or
  /// only just: two frames can differ in one per cent of their pixels by one
  /// step each, or in one per cent by two hundred, and only one of those is a
  /// rounding wobble.
  final int worstChannel;

  double get percent => pixels == 0 ? 0.0 : 100.0 * differing / pixels;

  @override
  String toString() => '$differing of $pixels differ '
      '(${percent.toStringAsFixed(3)}%), worst channel $worstChannel';
}

/// Compares two RGBA frames of the same size.
///
/// Alpha is ignored, deliberately: what is being compared is a picture, and a
/// backend that writes a different alpha into an opaque frame has not drawn
/// anything a person would see.
///
/// Throws if the two are different sizes rather than comparing what they have
/// in common, because two frames of different sizes is a broken test rather
/// than a failing one.
FrameDifference compareFrames(
  Uint8List a,
  Uint8List b, {
  int channel = 8,
}) {
  if (a.length != b.length) {
    throw ArgumentError(
      'the two frames are different sizes: ${a.length} and ${b.length} bytes',
    );
  }
  var differing = 0;
  var worst = 0;
  for (var i = 0; i < a.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 3; c++) {
      final delta = (a[i + c] - b[i + c]).abs();
      if (delta > d) d = delta;
    }
    if (d > channel) differing++;
    if (d > worst) worst = d;
  }
  return FrameDifference(
    differing: differing,
    pixels: a.length ~/ 4,
    worstChannel: worst,
  );
}

/// How many pixels differ, for a caller that only wants the count.
int differingPixels(Uint8List a, Uint8List b, {int channel = 8}) =>
    compareFrames(a, b, channel: channel).differing;
