/// The Dart physics core five kilometres from the site origin, through the
/// loop's origin shift: the same small scene — a crate dropped on a floor
/// until it rests, a crate sliding to a stop on it — stepped by an
/// [EngineLoop] for ten seconds at 60 Hz at the origin and at a site 5 km
/// out along each axis and along all three, under both profiles. The far
/// runs move the loop's origin to the site rounded to whole metres, as the
/// view's shift does, and [EngineLoop.shiftsPhysics] carries the collision
/// world along. The measure is the largest distance, over every step,
/// between a body's place in the world and where the run at the origin has
/// it, carried out to the site.
///
/// The Dart core has no joints, so the native core's `far_origin_test.dart`
/// holds the hinge. Its colliders are float32 under both profiles; the
/// accurate profile keeps doubles beside them only while they still round
/// to the float32 values, so an origin shift starts it again from those.
///
/// **The numbers, for CONTRACTS and the twin page** (measured on a laptop):
///
/// * the scene placed relative to the shifted origin: within 0.02 mm, the
///   native core's bound (measured: 0.0004 mm);
/// * the scene placed at 5 km in float32 and only then shifted: within
///   0.5 mm (measured: 0.27 mm), the placement's rounding;
/// * the scene a kilometre from the origin for the second five seconds:
///   within 0.1 mm (measured: 0.026 mm);
/// * no shift at all: out by more than the first bound (measured: 4 mm
///   under the deterministic profile, 0.4 mm under the accurate one).
///
///     dart test test/far_origin_physics_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _steps = 600;

/// The bound a scene placed relative to the shifted origin is held to, in
/// metres: the number CONTRACTS states.
const double _bound = 2e-5;

/// Where the scene's own (0, 0, 0) is in the world ([site]); where the
/// loop's origin is moved before the scene is built ([origin]), after it
/// ([built]), and halfway through the run ([halfway]), each when given.
typedef _Placement = ({
  WorldPosition site,
  WorldPosition? origin,
  WorldPosition? built,
  WorldPosition? halfway,
});

/// The scene's bodies' places in the world after each step: the dropped
/// crate's, then the sliding one's, per step.
List<WorldPosition> _run(_Placement placement, SimulationProfile profile) {
  final loop = EngineLoop(input: InputState(), profile: profile);
  final world = CollisionWorld();
  final dynamics = Dynamics(
    world: world,
    gravity: Vector3(0.0, -9.81, 0.0),
    profile: profile,
  );
  loop.shiftsPhysics(world);
  if (placement.origin case final o?) loop.shiftOrigin(o);
  // A place in the scene, in the loop's frame: the site plus [x, y, z],
  // taken in doubles relative to the origin and narrowed once.
  Vector3 at(double x, double y, double z) =>
      placement.site.translated(x, y, z).toVector3Relative(loop.origin);

  world.add(
    Collider(
      shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
      position: at(0.0, -0.5, 0.0),
      kind: ColliderKind.static,
    ),
  );
  final dropped = dynamics.add(
    RigidBody(
      world: world,
      shape: CollisionBox(Vector3.all(0.5)),
      position: at(0.3, 1.5, -0.2),
    ),
  );
  final sliding = dynamics.add(
    RigidBody(
      world: world,
      shape: CollisionBox(Vector3.all(0.25)),
      position: at(4.0, 0.25, 0.0),
    ),
  );
  sliding.velocity.setValues(3.0, 0.0, 1.5);
  if (placement.built case final o?) loop.shiftOrigin(o);

  final places = <WorldPosition>[];
  loop
    ..addSystem('physics', LoopPhase.physics, (c) {
      if (c.step == _steps ~/ 2) {
        if (placement.halfway case final o?) loop.shiftOrigin(o);
      }
      dynamics.step(c.dt);
    })
    ..addSystem('record', LoopPhase.publish, (_) {
      places
        ..add(dropped.position.toWorldPosition(origin: loop.origin))
        ..add(sliding.position.toWorldPosition(origin: loop.origin));
    });
  while (places.length < 2 * _steps) {
    loop.frame(loop.stepSeconds);
  }
  return places;
}

/// The largest distance between [far]'s places, taken back from [site],
/// and [near]'s.
double _error(
  List<WorldPosition> near,
  List<WorldPosition> far,
  WorldPosition site,
) => <double>[
  for (var i = 0; i < near.length; i++)
    () {
      final (:x, :y, :z) = far[i].relativeTo(site);
      final n = near[i];
      return math.sqrt(
        (x - n.x) * (x - n.x) + (y - n.y) * (y - n.y) + (z - n.z) * (z - n.z),
      );
    }(),
].reduce(math.max);

/// [site] rounded to whole metres, as the view rounds the camera's place.
WorldPosition _rounded(WorldPosition site) => WorldPosition(
  site.x.roundToDouble(),
  site.y.roundToDouble(),
  site.z.roundToDouble(),
);

void main() {
  const sites = <String, WorldPosition>{
    'x': WorldPosition(5000.37, 0.0, 0.0),
    'y': WorldPosition(0.0, 5000.37, 0.0),
    'z': WorldPosition(0.0, 0.0, 5000.37),
    'all three': WorldPosition(5000.37, 5000.62, 4999.71),
  };
  for (final profile in <SimulationProfile>[
    SimulationProfile.deterministic,
    SimulationProfile.accurate,
  ]) {
    group('under ${profile.name}', () {
      final near = _run((
        site: WorldPosition.origin,
        origin: null,
        built: null,
        halfway: null,
      ), profile);

      test('at the origin both crates come to rest on the floor', () {
        final dropped = near[near.length - 2], sliding = near[near.length - 1];
        expect(dropped.y, closeTo(0.5, 0.03));
        expect(sliding.y, closeTo(0.25, 0.03));
        expect(sliding.x, greaterThan(4.1));
        expect(near[near.length - 3], sliding);
      });

      for (final MapEntry(key: axis, value: site) in sites.entries) {
        group('5 km out along $axis', () {
          test('placed relative to the shifted origin, within 0.02 mm', () {
            final far = _run((
              site: site,
              origin: _rounded(site),
              built: null,
              halfway: null,
            ), profile);
            expect(_error(near, far, site), lessThan(_bound));
          });

          test('placed in float32 out there first, it keeps that '
              'rounding', () {
            final far = _run((
              site: site,
              origin: null,
              built: _rounded(site),
              halfway: null,
            ), profile);
            expect(_error(near, far, site), lessThan(5e-4));
          });

          test('a kilometre from the origin, within 0.1 mm', () {
            // Mutation: leave `shiftsPhysics` out — the colliders stay in
            // the frame of the first origin while the loop reads them in
            // the second.
            final far = _run((
              site: site,
              origin: _rounded(site),
              built: null,
              halfway: _rounded(site).translated(-700.0, 400.0, 500.0),
            ), profile);
            expect(_error(near, far, site), lessThan(1e-4));
          });

          test('without the shift it is out by more than the bound', () {
            final far = _run((
              site: site,
              origin: null,
              built: null,
              halfway: null,
            ), profile);
            expect(_error(near, far, site), greaterThan(_bound));
          });
        });
      }
    });
  }
}
