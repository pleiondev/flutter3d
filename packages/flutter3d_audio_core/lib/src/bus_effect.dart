import 'dart:math' as math;

/// Something a mixer bus does to everything routed through it, beyond its
/// volume: a filter, a reverb.
///
/// **A description, not a DSP.** The mixer realises what it can itself — a
/// [LowPassEffect] becomes the muffle each voice on the bus is handed — and a
/// backend that mixes buses of its own (`MixingBackend`) is handed the whole
/// list and realises the rest. A backend that can do neither ignores what it
/// cannot do, which is the same promise `muffle` has always made.
///
/// `base`, so an effect added later arrives with defaults: a game declares
/// its own by extending this, and a backend that does not know it skips it.
abstract base class BusEffect {
  const BusEffect();

  /// This effect at [weight] of its strength, from 0 (it does nothing) to 1
  /// (all of it): what a snapshot blending in or out applies on the way.
  ///
  /// The default is a step at the half — right for something with no
  /// in-between, and overridden by everything that has one.
  BusEffect? atWeight(double weight) => weight >= 0.5 ? this : null;
}

/// Takes the top off everything on the bus above [cutoffHz] hertz: what
/// "under water" and "through a wall" sound like.
///
/// **The mixer realises it on any backend**, as the muffle a voice is
/// started with: the same 0-to-1 dullness occlusion already hands a backend,
/// on the same geometric scale between [openHz] and [wallHz] that
/// `flutter3d_audio`'s filter turns back into a cutoff. A voice behind a
/// wall on a muffled bus is as dull as the duller of the two.
final class LowPassEffect extends BusEffect {
  const LowPassEffect(this.cutoffHz) : assert(cutoffHz > 0.0);

  /// Where the filter sits, in hertz.
  final double cutoffHz;

  /// The cutoff that counts as no filter at all, in hertz: a muffle of 0.
  static const double openHz = 16000.0;

  /// The cutoff of a sound heard through a wall, in hertz: a muffle of 1.
  static const double wallHz = 600.0;

  /// How dull this leaves a voice, from 0 (clear) to 1 (through a wall):
  /// the cutoff's place between [openHz] and [wallHz], in octaves rather
  /// than in hertz, because that is how pitch is heard.
  double get muffle {
    if (cutoffHz >= openHz) return 0.0;
    if (cutoffHz <= wallHz) return 1.0;
    return math.log(openHz / cutoffHz) / math.log(openHz / wallHz);
  }

  /// Geometric between [openHz] and the cutoff, so half way in is half way
  /// in pitch.
  @override
  LowPassEffect? atWeight(double weight) {
    if (weight <= 0.0) return null;
    if (weight >= 1.0 || cutoffHz >= openHz) return this;
    return LowPassEffect(
      openHz * math.pow(cutoffHz / openHz, weight).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LowPassEffect && other.cutoffHz == cutoffHz;

  @override
  int get hashCode => cutoffHz.hashCode;

  @override
  String toString() => 'LowPassEffect(${cutoffHz.toStringAsFixed(0)} Hz)';
}

/// A room's tail on everything on the bus: [wet] of the signal sent to a
/// reverb that dies away by 60 dB in [decaySeconds] seconds.
///
/// **Only a backend that mixes buses itself can play it**; the mixer has no
/// way to fake a reverb with a gain and a pan, and does not pretend to. It
/// is here so that a snapshot written today — a cave, a hall — names its
/// reverb now and is heard with it on the first backend that has one.
final class ReverbEffect extends BusEffect {
  const ReverbEffect({this.wet = 0.3, this.decaySeconds = 1.5})
    : assert(wet >= 0.0 && wet <= 1.0),
      assert(decaySeconds > 0.0);

  /// How much of the bus is sent to the reverb, from 0 to 1, as linear gain.
  final double wet;

  /// The time for the tail to fall by 60 dB (RT60), in seconds.
  final double decaySeconds;

  /// The send scaled; the room stays the size it is.
  @override
  ReverbEffect? atWeight(double weight) {
    if (weight <= 0.0) return null;
    if (weight >= 1.0) return this;
    return ReverbEffect(wet: wet * weight, decaySeconds: decaySeconds);
  }

  @override
  bool operator ==(Object other) =>
      other is ReverbEffect &&
      other.wet == wet &&
      other.decaySeconds == decaySeconds;

  @override
  int get hashCode => Object.hash(wet, decaySeconds);

  @override
  String toString() => 'ReverbEffect(wet: $wet, ${decaySeconds}s)';
}
