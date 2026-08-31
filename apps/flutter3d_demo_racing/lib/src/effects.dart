import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

/// What this game throws into the air, as recipes rather than code.
///
/// The same shape the other two games use: an emitter, a lifetime, a size and a
/// list of affectors, all data. **This game had none of it** — no particles at
/// all, so a car could lock its wheels, slide sideways across a kerb and throw
/// up nothing, and the only thing that changed on screen was a number.
///
/// Colours are linear and their alpha reads as brightness, because these draw
/// additively into an HDR target. A racing palette is dust and rubber smoke:
/// pale, thin, and quick to fade, because it is seen at sixty metres a second
/// and anything that lingers reads as fog.
abstract final class Effects {
  /// Tyre smoke: the wheels turning faster or slower than the road.
  ///
  /// Rises and drifts rather than flying: rubber smoke has almost no momentum
  /// of its own, and a cone of fast particles reads as sparks. What sells it is
  /// how long it hangs, which is why the lifetime is the longest here.
  static final ParticleEffect smoke = ParticleEffect(
    count: 6,
    lifetime: const Range(0.5, 1.1),
    size: const Range(0.35, 0.8),
    color: Vector4(0.62, 0.60, 0.58, 0.55),
    emitter: const SphereEmitter(
      radius: Range(0.05, 0.2),
      speed: Range(0.4, 1.2),
    ),
    affectors: <ParticleAffector>[
      // Upwards, slightly: smoke off a hot tyre rises, and gravity pulling it
      // down is the difference between smoke and dirt.
      const ParticleGravity(1.1),
      const ParticleDrag(2.6),
      const ParticleSizeOverLife(from: 0.6, to: 2.4),
      const ParticleFade(startsAt: 0.2),
    ],
  );

  /// Dirt thrown by a wheel that has left the road.
  ///
  /// Heavier, faster and much shorter-lived than smoke: this is thrown by the
  /// tyre rather than boiled off it, so it flies and falls.
  static final ParticleEffect dirt = ParticleEffect(
    count: 10,
    lifetime: const Range(0.25, 0.6),
    size: const Range(0.1, 0.26),
    color: Vector4(0.42, 0.34, 0.22, 0.9),
    emitter: const SphereEmitter(
      radius: Range(0.05, 0.18),
      speed: Range(2.0, 5.0),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-9.0),
      const ParticleDrag(1.2),
      const ParticleSizeOverLife(from: 1.0, to: 0.6),
      const ParticleFade(startsAt: 0.5),
    ],
  );

  /// The scrape of a car against a barrier.
  static final ParticleEffect sparks = ParticleEffect(
    count: 12,
    lifetime: const Range(0.15, 0.4),
    size: const Range(0.04, 0.1),
    // Well above one: sparks are what the bloom is for.
    color: Vector4(2.4, 1.5, 0.5, 1.0),
    emitter: const SphereEmitter(
      radius: Range(0.0, 0.1),
      speed: Range(3.0, 8.0),
    ),
    affectors: <ParticleAffector>[
      const ParticleGravity(-14.0),
      const ParticleDrag(0.8),
      const ParticleSizeOverLife(from: 1.0, to: 0.4),
      const ParticleFade(startsAt: 0.4),
    ],
  );
}
