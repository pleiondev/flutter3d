import 'package:vector_math/vector_math.dart';

import '../physics/collider.dart';
import '../physics/collision_shape.dart';
import '../physics/collision_world.dart';
import 'blast.dart';

/// One rocket in flight.
///
/// Plain fields and a live flag rather than an object per shot: a projectile
/// exists for a second or two and dozens are in the air during a firefight,
/// which is exactly the shape a pool is for.
final class Projectile {
  final Vector3 position = Vector3.zero();
  final Vector3 velocity = Vector3.zero();

  late Blast blast;

  /// Who fired it. Ignored while sweeping, because the muzzle is inside them.
  Collider? owner;

  /// Seconds left before it gives up and detonates.
  double life = 0.0;

  bool alive = false;
}

/// Where and what an explosion was.
final class Detonation {
  Detonation({
    required Vector3 position,
    required Vector3 normal,
    required this.blast,
    required this.damage,
    required this.owner,
  })  : position = position.clone(),
        normal = normal.clone();

  final Vector3 position;

  /// Surface the rocket struck, or the direction it came from when it timed
  /// out in the open. Effects need somewhere to face.
  final Vector3 normal;

  final Blast blast;

  /// Everything hurt, and by how much. Includes the shooter.
  final Map<Collider, double> damage;

  final Collider? owner;
}

/// Everything currently in the air.
///
/// ## Swept, not stepped
///
/// A rocket travels forty metres a second, which is two thirds of a metre
/// between one simulation step and the next — further than a wall is thick. A
/// projectile moved by adding velocity and then asked whether it is inside
/// something passes cleanly through thin geometry, and the faster the
/// projectile the more reliably it does so. Every move is a sweep.
///
/// ## Fixed pool
///
/// A projectile that cannot be spawned is dropped rather than growing the
/// pool. Sixty-four rockets in the air at once is already far past anything the
/// game produces, and a pool that grows under load is a pool that allocates
/// during the exact frame that was already struggling.
final class ProjectileSystem {
  ProjectileSystem({
    required this.world,
    int capacity = 64,
    this.radius = 0.12,
  })  : _resolver = BlastResolver(world),
        _pool = List<Projectile>.generate(
          capacity,
          (_) => Projectile(),
          growable: false,
        );

  final CollisionWorld world;

  /// How fat a rocket is, for the sweep. Not zero: a point squeezes through the
  /// seam between two brushes that meet exactly.
  final double radius;

  final List<Projectile> _pool;
  final BlastResolver _resolver;

  /// Explosions produced by the last [step], for the game to react to.
  ///
  /// Reported rather than applied here: this knows how far a blast reaches, and
  /// nothing about health, death animations or sound.
  final List<Detonation> detonations = <Detonation>[];

  /// Rockets dropped because the pool was full. Worth watching rather than
  /// hiding — a number that climbs means the cap is wrong.
  int get dropped => _dropped;
  int _dropped = 0;

  int get activeCount {
    var count = 0;
    for (final projectile in _pool) {
      if (projectile.alive) count++;
    }
    return count;
  }

  final SweepHit _hit = SweepHit();
  final Vector3 _delta = Vector3.zero();
  final Vector3 _normal = Vector3.zero();

  /// Launches one. Returns false when the pool was full.
  bool spawn({
    required Vector3 position,
    required Vector3 direction,
    required double speed,
    required Blast blast,
    Collider? owner,
    double life = 6.0,
  }) {
    for (final projectile in _pool) {
      if (projectile.alive) continue;
      projectile
        ..alive = true
        ..life = life
        ..blast = blast
        ..owner = owner
        ..position.setFrom(position);
      projectile.velocity
        ..setFrom(direction)
        ..normalize()
        ..scale(speed);
      return true;
    }
    _dropped++;
    return false;
  }

  void clear() {
    for (final projectile in _pool) {
      projectile.alive = false;
    }
    detonations.clear();
  }

  void step(double dt) {
    detonations.clear();
    final shape = CollisionSphere(radius);

    for (final projectile in _pool) {
      if (!projectile.alive) continue;

      projectile.life -= dt;
      if (projectile.life <= 0.0) {
        _normal
          ..setFrom(projectile.velocity)
          ..normalize()
          ..scale(-1.0);
        _detonate(projectile, projectile.position, _normal);
        continue;
      }

      _delta
        ..setFrom(projectile.velocity)
        ..scale(dt);

      if (!world.sweep(
        shape,
        projectile.position,
        _delta,
        _hit,
        ignore: projectile.owner,
      )) {
        projectile.position.add(_delta);
        continue;
      }

      // Stop just short of the surface, so the explosion happens in the room
      // rather than inside the wall — which would put the geometry between the
      // blast and everything it should have hurt.
      final travel = _hit.fraction;
      projectile.position
        ..x += _delta.x * travel + _hit.normal.x * 0.02
        ..y += _delta.y * travel + _hit.normal.y * 0.02
        ..z += _delta.z * travel + _hit.normal.z * 0.02;

      _detonate(projectile, projectile.position, _hit.normal);
    }
  }

  void _detonate(Projectile projectile, Vector3 at, Vector3 normal) {
    projectile.alive = false;
    final damage = <Collider, double>{};
    _resolver.resolve(projectile.blast, at, damage);
    detonations.add(
      Detonation(
        position: at,
        normal: normal,
        blast: projectile.blast,
        damage: damage,
        owner: projectile.owner,
      ),
    );
  }
}
