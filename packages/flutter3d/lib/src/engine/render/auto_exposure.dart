/// Exposure decided by the frame rather than by a number in the settings.
///
/// Three pieces, none of which needs a device. [AutoExposureSettings] is the
/// knob; [ExposureMeter] turns the bytes the luminance pass wrote into one
/// brightness; [ExposureAdapter] moves the exposure towards what that
/// brightness asks for, at a rate rather than at once, and holds the value the
/// composite reads. The renderer owns the pass and the readback and calls the
/// two in turn; everything about *what* the exposure should be is here, where
/// a test can hand it bytes and read the answer.
///
/// **Off by default.** Every golden in the repository is recorded at the
/// setting's own exposure, and a meter that switched itself on would re-record
/// all of them in a commit about something else. A game turns it on; the
/// dungeon does.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// How the frame's own brightness decides its exposure.
final class AutoExposureSettings {
  const AutoExposureSettings({
    this.enabled = false,
    this.minExposure = 0.25,
    this.maxExposure = 8.0,
    this.speedUp = 1.5,
    this.speedDown = 3.0,
    this.target = 0.18,
    this.lowPercentile = 0.8,
    this.highPercentile = 0.98,
  }) : assert(minExposure > 0.0 && maxExposure >= minExposure),
       assert(
         lowPercentile >= 0.0 &&
             highPercentile <= 1.0 &&
             lowPercentile < highPercentile,
       );

  final bool enabled;

  /// Where the exposure stops, whatever the frame says.
  ///
  /// Two limits rather than none, because a meter with none is a meter that
  /// turns a black frame — a loading screen, a fade, the first frame before
  /// anything has drawn — into a blown-out one the moment something appears.
  /// The defaults span five stops either side of the engine's own 1.6.
  final double minExposure;
  final double maxExposure;

  /// How quickly the exposure *rises*, once the scene has gone dark, and how
  /// quickly it *falls* once the scene has gone bright, per second.
  ///
  /// Each is a rate: a fraction `1 − e^(−speed·dt)` of the remaining distance
  /// in stops is covered each frame, so at 1 about two thirds of the gap
  /// closes in a second and at 3 nearly all of it does. Falling faster than
  /// rising is what an eye does — walking out into daylight stings for a
  /// moment and is over; walking into a cellar takes a while — and it is also
  /// the safe side, since an over-bright frame clips and an over-dark one
  /// merely waits. `double.infinity` is allowed and means at once, which is
  /// what a frame that has to be the same every time it is drawn asks for.
  final double speedUp;
  final double speedDown;

  /// What the metered brightness is exposed *to*, in linear light before the
  /// tone curve: 0.18 is the photographer's middle grey, and lands where the
  /// Neutral tone mapper leaves midtones alone.
  final double target;

  /// Which of the frame's texels count, as fractions of the histogram.
  ///
  /// The bright end of the picture rather than all of it. Darkness is most of
  /// most frames — a far wall, the clear colour, a corridor no torch reaches —
  /// and a plain mean of every texel would meter that and push whatever is
  /// lit past white. So the darkest four fifths and the brightest fiftieth are
  /// left out, and the band between them — the lit walls, the thing the
  /// camera is pointed at — is what the exposure is set from. Walk into a
  /// corridor with nothing lit in view and the band is dim, so the exposure
  /// climbs and the corridor can be seen; that is the whole of the effect.
  final double lowPercentile;
  final double highPercentile;

  AutoExposureSettings copyWith({
    bool? enabled,
    double? minExposure,
    double? maxExposure,
    double? speedUp,
    double? speedDown,
    double? target,
    double? lowPercentile,
    double? highPercentile,
  }) => AutoExposureSettings(
    enabled: enabled ?? this.enabled,
    minExposure: minExposure ?? this.minExposure,
    maxExposure: maxExposure ?? this.maxExposure,
    speedUp: speedUp ?? this.speedUp,
    speedDown: speedDown ?? this.speedDown,
    target: target ?? this.target,
    lowPercentile: lowPercentile ?? this.lowPercentile,
    highPercentile: highPercentile ?? this.highPercentile,
  );
}

/// The other end of `luminance.frag`'s encoding, and the arithmetic that
/// turns a texture of stops into one exposure.
abstract final class ExposureMeter {
  /// The luminance target's side, in texels. Small enough that a readback of
  /// it is sixteen kilobytes, large enough that a percentile means something.
  static const int size = 64;

  /// The stop a byte of zero stands for, and how many stops the byte spans.
  ///
  /// Minus ten to plus six: a thousandth of a unit of light up to sixty-four
  /// units, in sixteenths of a stop. The shader clamps outside it, which is
  /// why the floor sits well below anything a lit scene reaches — a byte of
  /// zero is "black", not "dark".
  static const double floorStops = -10.0;
  static const double rangeStops = 16.0;

  /// The stop a byte of [encoded] stands for.
  static double stopsOf(int encoded) =>
      floorStops + encoded / 255.0 * rangeStops;

  /// The mean brightness, in stops, of the texels between the two
  /// percentiles of [luminance] — the bytes the pass wrote, red channel read,
  /// one per texel.
  ///
  /// A histogram of the byte values, walked from dark to bright: the texels
  /// below [lowPercentile] and above [highPercentile] are dropped, and what is
  /// left is averaged. Bytes rather than floats because that is what a
  /// readback hands over, and the histogram has exactly as many bins as a
  /// byte has values, so nothing here rounds twice.
  static double meanStops(
    ByteData luminance, {
    double lowPercentile = 0.8,
    double highPercentile = 0.98,
  }) {
    final total = luminance.lengthInBytes ~/ 4;
    if (total == 0) return floorStops;

    final counts = List<int>.filled(256, 0);
    for (var i = 0; i < total; i++) {
      counts[luminance.getUint8(i * 4)]++;
    }

    final from = (total * lowPercentile).floor();
    final to = (total * highPercentile).ceil();
    var seen = 0;
    var sum = 0.0;
    var used = 0;
    for (var value = 0; value < 256; value++) {
      final count = counts[value];
      if (count == 0) continue;
      final start = seen;
      final end = seen + count;
      seen = end;
      final int take = math.min<int>(end, to) - math.max<int>(start, from);
      if (take <= 0) continue;
      sum += take * stopsOf(value);
      used += take;
    }
    if (used == 0) {
      // A band so narrow it fell between two bins: the whole frame, then.
      for (var value = 0; value < 256; value++) {
        sum += counts[value] * stopsOf(value);
      }
      used = total;
    }
    return sum / used;
  }

  /// The exposure that puts a scene whose brightness is [meanStops] at
  /// [target] — a linear multiplier, the same quantity `RenderSettings.exposure`
  /// is.
  static double exposureFor(double meanStops, double target) =>
      target / math.pow(2.0, meanStops);
}

/// The exposure as it stands, and where it is going.
///
/// One per renderer, and mutable on purpose: this is the one piece of the
/// frame that is a running value rather than a fact about this frame. The
/// meter reads a frame that is already gone — a readback answers a frame or
/// two later — and the adapter is what turns that into something the frame
/// being drawn can use without lurching.
final class ExposureAdapter {
  ExposureAdapter({required double initial}) : value = initial;

  /// The exposure the composite uses now.
  double value;

  /// What the last metered frame asked for, or null before any frame has been
  /// metered.
  double? get target => _target;
  double? _target;

  /// Reads a metered frame and decides where the exposure should go.
  ///
  /// Clamped here rather than in [step], so the target itself is honest about
  /// the limits and a frame that asks for more than the ceiling reads back as
  /// the ceiling.
  void meter(ByteData luminance, AutoExposureSettings settings) {
    final stops = ExposureMeter.meanStops(
      luminance,
      lowPercentile: settings.lowPercentile,
      highPercentile: settings.highPercentile,
    );
    _target = ExposureMeter.exposureFor(
      stops,
      settings.target,
    ).clamp(settings.minExposure, settings.maxExposure);
  }

  /// Moves [value] towards the target by [dt] seconds' worth of adaptation.
  ///
  /// In stops, not in the multiplier: halving and doubling the exposure are
  /// the same size of step to an eye, and a lerp on the multiplier would make
  /// the climb out of a dark room ten times faster than the fall into it.
  void step(double dt, AutoExposureSettings settings) {
    final wanted = _target;
    if (wanted == null) {
      value = value.clamp(settings.minExposure, settings.maxExposure);
      return;
    }
    final current = math.log(value) / math.ln2;
    final goal = math.log(wanted) / math.ln2;
    final speed = goal > current ? settings.speedUp : settings.speedDown;
    // A rate of infinity is "at once", and `0 · ∞` is not a number, so the
    // case is named rather than left to the arithmetic.
    final fraction = speed.isInfinite
        ? 1.0
        : 1.0 - math.exp(-math.max(dt, 0.0) * math.max(speed, 0.0));
    value = math
        .pow(2.0, current + (goal - current) * fraction)
        .toDouble()
        .clamp(settings.minExposure, settings.maxExposure);
  }
}
