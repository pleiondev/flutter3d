/// The camera's exposure as a photographer states it — `B6.22`.
///
/// `RenderSettings.exposure` is a multiplier, and a multiplier says nothing
/// to somebody who knows that a sunny afternoon is f/16 at a hundredth of a
/// second. [PhysicalCamera] is the same number stated as an aperture, a
/// shutter and a sensitivity, with the exposure value they make, and a light
/// meter that turns the physical sky's illuminance into one.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'physical_sky.dart';

/// An aperture, a shutter time and a sensitivity, and the exposure they make.
///
/// **The default camera draws the frame this engine always drew.** f/4 at a
/// sixtieth of a second and ISO 100 is the *reference camera*: its exposure
/// value, `log2(4² × 60) ≈ 9.907`, is the one `RenderSettings.exposure` is
/// stated at. A camera one stop slower — f/4 at a thirtieth — exposes twice
/// as much, and so on, so [exposureScale] is `2^(referenceEv100 − ev100)`
/// and nothing else: exactly one for the reference camera, which is why the
/// goldens did not move when the physical camera became the default.
///
/// **What the numbers mean in light.** The renderer exposes with the
/// saturation-based model (ISO 12232): the brightest luminance a camera
/// records is `1.2 × 2^EV100` candela per square metre, and the exposure
/// multiplier is its inverse. Holding the reference camera to the default
/// multiplier of 1.6 fixes the engine's photometric scale: one unit of scene
/// luminance is 1.6 × 1.2 × 960 = 1843.2 cd/m² (`Photometric.legacyNits`)
/// — and, since a white Lambertian surface shows `E/π` of an illuminance E,
/// one unit of illuminance is π times that, about 5790.6 lux
/// (`Photometric.legacyUnit`). Those are the renderer's own business since
/// 1.0: everything the API takes is in lux, candela or nits, and the
/// renderer converts. The physical sky's default sun is about 116 000 lux
/// before the air, which is the real sun's order.
///
/// **A light meter, not just a dial.** [ev100ForIlluminance] is an incident
/// meter's reading (calibration constant 250): EV100 = log2(E / 2.5). Fed
/// [PhysicalSky.illuminanceLux], it says what a camera standing in that
/// light would be set to, and [PhysicalCamera.metered] makes that camera,
/// solving for the shutter at a chosen aperture.
///
/// Auto exposure still decides the exposure while it is on: the meter's
/// answer replaces the camera's, as a camera on automatic chooses its own
/// shutter, and `FrameResult.ev100` reports what it chose in these units.
final class PhysicalCamera {
  const PhysicalCamera({
    this.aperture = referenceAperture,
    this.shutter = referenceShutter,
    this.iso = referenceIso,
    this.compensation = 0.0,
  }) : assert(aperture > 0.0, 'an f-number is above nought'),
       assert(shutter > 0.0, 'a shutter is open for some time'),
       assert(iso > 0.0, 'a sensitivity is above nought');

  /// A camera set to [ev100] at [aperture] and [iso]: the shutter is what
  /// makes the three agree.
  factory PhysicalCamera.atEv100(
    double ev100, {
    double aperture = referenceAperture,
    double iso = referenceIso,
  }) => PhysicalCamera(
    aperture: aperture,
    iso: iso,
    shutter: shutterFor(ev100, aperture: aperture, iso: iso),
  );

  /// A camera set as an incident meter reads [lux]: [ev100ForIlluminance],
  /// then [PhysicalCamera.atEv100].
  factory PhysicalCamera.metered(
    double lux, {
    double aperture = referenceAperture,
    double iso = referenceIso,
  }) => PhysicalCamera.atEv100(
    ev100ForIlluminance(lux),
    aperture: aperture,
    iso: iso,
  );

  /// A camera set for the light under [sky] with the sun along [toSun]:
  /// [PhysicalSky.illuminanceLux], metered.
  factory PhysicalCamera.forSky(
    PhysicalSky sky,
    Vector3 toSun, {
    double aperture = referenceAperture,
    double iso = referenceIso,
  }) => PhysicalCamera.metered(
    sky.illuminanceLux(toSun),
    aperture: aperture,
    iso: iso,
  );

  /// The f-number: the focal length over the opening's diameter. Larger is
  /// a smaller opening, less light and, where depth of field is on, more of
  /// the picture sharp.
  /// A unitless ratio.
  final double aperture;

  /// How long the shutter is open, in seconds.
  final double shutter;

  /// The sensor's sensitivity, ISO arithmetic.
  /// Unitless.
  final double iso;

  /// Stops added on top of what the three settings make; positive is
  /// brighter, as the dial on a camera.
  /// In stops (EV).
  final double compensation;

  /// f/4, the reference camera's aperture.
  /// A unitless ratio.
  static const double referenceAperture = 4.0;

  /// A sixtieth of a second, the reference camera's shutter.
  static const double referenceShutter = 1.0 / 60.0;

  /// ISO 100, the reference camera's sensitivity.
  /// Unitless.
  static const double referenceIso = 100.0;

  /// The reference camera's exposure value, `log2(4² × 60)`, about 9.907.
  static double get referenceEv100 => const PhysicalCamera().ev100;

  /// The exposure multiplier the reference camera is held to — what
  /// `RenderSettings.defaultExposure` is.
  static const double referenceExposure = 1.6;

  /// The exposure value at ISO 100: `log2(N² / t) − log2(S / 100)`, less
  /// [compensation].
  /// In stops (EV).
  double get ev100 =>
      _log2(aperture * aperture / shutter) - _log2(iso / 100.0) - compensation;

  /// What this camera multiplies a frame's light by, against the reference
  /// camera: `2^(referenceEv100 − ev100)`. Exactly one at the reference.
  double get exposureScale {
    final stops = referenceEv100 - ev100;
    return stops == 0.0 ? 1.0 : math.pow(2.0, stops).toDouble();
  }

  /// The linear exposure multiplier this camera makes, in the engine's
  /// photometric scale: `1843.2 / (1.2 × 2^EV100)`, which is
  /// [referenceExposure] × [exposureScale].
  double get exposure => referenceExposure * exposureScale;

  /// The exposure value a linear [exposure] multiplier stands for — what a
  /// metered or pinned multiplier would be on a dial.
  static double ev100ForExposure(double exposure) =>
      referenceEv100 + _log2(referenceExposure / exposure);

  /// An incident meter's reading under [lux], at ISO 100: `log2(E / 2.5)`,
  /// the calibration constant 250 over a hundred.
  static double ev100ForIlluminance(double lux) =>
      _log2(math.max(lux, 1e-6) / 2.5);

  /// The shutter time that makes [ev100] at [aperture] and [iso].
  static double shutterFor(
    double ev100, {
    double aperture = referenceAperture,
    double iso = referenceIso,
  }) => aperture * aperture / math.pow(2.0, ev100 + _log2(iso / 100.0));

  /// This camera with [aperture] moved by [thirds] thirds of a stop; positive
  /// closes it. A third of a stop is a factor of `2^(1/6)` in f-number.
  PhysicalCamera stopAperture(int thirds) =>
      copyWith(aperture: aperture * math.pow(2.0, thirds / 6.0));

  /// This camera with [shutter] moved by [thirds] thirds of a stop; positive
  /// is longer.
  PhysicalCamera stopShutter(int thirds) =>
      copyWith(shutter: shutter * math.pow(2.0, thirds / 3.0));

  /// This camera with [iso] moved by [thirds] thirds of a stop; positive is
  /// more sensitive.
  PhysicalCamera stopIso(int thirds) =>
      copyWith(iso: iso * math.pow(2.0, thirds / 3.0));

  PhysicalCamera copyWith({
    double? aperture,
    double? shutter,
    double? iso,
    double? compensation,
  }) => PhysicalCamera(
    aperture: aperture ?? this.aperture,
    shutter: shutter ?? this.shutter,
    iso: iso ?? this.iso,
    compensation: compensation ?? this.compensation,
  );

  /// `f/4 · 1/60 s · ISO 100`, as a camera's display would put it.
  String get label {
    final f = aperture >= 10.0
        ? aperture.toStringAsFixed(0)
        : aperture.toStringAsFixed(1);
    final t = shutter >= 1.0
        ? '${shutter.toStringAsFixed(shutter >= 10.0 ? 0 : 1)} s'
        : '1/${(1.0 / shutter).round()} s';
    return 'f/$f · $t · ISO ${iso.round()}';
  }

  @override
  bool operator ==(Object other) =>
      other is PhysicalCamera &&
      other.aperture == aperture &&
      other.shutter == shutter &&
      other.iso == iso &&
      other.compensation == compensation;

  @override
  int get hashCode => Object.hash(aperture, shutter, iso, compensation);

  @override
  String toString() =>
      'PhysicalCamera($label, EV100 ${ev100.toStringAsFixed(2)})';

  static double _log2(double x) => math.log(x) / math.ln2;
}
