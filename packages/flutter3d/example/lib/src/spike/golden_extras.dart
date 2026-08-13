import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

/// The particles and the view model a golden draws, built to be repeatable.
///
/// Both plugins were moved out of the renderer onto the plugin seam and
/// neither was covered by a golden, which meant the suite could go green while
/// the two things the refactor touched were broken. These exist to close that,
/// and everything about them is fixed on purpose: a seeded generator, a whole
/// number of fixed steps, no wall clock anywhere.
abstract final class GoldenExtras {
  /// The seed. Any value works; what matters is that it never changes, because
  /// changing it invalidates every recorded reference.
  static const int seed = 20260809;

  /// Simulated seconds before the frame is drawn.
  ///
  /// Chosen so the burst is mid-flight: at zero every particle sits on the
  /// origin in one bright blob, and a golden of a blob would pass whether or
  /// not the affectors ran.
  static const double warmUp = 0.55;

  static const double stepSize = 1.0 / 60.0;

  /// A burst that exercises the parts a still frame can show: spread from the
  /// emitter, drag and gravity bending the paths, colour and size changing
  /// over life.
  static ParticleEffect get effect => ParticleEffect(
        count: 220,
        lifetime: const Range(0.7, 1.4),
        size: const Range(0.06, 0.16),
        color: Vector4(1.0, 0.72, 0.30, 1.0),
        emitter: const SphereEmitter(speed: Range(2.5, 6.0)),
        affectors: <ParticleAffector>[
          const ParticleGravity(-4.0),
          const ParticleDrag(1.2),
          ParticleColorOverLife(
            Vector4(1.0, 0.75, 0.35, 1.0),
            Vector4(0.9, 0.15, 0.05, 1.0),
          ),
          const ParticleFade(),
          const ParticleSizeOverLife(from: 1.0, to: 2.4),
        ],
      );

  /// A system holding one burst, already advanced to [warmUp].
  ///
  /// Stepped rather than solved: the golden has to show what the running
  /// simulation produces, and a closed form would be a second implementation
  /// that could agree with the reference while the real one drifted.
  static ParticleSystem burst() {
    final particles = ParticleSystem(
      capacity: 512,
      random: math.Random(seed),
    );
    particles.burst(effect, Vector3(0.0, 0.6, 0.0));
    for (var t = 0.0; t < warmUp - 1e-9; t += stepSize) {
      particles.step(stepSize);
    }
    return particles;
  }

  /// A pool that has been round at least once: particles born, died and had
  /// their slots reused before the frame is drawn.
  ///
  /// **The gap this closes.** Every other particle fixture warms up for less
  /// than one lifetime, so nothing dies and every slot is still held by its
  /// first occupant. That made all of them blind to how the pool recycles —
  /// which went unnoticed until compaction landed and all twenty-seven goldens
  /// came back byte-identical, where the change was expected to reorder the
  /// quads and move the picture. It did not reorder anything, because there
  /// was nothing to reorder.
  ///
  /// Here the lifetime is a fifth of the warm-up, so the pool turns over about
  /// five times. Whatever order the live set ends up in, this is the fixture
  /// that has an opinion about it.
  static ParticleSystem recycled() {
    final particles = ParticleSystem(
      capacity: 128,
      random: math.Random(seed),
    );
    final short = ParticleEffect(
      count: 40,
      lifetime: const Range(0.08, 0.12),
      size: const Range(0.06, 0.16),
      color: Vector4(1.0, 0.72, 0.30, 1.0),
      emitter: const SphereEmitter(speed: Range(2.5, 6.0)),
      affectors: <ParticleAffector>[
        const ParticleGravity(-4.0),
        const ParticleDrag(1.2),
        const ParticleFade(),
      ],
    );
    // A burst every few steps, so slots are freed and taken repeatedly rather
    // than once.
    var t = 0.0;
    var since = 0.0;
    while (t < warmUp - 1e-9) {
      if (since <= 0.0) {
        particles.burst(short, Vector3(0.0, 0.6, 0.0));
        since = 0.06;
      }
      particles.step(stepSize);
      since -= stepSize;
      t += stepSize;
    }
    return particles;
  }

  /// One particle, at rest, at a stated place and size.
  ///
  /// The burst has 220 quads overlapping in a field dense enough that "the
  /// nearest bright pixel in the other image is six away" finds a neighbour
  /// rather than the same particle — which is how three attempts to say
  /// whether the two backends draw the same particles produced three numbers
  /// and no answer. One particle has no neighbour to be confused with.
  ///
  /// No affectors, no warm-up and no randomness that matters: whatever the two
  /// backends do with a single camera-facing quad, they do it here where the
  /// difference can only be its position, its size or its brightness.
  static ParticleSystem oneParticle({int count = 1}) {
    final particles = ParticleSystem(
      capacity: 8,
      random: math.Random(seed),
    );
    particles.burst(
      ParticleEffect(
        count: count,
        lifetime: const Range(10.0, 10.0),
        size: const Range(0.8, 0.8),
        color: Vector4(1.0, 0.72, 0.30, 1.0),
        emitter: const SphereEmitter(speed: Range(0.0, 0.0)),
      ),
      Vector3(0.0, 0.6, 1.6),
    );
    return particles;
  }

  /// Eight particles in exactly the same place, which is the only thing
  /// `particle-one` leaves untested.
  ///
  /// One quad matches Impeller everywhere. Two hundred and twenty overlapping
  /// ones are five percent apart. Between those two facts sits addition — the
  /// same fragment written eight times into an HDR target, which is half-float
  /// on the hardware backends and float32 here. Stacked at one point with no
  /// spread, nothing else can differ.
  static ParticleSystem stackedParticles() => oneParticle(count: 8);

  /// A stand-in for something held in the player's hands.
  ///
  /// A plain box rather than a weapon, because what is being tested is that
  /// the overlay stage draws at all and is not clipped by the world — and a
  /// box placed deliberately inside the model proves the second half.
  static ViewModelNode viewModel(GraphicsDevice device) {
    final scene = Scene();
    final camera = CameraNode(
      // Narrower than the world camera, the way a real view model is.
      projection: const PerspectiveProjection(fovYRadians: 0.95),
    );
    scene.add(camera);
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(0.34, 0.2, 0.7)).build(),
        ),
        Material(
          name: 'view model',
          baseColor: Vector4(0.85, 0.30, 0.22, 1.0),
          roughness: 0.35,
        ),
        name: 'held',
      )..setPosition(0.32, -0.26, -0.9),
    );
    return ViewModelNode(scene: scene, camera: camera);
  }
}
