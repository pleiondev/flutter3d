import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// The effects this game triggers, as recipes rather than code.
///
/// Every one of these is the same three ingredients — an emitter, a lifetime
/// and a list of affectors — with different numbers. That is the point of the
/// particle system taking them as data: adding a new effect is adding a
/// constant to this file, and nothing in the engine or the renderer changes.
///
/// The colours are linear and their alpha reads as brightness, because these
/// draw additively into the HDR target. Values above one are deliberate: they
/// are what the bloom pass picks up, and an explosion that does not bloom looks
/// like an orange sticker.
abstract final class Effects {
  /// A torch flame: small, short-lived, rising, orange into dark red.
  ///
  /// Emitted continuously rather than in bursts — see
  /// [ParticleSystem.emitFor]. This is what makes a torch a torch; the iron
  /// around it is only a bracket. A cone would be a cone however orange it was
  /// painted, which is what the first attempt at this was.
  static final ParticleEffect flame = ParticleEffect(
    count: 1,
    // Short and slow, so the particles stay in a handful and overlap. The
    // first attempt used a long life and a wide spread, and sixteen live
    // particles at that size are a scattering of dots — which is exactly what
    // it looked like. Fire reads as fire when the quads pile up: additive
    // blending turns the overlap into a bright core, and the core is the part
    // the eye calls flame.
    lifetime: const Range(0.20, 0.40),
    size: const Range(0.10, 0.19),
    color: Vector4(1.0, 0.62, 0.22, 1.0),
    emitter: const ConeEmitter(
      halfAngleDegrees: 10.0,
      speed: Range(0.22, 0.55),
    ),
    affectors: <ParticleAffector>[
      // Upward, because hot air is the whole shape of a flame.
      const ParticleGravity(1.1),
      const ParticleDrag(2.6),
      ParticleColorOverLife(
        Vector4(1.0, 0.72, 0.30, 1.0),
        Vector4(0.55, 0.08, 0.02, 1.0),
      ),
      const ParticleFade(startsAt: 0.35),
      const ParticleSizeOverLife(from: 1.0, to: 0.25),
    ],
  );

  /// The core of a rocket blast: fast, bright, brief.
  static final ParticleEffect explosionCore = ParticleEffect(
    count: 90,
    emitter: const SphereEmitter(
      speed: Range(4.0, 16.0),
      radius: Range(0.0, 0.4),
    ),
    lifetime: const Range(0.25, 0.6),
    size: const Range(0.35, 0.9),
    color: Vector4(3.2, 1.5, 0.45, 1.0),
    affectors: <ParticleAffector>[
      // Enough drag that the fireball stops expanding almost at once, which is
      // what makes it read as a detonation rather than as fireworks.
      const ParticleDrag(6.0),
      const ParticleGravity(-3.0),
      ParticleColorOverLife(
        Vector4(3.2, 1.5, 0.45, 1.0),
        Vector4(0.6, 0.15, 0.05, 1.0),
      ),
      const ParticleSizeOverLife(from: 0.7, to: 1.6),
      const ParticleFade(startsAt: 0.35),
    ],
  );

  /// Debris thrown clear of the blast, slower to die than the core.
  static final ParticleEffect explosionEmbers = ParticleEffect(
    count: 40,
    emitter: const SphereEmitter(speed: Range(6.0, 22.0)),
    lifetime: const Range(0.5, 1.4),
    size: const Range(0.05, 0.14),
    color: Vector4(2.6, 1.1, 0.3, 1.0),
    affectors: <ParticleAffector>[
      const ParticleGravity(-11.0),
      const ParticleDrag(1.2),
      const ParticleFade(startsAt: 0.5),
    ],
  );

  /// Sparks where a bullet met stone.
  static final ParticleEffect impactSparks = ParticleEffect(
    count: 14,
    emitter: const ConeEmitter(
      speed: Range(2.5, 7.0),
      halfAngleDegrees: 42.0,
    ),
    lifetime: const Range(0.12, 0.35),
    size: const Range(0.03, 0.08),
    color: Vector4(2.4, 1.6, 0.7, 1.0),
    affectors: <ParticleAffector>[
      const ParticleGravity(-14.0),
      const ParticleFade(startsAt: 0.4),
    ],
  );

  /// Dust knocked off the surface, which is what sells the sparks as impact
  /// rather than as decoration.
  static final ParticleEffect impactDust = ParticleEffect(
    count: 6,
    emitter: const ConeEmitter(
      speed: Range(0.4, 1.6),
      halfAngleDegrees: 60.0,
    ),
    lifetime: const Range(0.4, 0.9),
    size: const Range(0.12, 0.3),
    color: Vector4(0.30, 0.26, 0.22, 1.0),
    affectors: <ParticleAffector>[
      const ParticleDrag(2.5),
      const ParticleSizeOverLife(from: 0.6, to: 1.8),
      const ParticleFade(),
    ],
  );

  /// A brief flare at the muzzle.
  static final ParticleEffect muzzleFlash = ParticleEffect(
    count: 5,
    emitter: const ConeEmitter(
      speed: Range(0.5, 2.0),
      halfAngleDegrees: 18.0,
    ),
    lifetime: const Range(0.04, 0.09),
    size: const Range(0.10, 0.22),
    color: Vector4(4.0, 2.6, 1.1, 1.0),
    affectors: <ParticleAffector>[
      const ParticleSizeOverLife(from: 1.0, to: 0.3),
      const ParticleFade(),
    ],
  );
}
