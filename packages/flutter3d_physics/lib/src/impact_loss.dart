/// What a material's loss factor takes from a bounce:
/// [restitutionOfLossFactor].
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show PhysicalMaterial, WorldProperties;

/// The most share of its approach speed a contact gives back when what it
/// is made of has the loss factor [lossFactor] (`InelasticProperties
/// .lossFactor`): one for none, nought from two on.
///
/// **The law.** A contact is a spring and a dashpot in parallel (Kelvin and
/// Voigt). A material's loss factor, the energy a cycle loses to heat over
/// 2π times the energy it stores, is twice the damping ratio of such a
/// spring at its resonance, η = 2ζ (Nashif, Jones and Henderson, *Vibration
/// Damping*, Wiley, 1985). The spring and dashpot let go of a mass after
/// half a damped period with exp(−π ζ / √(1 − ζ²)) of the speed it met
/// them at, and an overdamped one, ζ ≥ 1, with none: the linear dashpot's
/// coefficient of restitution (Schwager and Pöschel, Phys. Rev. E 78,
/// 051304, 2008).
///
/// **What the contact makes of it.** In a world whose profile is not
/// bit-exact (`WorldProperties.profile`), a contact bounces with no more
/// than this of the lossier side's η: it takes from the restitution the
/// contact would have, and never adds to it, since a material's hysteresis
/// is one of the ways an impact loses energy and not the only one. Under a
/// bit-exact profile nothing reads it, so a deterministic run's tapes and
/// digests are what they were. Both cores do the same: `Dynamics` here, and
/// the native core through `NativeWorld.setLossFactor`.
///
/// Throws an [ArgumentError] for a loss factor below nought or not finite.
double restitutionOfLossFactor(double lossFactor) {
  if (!(lossFactor >= 0.0 && lossFactor.isFinite)) {
    throw ArgumentError.value(
      lossFactor,
      'lossFactor',
      'a loss factor is finite and nought or more',
    );
  }
  final zeta = lossFactor / 2.0;
  if (zeta >= 1.0) return 0.0;
  return Portable.exp(-math.pi * zeta / math.sqrt(1.0 - zeta * zeta));
}

/// Whether a contact in a world of [properties] reads its materials' loss
/// factors: only where the profile does not promise bits.
bool contactsReadLoss(WorldProperties properties) =>
    !properties.profile.isBitExact;

/// [material]'s loss factor at its reference state, or nought where it has
/// none: the number `inelastic` gives a contact.
double lossFactorOf(PhysicalMaterial? material) =>
    material?.inelastic?.lossFactor?.value ?? 0.0;
