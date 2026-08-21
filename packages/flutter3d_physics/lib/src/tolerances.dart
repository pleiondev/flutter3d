/// What "close enough" means in this package, once.
///
/// **Three magnitudes, seventeen sites, and no name on any of them.** `1e-6`
/// appeared seven times, `1e-12` five, `1e-9` three and `1e-4` twice, and
/// reading any one of them told you the number rather than the question. They
/// are not interchangeable: one is a distance a player cannot perceive, one is
/// the slack on comparing two numbers that were computed different ways, and
/// one is a denominator guard on a squared quantity. Mixing them up is a
/// division by nearly nothing or a body that never settles.
///
/// The values are exactly what was there before — this names them, it does not
/// tune them. Anything that wants a different number wants a different name
/// and a reason.
abstract final class Nearly {
  /// A micrometre, or a micrometre a second.
  ///
  /// Far enough to swallow the float noise on a position placed exactly on a
  /// surface, far short of the millimetre of clearance a contact backs off by,
  /// and nothing a player can be at either scale. This is the one that answers
  /// "is it still?", "is it touching?" and "is it going anywhere?".
  static const double still = 1e-6;

  /// A tenth of a millimetre, or a tenth of a millimetre a second.
  ///
  /// **Coarser on purpose**, and only where the answer is whether a *person*
  /// is doing something: whether a walker is pushing a crate, and which way.
  /// A micrometre a second is a body drifting on numerical noise, and shoving
  /// a crate with it makes the world twitch while nobody is moving.
  static const double moving = 1e-4;

  /// The slack on comparing two numbers that were computed different ways.
  ///
  /// Not a distance anybody can see: a nanometre is beneath the precision of
  /// the arithmetic that produced it. What it stops is `a > b` answering
  /// differently on either side of a rounding.
  static const double same = 1e-9;

  /// A denominator that must not be divided by.
  ///
  /// Squared lengths and dot products live here, which is why it is so much
  /// smaller than the others: a length of a micrometre is a squared length of
  /// `1e-12`, so a guard on the square has to be squared too or it rejects
  /// vectors that are perfectly usable.
  static const double parallel = 1e-12;
}
