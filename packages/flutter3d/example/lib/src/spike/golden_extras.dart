import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
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

  /// A stand-in for something held in the player's hands.
  ///
  /// A plain box rather than a weapon, because what is being tested is that
  /// the overlay stage draws at all and is not clipped by the world — and a
  /// box placed deliberately inside the model proves the second half.
  static ViewModelPlugin viewModel() {
    final scene = Scene();
    final camera = CameraNode(
      // Narrower than the world camera, the way a real view model is.
      projection: const PerspectiveProjection(fovYRadians: 0.95),
    );
    scene.add(camera);
    scene.add(
      MeshNode(
        GpuMesh.upload(CuboidShape(size: Vector3(0.34, 0.2, 0.7)).build()),
        Material(
          name: 'view model',
          baseColor: Vector4(0.85, 0.30, 0.22, 1.0),
          roughness: 0.35,
        ),
        name: 'held',
      )..setPosition(0.32, -0.26, -0.9),
    );
    return ViewModelPlugin(scene: scene, camera: camera);
  }
}
