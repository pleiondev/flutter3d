/// The native core five kilometres from the site origin: the same small
/// scene — a crate dropped on a floor until it rests, a bob swinging on a
/// hinge — stepped for ten seconds at 60 Hz at the origin and at a site 5 km
/// out along each axis and along all three. The core is float32 relative to
/// its own origin, so the far runs first move that origin to the site
/// rounded to whole metres, as the view's origin shift does, and the
/// measure is the largest distance, over every step, between a body's
/// place in the world and where the run at the origin has it, carried out
/// to the site.
///
/// **The numbers, for CONTRACTS and the twin page** (measured on a laptop):
///
/// * the scene placed relative to the shifted origin: within 0.02 mm
///   (measured: 0.006 mm, the hinge's);
/// * the scene placed at 5 km in float32 and only then shifted: within
///   4 mm (measured: 1.7 mm), the placement's rounding — half of float32's
///   0.5 mm spacing out there — lengthening the hinge's arm and the swing
///   drifting by it;
/// * the scene a kilometre from the origin for the second five seconds, as
///   when the camera watches it from that far: within 2 mm (measured:
///   1.0 mm);
/// * no shift at all: out by more than the first bound (measured: up to
///   41 mm).
///
///     dart test test/far_origin_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;
const int _steps = 600;

/// The bound a scene placed relative to the shifted origin is held to, in
/// metres: the number CONTRACTS states.
const double _bound = 2e-5;

/// Where the scene's own (0, 0, 0) is in the world ([site]); where the
/// world's origin is moved before the scene is built ([origin]), after it
/// ([built]), and halfway through the run ([halfway]), each when given.
typedef _Placement = ({
  WorldPosition site,
  WorldPosition? origin,
  WorldPosition? built,
  WorldPosition? halfway,
});

/// The scene's bodies' places in the world after each step: the crate's,
/// then the bob's, per step.
List<WorldPosition> _run(_Placement placement) {
  final world = NativeWorld()..setAir(temperature: 293.15, density: 1e-30);
  try {
    if (placement.origin case final o?) world.moveOriginTo(o);
    // A place in the scene, in the world's frame: the site plus [x, y, z],
    // taken in doubles relative to the origin and narrowed once.
    Vector3 at(double x, double y, double z) =>
        placement.site.translated(x, y, z).toVector3Relative(world.origin);

    final floor = world.addBody(
      position: at(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(20.0, 0.5, 20.0)));
    final crate = world.addBody(position: at(0.3, 1.5, -0.2));
    world.setShape(crate, NativeShape.box(Vector3.all(0.5)));

    const swing = 0.4;
    final pivot = world.addBody(
      position: at(4.0, 3.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final bob = world.addBody(
      position: at(4.0 + math.sin(swing), 3.0 - math.cos(swing), 0.0),
    );
    world
      ..setShape(bob, const NativeShape.sphere(0.05))
      ..createJoint(
        NativeJointType.revolute,
        pivot,
        bob,
        anchor: at(4.0, 3.0, 0.0),
        axis: Vector3(0.0, 0.0, 1.0),
      );
    if (placement.built case final o?) world.moveOriginTo(o);

    return <WorldPosition>[
      for (var i = 0; i < _steps; i++)
        ...() {
          if (i == _steps ~/ 2) {
            if (placement.halfway case final o?) world.moveOriginTo(o);
          }
          world.step(_dt);
          return <WorldPosition>[
            world.positionOf(crate),
            world.positionOf(bob),
          ];
        }(),
    ];
  } finally {
    world.dispose();
  }
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
  final near = _run((
    site: WorldPosition.origin,
    origin: null,
    built: null,
    halfway: null,
  ));

  test('at the origin the crate comes to rest and the bob still swings', () {
    final crate = near[near.length - 2], bob = near[near.length - 1];
    expect(crate.y, closeTo(0.5, 0.01));
    expect(near[near.length - 4].y, closeTo(crate.y, 1e-6));
    expect((bob.x - 4.0).abs(), greaterThan(0.01));
  });

  for (final MapEntry(key: axis, value: site) in sites.entries) {
    group('5 km out along $axis', () {
      test('placed relative to the shifted origin, within 0.02 mm', () {
        final far = _run((
          site: site,
          origin: _rounded(site),
          built: null,
          halfway: null,
        ));
        expect(_error(near, far, site), lessThan(_bound));
      });

      test('placed in float32 out there first, it keeps that rounding', () {
        final far = _run((
          site: site,
          origin: null,
          built: _rounded(site),
          halfway: null,
        ));
        expect(_error(near, far, site), lessThan(4e-3));
      });

      test('a kilometre from the origin, within 2 mm', () {
        // Mutation: hand `f3d_world_shift_origin` the new origin rather
        // than the difference in `NativeWorld.moveOriginTo` — the second
        // move lands the scene 5 km off.
        final far = _run((
          site: site,
          origin: _rounded(site),
          built: null,
          halfway: _rounded(site).translated(-700.0, 400.0, 500.0),
        ));
        expect(_error(near, far, site), lessThan(2e-3));
      });

      test('without the shift it is out by more than the bound', () {
        final far = _run((
          site: site,
          origin: null,
          built: null,
          halfway: null,
        ));
        expect(_error(near, far, site), greaterThan(_bound));
      });
    });
  }
}
