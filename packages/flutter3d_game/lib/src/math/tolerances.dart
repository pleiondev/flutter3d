/// What "close enough" means in this package.
///
/// **Twenty-three comparisons against a bare number, in four magnitudes.** As
/// in `flutter3d_physics`, which grew the same set for the same reason, the
/// number was never the interesting part: `1e-6` appears both as "this vector
/// is too short to point anywhere" and as "nudge this off the grid line", and
/// those are different questions that happen to have the same answer today.
///
/// **Named `Tolerance` rather than `Nearly`** because this package imports
/// `flutter3d_physics`, which has a `Nearly` of its own with a different set —
/// and two identical names for two different sets is how a caller ends up
/// asking the wrong question in the right units.
///
/// The values are exactly what they were. What is new is that a reader can see
/// which question is being asked, and that somebody changing one of them
/// changes it for the question rather than for the file.
abstract final class Tolerance {
  /// A vector too short to point anywhere.
  ///
  /// Normalising below this divides by noise and gives a direction that is
  /// whatever the rounding was — which is why every caller checks first and
  /// does something else instead.
  static const double zeroLength = 1e-6;

  /// A denominator that must not be divided by.
  ///
  /// Smaller than [zeroLength] because what is guarded here is a span, a
  /// duration or a squared length rather than a distance — quantities that are
  /// legitimately tiny without being degenerate.
  static const double divisor = 1e-9;

  /// A tenth of a millimetre.
  ///
  /// The scale at which two surfaces are the same surface, a step is not a
  /// step, and a point is already where it was going. Coarse on purpose: it
  /// answers questions about *level geometry*, which is authored in metres by a
  /// person, and a micrometre there is a rounding in the document rather than a
  /// fact about the world.
  static const double sameSurface = 1e-4;

  /// The nudge that keeps a boundary out of two cells at once.
  ///
  /// A brush whose face lands exactly on a grid line overlaps a zero-width
  /// slice of the next cell, and counting it fills a cell nothing stands in.
  /// The same magnitude as [zeroLength] and a different question, which is the
  /// whole argument for naming these.
  static const double gridBias = 1e-6;
}
