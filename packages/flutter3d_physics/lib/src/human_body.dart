/// One reference human body: how heavy a whole person is, and how that
/// weight is shared out among the segments a ragdoll is made of.
///
/// **One body, read by everything that has one** — a skinned character gone
/// limp, a dungeon's corpses, a showcase's figure — so a ragdoll's thigh
/// and a corpse's push are reckoned from the same person.
library;

/// What a reference adult man weighs, kg: 73, the reference male of ICRP
/// Publication 89, "Basic anatomical and physiological data for use in
/// radiological protection: reference values" (Annals of the ICRP 32, 2002).
const double referenceBodyMass = 73.0;

/// The share of a whole body's mass each segment holds, for an adult man:
/// de Leva, "Adjustments to Zatsiorsky–Seluyanov's segment inertia
/// parameters", Journal of Biomechanics 29(9), 1223–1230 (1996), table 4,
/// males. No unit; a limb's segment is one side's, and the shares of a whole
/// body — the head, the three trunk segments, and two of each limb segment —
/// add up to one.
abstract final class SegmentMassShares {
  /// The head with the neck, a share of the whole body.
  static const double head = 0.0694;

  /// The upper trunk, a share of the whole body: from the neck to the
  /// bottom of the sternum.
  static const double upperTrunk = 0.1596;

  /// The middle trunk, a share of the whole body: from the sternum to the
  /// navel.
  static const double middleTrunk = 0.1633;

  /// The lower trunk, a share of the whole body: from the navel to the hip
  /// joints — the pelvis.
  static const double lowerTrunk = 0.1117;

  /// One upper arm, a share of the whole body.
  static const double upperArm = 0.0271;

  /// One forearm, a share of the whole body.
  static const double forearm = 0.0162;

  /// One hand, a share of the whole body.
  static const double hand = 0.0061;

  /// One thigh, a share of the whole body.
  static const double thigh = 0.1416;

  /// One shank, a share of the whole body: from the knee to the ankle.
  static const double shank = 0.0433;

  /// One foot, a share of the whole body.
  static const double foot = 0.0137;

  /// Every segment of a whole body, one per side for a limb, by name: what
  /// adds up to one.
  static const Map<String, double> wholeBody = <String, double>{
    'head': head,
    'upperTrunk': upperTrunk,
    'middleTrunk': middleTrunk,
    'lowerTrunk': lowerTrunk,
    'upperArm.L': upperArm,
    'upperArm.R': upperArm,
    'forearm.L': forearm,
    'forearm.R': forearm,
    'hand.L': hand,
    'hand.R': hand,
    'thigh.L': thigh,
    'thigh.R': thigh,
    'shank.L': shank,
    'shank.R': shank,
    'foot.L': foot,
    'foot.R': foot,
  };
}
