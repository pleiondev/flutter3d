import 'particle.dart';
import 'particle_affector.dart';

/// Stops particles at a level floor, and throws them back up off it.
///
/// **The collision this package can do, and the one it says it cannot.** A
/// particle here is simulated on the CPU, before the frame it is drawn in has
/// a depth buffer, so colliding with the scene's depth — what a GPU particle
/// system does — has nothing to read. What every effect that lands still
/// needs is the floor: a splash that falls through the water it came out of,
/// or sparks that sink into the stone they bounced off, is the tell. A plane
/// at a height is that, and it is exact rather than a guess at the depth a
/// frame might have had.
///
/// An effect document asking for `"against": "depth"` is read and told that
/// this build has no such collision (see `EffectDescription.unsupported`),
/// rather than refused or quietly drawn as something else.
///
/// **Checked before the particle moves**, which is when an affector runs: a
/// particle that would cross the plane during this step has its fall turned
/// into a rise by [bounce] instead, and one already below it — born there, or
/// pushed there by something else — is put back on it.
final class ParticlePlaneCollision extends ParticleAffector {
  const ParticlePlaneCollision({
    this.height = 0.0,
    this.bounce = 0.0,
    this.friction = 0.0,
  }) : assert(
         bounce >= 0.0,
         'a bounce is a fraction of the fall, never below 0',
       ),
       assert(
         friction >= 0.0 && friction <= 1.0,
         'friction is the fraction of the sideways speed one landing takes',
       );

  /// The floor's height on the y axis, metres.
  final double height;

  /// The fraction of its falling speed a particle keeps going up again: 0
  /// lands dead, 1 bounces as high as it fell.
  final double bounce;

  /// The fraction of its sideways speed a particle loses each landing.
  final double friction;

  @override
  void apply(Particle particle, double dt) {
    final position = particle.position;
    final velocity = particle.velocity;
    if (position.y < height) position.y = height;
    if (velocity.y >= 0.0 || position.y + velocity.y * dt >= height) return;
    velocity
      ..y = -velocity.y * bounce
      ..x *= 1.0 - friction
      ..z *= 1.0 - friction;
  }
}
