import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

/// What this game throws into the air, as recipes rather than code.
///
/// The same shape as the dungeon's: an emitter, a lifetime, a size and a list
/// of affectors, all data. Adding an effect is adding a constant here.
///
/// Colours are linear and their alpha reads as brightness, because these draw
/// additively into an HDR target — values above one are what the bloom picks
/// up. A platformer's palette is lighter than a dungeon's on purpose: dust and
/// sparks rather than fire and blood.
abstract final class Effects {
  /// The puff a landing raises. Sized by the impact at the call site.
  static final ParticleEffect dust = ParticleEffect(
    count: 14,
    lifetime: const Range(0.25, 0.55),
    size: const Range(0.14, 0.34),
    color: Vector4(0.72, 0.68, 0.60, 0.9),
    // Outwards and barely upwards: dust is thrown sideways by a foot, and a
    // cone pointing up reads as steam.
    // A shell rather than a point, so the puff starts as a ring under the
    // feet: `radius` on a sphere emitter is what a disc emitter would be, and
    // gravity flattens it in a tenth of a second anyway.
    emitter: const SphereEmitter(
      radius: Range(0.15, 0.35),
      speed: Range(1.2, 2.6),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-2.2),
      const ParticleDrag(3.4),
      const ParticleSizeOverLife(from: 0.7, to: 1.6),
      const ParticleFade(startsAt: 0.35),
    ],
  );

  /// The heavier version, for a ground pound.
  static final ParticleEffect slam = ParticleEffect(
    count: 26,
    lifetime: const Range(0.35, 0.75),
    size: const Range(0.20, 0.5),
    color: Vector4(0.85, 0.78, 0.62, 1.0),
    emitter: const SphereEmitter(
      radius: Range(0.2, 0.5),
      speed: Range(3.0, 6.5),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-3.0),
      const ParticleDrag(2.6),
      const ParticleSizeOverLife(from: 0.6, to: 2.0),
      const ParticleFade(),
    ],
  );

  /// The streak a dash leaves behind it.
  static final ParticleEffect dash = ParticleEffect(
    count: 10,
    lifetime: const Range(0.18, 0.34),
    size: const Range(0.16, 0.30),
    color: Vector4(0.55, 0.80, 1.0, 1.0),
    emitter: const SphereEmitter(
      radius: Range(0.1, 0.3),
      speed: Range(0.2, 0.9),
    ),
    affectors: <ParticleAffector>[
      const ParticleDrag(5.0),
      const ParticleFade(),
      const ParticleSizeOverLife(from: 1.0, to: 0.2),
    ],
  );

  /// The flash a coin leaves where it was.
  static final ParticleEffect coin = ParticleEffect(
    count: 12,
    lifetime: const Range(0.22, 0.45),
    size: const Range(0.08, 0.18),
    color: Vector4(1.6, 1.25, 0.35, 1.0),
    emitter: const SphereEmitter(
      radius: Range(0.05, 0.15),
      speed: Range(1.4, 3.0),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-3.5),
      const ParticleDrag(2.2),
      const ParticleFade(),
    ],
  );

  /// The puff a spring makes when it throws somebody.
  static final ParticleEffect spring = ParticleEffect(
    count: 18,
    lifetime: const Range(0.20, 0.40),
    size: const Range(0.12, 0.26),
    color: Vector4(1.2, 0.95, 0.45, 1.0),
    emitter: const ConeEmitter(halfAngleDegrees: 26.0, speed: Range(3.0, 6.0)),
    affectors: <ParticleAffector>[
      const ParticleGravity(-4.0),
      const ParticleDrag(2.0),
      const ParticleFade(),
    ],
  );

  /// The flare a checkpoint gives when it becomes yours.
  static final ParticleEffect checkpoint = ParticleEffect(
    count: 30,
    lifetime: const Range(0.5, 1.0),
    size: const Range(0.10, 0.22),
    color: Vector4(0.45, 1.6, 0.75, 1.0),
    emitter: const ConeEmitter(halfAngleDegrees: 16.0, speed: Range(2.0, 4.5)),
    affectors: <ParticleAffector>[
      const ParticleGravity(-1.2),
      const ParticleDrag(1.6),
      const ParticleFade(),
    ],
  );

  /// What a death throws out. Deliberately not blood: this game is not that.
  static final ParticleEffect death = ParticleEffect(
    count: 40,
    lifetime: const Range(0.4, 0.9),
    size: const Range(0.14, 0.30),
    color: Vector4(1.4, 0.5, 0.35, 1.0),
    emitter: const SphereEmitter(
      radius: Range(0.15, 0.4),
      speed: Range(2.5, 7.0),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-6.0),
      const ParticleDrag(1.4),
      const ParticleFade(),
    ],
  );

  /// The dust a crumbling platform sheds as it goes.
  static final ParticleEffect crumble = ParticleEffect(
    count: 20,
    lifetime: const Range(0.4, 0.9),
    size: const Range(0.10, 0.24),
    color: Vector4(0.62, 0.55, 0.46, 1.0),
    emitter: BoxEmitter(
      halfExtents: Vector3(1.6, 0.1, 1.6),
      speed: const Range(0.2, 1.2),
      along: Vector3(0.0, -1.0, 0.0),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-7.0),
      const ParticleFade(startsAt: 0.35),
    ],
  );

  /// A lamp's flame. Emitted continuously rather than burst — see the
  /// dungeon's, which this is deliberately a smaller copy of.
  static final ParticleEffect flame = ParticleEffect(
    count: 1,
    lifetime: const Range(0.18, 0.36),
    size: const Range(0.08, 0.16),
    color: Vector4(1.0, 0.66, 0.26, 1.0),
    emitter: const ConeEmitter(halfAngleDegrees: 11.0, speed: Range(0.20, 0.5)),
    affectors: <ParticleAffector>[
      const ParticleGravity(1.0),
      const ParticleDrag(2.6),
      const ParticleTurbulence(strength: 0.5, scale: 3.0),
      const ParticleFade(),
    ],
  );
}
