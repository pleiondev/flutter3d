import 'package:flutter3d_particles/flutter3d_particles.dart';
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
  /// [ParticleSystem.emit]. This is what makes a torch a torch; the iron
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
      // A standing swirl, at a scale a little smaller than the flame itself so
      // a particle crosses two or three cells in its fifth of a second. Weak:
      // the cone already decides the shape and this only has to stop the
      // column being a column. Turn it up and the torch reads as a gas leak.
      //
      // Each torch is in a different part of the level, so each sits in a
      // different part of the field and burns differently from its neighbour —
      // which is the thing a per-torch phase offset would otherwise have to
      // fake.
      const ParticleTurbulence(strength: 0.55, scale: 3.0),
      ParticleColorGradient(
        ParticleGradient(<GradientKey>[
          // Three keys where there were two: real flame is white-hot at the
          // wick, orange through the body and dark at the tip, and a straight
          // line between the first and last passes through none of that. The
          // first segment eases, so the drop out of the hottest part is quick
          // and the long orange middle is where most of the life is spent.
          GradientKey(0.0, Vector4(1.0, 0.86, 0.55, 1.0), ease: KeyEase.smooth),
          GradientKey(0.35, Vector4(1.0, 0.66, 0.24, 1.0)),
          GradientKey(1.0, Vector4(0.55, 0.08, 0.02, 1.0)),
        ]),
      ),
      const ParticleFade(startsAt: 0.35),
      const ParticleSizeOverLife(from: 1.0, to: 0.25),
    ],
  );

  /// What a blast leaves behind: a slow plume that keeps rising after the
  /// bright part is over.
  ///
  /// The one effect here that is neither a burst nor a standing rate. An
  /// explosion is over in a fifth of a second and its smoke is not, so this is
  /// emitted with [ParticleSystem.emitTimed] — a rate that runs for a stated
  /// time and then stops itself. Emitting it as one burst instead would put
  /// every particle in the air at the same instant, which reads as a puff of
  /// dust rather than as something still burning.
  ///
  /// Wide and dark, because it is behind the fire rather than part of it: the
  /// bloom threshold must not pick it up, or the smoke glows.
  static final ParticleEffect explosionSmoke = ParticleEffect(
    count: 1,
    emitter: BoxEmitter(
      halfExtents: Vector3(0.35, 0.10, 0.35),
      speed: const Range(0.5, 1.3),
      along: Vector3(0.0, 1.0, 0.0),
    ),
    lifetime: const Range(0.9, 1.8),
    size: const Range(0.22, 0.40),
    color: Vector4(0.20, 0.17, 0.15, 1.0),
    affectors: <ParticleAffector>[
      const ParticleDrag(1.4),
      // Stronger and wider than the torch's: a plume this size has room to
      // roll, and the roll is most of what separates smoke from a grey cone.
      const ParticleTurbulence(strength: 0.9, scale: 1.2),
      ParticleSizeCurve(
        ParticleCurve(<CurveKey>[
          // Small at birth, opening quickly, then easing to a stop rather than
          // growing at the same rate all the way out — smoke expands into still
          // air and slows as it does.
          const CurveKey(0.0, 0.5, ease: KeyEase.smooth),
          const CurveKey(0.45, 1.7, ease: KeyEase.smooth),
          const CurveKey(1.0, 2.1),
        ]),
      ),
      const ParticleFade(startsAt: 0.25),
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
    emitter: const ConeEmitter(speed: Range(2.5, 7.0), halfAngleDegrees: 42.0),
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
    emitter: const ConeEmitter(speed: Range(0.4, 1.6), halfAngleDegrees: 60.0),
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
    emitter: const ConeEmitter(speed: Range(0.5, 2.0), halfAngleDegrees: 18.0),
    lifetime: const Range(0.04, 0.09),
    size: const Range(0.10, 0.22),
    color: Vector4(4.0, 2.6, 1.1, 1.0),
    affectors: <ParticleAffector>[
      const ParticleSizeOverLife(from: 1.0, to: 0.3),
      const ParticleFade(),
    ],
  );
}
