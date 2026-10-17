/// The numbers that make one driver different from another.
final class AiSettings {
  const AiSettings({
    this.lookAheadPerSpeed = 0.55,
    this.minLookAhead = 12.0,
    this.steerGain = 2.2,
    this.corneringGrip = 14.0,
    this.brakeHorizon = 45.0,
    this.brakeMargin = 1.1,
    this.rubberBandPer100m = 0.07,
    this.rubberBandClamp = 0.22,
    this.avoidRange = 22.0,
    this.avoidWidth = 3.2,
    this.avoidOffset = 3.0,
    this.skill = 1.0,
  });

  /// How far ahead to aim, per metre per second of speed.
  ///
  /// A fixed distance cannot work: near enough to be accurate in a hairpin is
  /// near enough to weave on a straight, and far enough to be smooth on a
  /// straight is far enough to cut the hairpin entirely.
  final double lookAheadPerSpeed;

  /// The nearest it ever aims, in metres.
  final double minLookAhead;

  /// How hard the wheel is turned per radian of error.
  final double steerGain;

  /// How much cornering the driver believes it has, in metres per second
  /// squared.
  ///
  /// Deliberately below what the tyres can actually do. A driver that believed
  /// the true figure would be at the limit in every corner and off the road at
  /// the first bump.
  final double corneringGrip;

  /// How far up the road to look for something to brake for.
  /// In metres.
  final double brakeHorizon;

  /// How far over the corner speed the driver lets itself get before braking,
  /// rather than lifting.
  /// A unitless multiplier on the corner speed.
  final double brakeMargin;

  /// How much faster a driver goes for every hundred metres it is behind the
  /// player, as a fraction of its pace.
  final double rubberBandPer100m;

  /// The most the rubber band may change a driver's pace, either way.
  ///
  /// The reason there is a limit at all: a field that can always catch up is a
  /// field the player cannot beat, and one that can always be caught is a field
  /// the player cannot lose to. Both read as the race being fake, which it is.
  /// A fraction of its pace.
  final double rubberBandClamp;

  /// How far ahead to look for a car to go round.
  /// In metres.
  final double avoidRange;

  /// How close alongside counts as being in the way.
  /// In metres.
  final double avoidWidth;

  /// How far to move over for one.
  /// In metres.
  final double avoidOffset;

  /// How good this driver is, from nought to one. Scales the pace it aims for.
  final double skill;

  /// A copy with the given fields replaced.
  AiSettings copyWith({
    double? lookAheadPerSpeed,
    double? minLookAhead,
    double? steerGain,
    double? corneringGrip,
    double? brakeHorizon,
    double? brakeMargin,
    double? rubberBandPer100m,
    double? rubberBandClamp,
    double? avoidRange,
    double? avoidWidth,
    double? avoidOffset,
    double? skill,
  }) => AiSettings(
    lookAheadPerSpeed: lookAheadPerSpeed ?? this.lookAheadPerSpeed,
    minLookAhead: minLookAhead ?? this.minLookAhead,
    steerGain: steerGain ?? this.steerGain,
    corneringGrip: corneringGrip ?? this.corneringGrip,
    brakeHorizon: brakeHorizon ?? this.brakeHorizon,
    brakeMargin: brakeMargin ?? this.brakeMargin,
    rubberBandPer100m: rubberBandPer100m ?? this.rubberBandPer100m,
    rubberBandClamp: rubberBandClamp ?? this.rubberBandClamp,
    avoidRange: avoidRange ?? this.avoidRange,
    avoidWidth: avoidWidth ?? this.avoidWidth,
    avoidOffset: avoidOffset ?? this.avoidOffset,
    skill: skill ?? this.skill,
  );
}
