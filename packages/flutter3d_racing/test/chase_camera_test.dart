import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A car placed by hand, so that a test about the camera is not also a test
/// about the driving.
final class PlacedCar implements VehicleController {
  PlacedCar({
    Vector3? at,
    this.headingYaw = 0.0,
    Vector3? going,
    this.trackDistance = 0.0,
  }) : collider = Collider(
          shape: CollisionSphere(0.7),
          position: at ?? Vector3.zero(),
        ) {
    if (going != null) velocity.setFrom(going);
  }

  @override
  final Collider collider;

  @override
  Vector3 get position => collider.position;

  @override
  final Vector3 velocity = Vector3.zero();

  @override
  double headingYaw;

  @override
  Matrix3 get visualBasis => Matrix3.identity();

  @override
  double get speed => velocity.length;

  @override
  double slipAngle = 0.0;

  @override
  double slipRatio = 0.0;

  @override
  bool grounded = true;

  @override
  double rpm = 0.0;

  @override
  double trackDistance;

  @override
  void step(double dt, VehicleInput input) {}

  @override
  void placeAt(Vector3 at, double yaw, {double? trackDistance}) {
    collider.position.setFrom(at);
    headingYaw = yaw;
  }
}

/// Settles the camera, so that a test reads where it ended up rather than where
/// it was passing through.
void settle(ChaseCamera camera, PlacedCar car, {double seconds = 2.0}) {
  final steps = (seconds * 60).round();
  for (var i = 0; i < steps; i++) {
    camera.follow(car, 1 / 60);
  }
}

/// Where the camera is looking, as an angle.
double facing(ChaseCamera camera) {
  final look = camera.target - camera.eye;
  return math.atan2(look.x, look.z);
}

/// A floor with nothing on it, so that a test about the picture is not also a
/// test about a circuit.
final class _FlatGround implements GroundField {
  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    out
      ..s = position.z
      ..lateral = position.x
      ..onRoad = true
      ..barrier = false
      ..halfWidth = 0.0
      ..surface = 'asphalt'
      ..height = 0.0;
    out.normal.setValues(0.0, 1.0, 0.0);
    return true;
  }
}

void main() {
  group('where it sits', () {
    test('behind the car, above it, looking at it', () {
      final world = CollisionWorld();
      final camera = ChaseCamera(world: world);
      final car = PlacedCar(at: Vector3(0.0, 0.5, 0.0));

      settle(camera, car);

      // Facing +z at a heading of nought, so the camera is back along -z.
      expect(camera.eye.z, lessThan(car.position.z));
      expect(camera.eye.y, greaterThan(car.position.y));
      expect(camera.eye.distanceTo(car.position), closeTo(8.5, 1.0));
    });

    test('a car pointing the other way is followed from the other side', () {
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(at: Vector3.zero(), headingYaw: math.pi);

      settle(camera, car);

      expect(camera.eye.z, greaterThan(0.0));
    });

    test('the first frame is a cut, not a swoop across the circuit', () {
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(at: Vector3(300.0, 0.5, -120.0));

      camera.follow(car, 1 / 60);

      expect(camera.eye.distanceTo(car.position), lessThan(12.0));
    });
  });

  group('showing a slide', () {
    test('the camera sits behind where the car is going, not where it points',
        () {
      // Mutation: place the camera from `headingYaw` alone. A car sliding
      // sideways then stays pointing straight up the screen and the slide is
      // invisible — the one thing the player most needs to see is the one thing
      // the camera hides.
      final camera = ChaseCamera(world: CollisionWorld());
      // Nose straight ahead, travelling well off to the side: a drift.
      final car = PlacedCar(
        at: Vector3.zero(),
        going: Vector3(18.0, 0.0, 24.0),
      );

      settle(camera, car);

      final travelling = math.atan2(car.velocity.x, car.velocity.z);
      final behindNose = (camera.heading - car.headingYaw).abs();
      final behindTravel = (camera.heading - travelling).abs();

      expect(behindNose, greaterThan(0.1),
          reason: 'the camera should have swung off the nose');
      expect(behindTravel, lessThan(behindNose),
          reason: 'and swung most of the way towards the way it is going');
    });

    test('a stationary car does not spin the camera', () {
      // Mutation: read the direction of travel at any speed. A car at rest has
      // a velocity of rounding error, whose direction is anything at all, and a
      // camera reading it whips round on the grid.
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(at: Vector3.zero(), going: Vector3(1e-7, 0.0, -1e-7));

      settle(camera, car);

      expect(camera.heading, closeTo(car.headingYaw, 1e-9));
    });

    test('the nose is not ignored entirely', () {
      // The blend is deliberately short of one: a camera that only ever looks
      // where the car is going stops reporting where it is about to go.
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(
        at: Vector3.zero(),
        going: Vector3(20.0, 0.0, 20.0),
      );

      settle(camera, car);

      final travelling = math.atan2(car.velocity.x, car.velocity.z);
      expect((camera.heading - travelling).abs(), greaterThan(0.01));
    });
  });

  group('looking up the road', () {
    TrackSpline ring() {
      const points = 20;
      final positions = <Vector3>[
        for (var i = 0; i < points; i++)
          Vector3(
            60 * math.cos(2 * math.pi * i / points),
            0.0,
            60 * math.sin(2 * math.pi * i / points),
          ),
      ];
      return TrackSpline(
        centre: CatmullRom(positions),
        widths: List<double>.filled(points, 14.0),
        banks: List<double>.filled(points, 0.0),
      );
    }

    test('the aim leads into the corner rather than sitting on the car', () {
      // Mutation: aim at the car. The corner then arrives at the same moment
      // the car does, which is the moment it is too late to do anything about.
      final track = ring();
      final withTrack = ChaseCamera(world: CollisionWorld(), track: track);
      final without = ChaseCamera(world: CollisionWorld());

      final at = Vector3.zero();
      track.centreAt(0.0, at);
      final tangent = Vector3.zero();
      track.centre.tangentAt(0.0, tangent);

      PlacedCar car() => PlacedCar(
            at: at.clone()..y += 0.5,
            headingYaw: math.atan2(tangent.x, tangent.z),
            going: tangent * 25.0,
          );

      final leading = car();
      final plain = car();
      settle(withTrack, leading);
      settle(without, plain);

      expect(
        facing(withTrack) != facing(without),
        isTrue,
        reason: 'a camera that knows the circuit should aim differently on it',
      );

      // And the lead is towards the road ahead, not away from it.
      final ahead = Vector3.zero();
      track.centreAt(30.0, ahead);
      expect(
        withTrack.target.distanceTo(ahead),
        lessThan(plain.position.distanceTo(ahead)),
      );
    });

    test('without a circuit the camera still works', () {
      // Every vehicle test builds one of these: a car on a flat plane and no
      // track at all.
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(at: Vector3.zero(), going: Vector3(0.0, 0.0, 30.0));

      settle(camera, car);

      expect(camera.target.distanceTo(car.position), lessThan(3.0));
    });
  });

  group('the feeling of speed', () {
    test('the view widens with speed', () {
      // Mutation: a fixed field of view. Speed on a screen is not how fast the
      // numbers change, it is how fast the edges of the frame move — this is the
      // cheapest trick in the genre and the one that does the most.
      final slow = ChaseCamera(world: CollisionWorld());
      final fast = ChaseCamera(world: CollisionWorld());

      settle(slow, PlacedCar(going: Vector3(0.0, 0.0, 5.0)));
      settle(fast, PlacedCar(going: Vector3(0.0, 0.0, 50.0)));

      expect(fast.fov, greaterThan(slow.fov));
    });

    test('and stops widening before it becomes a fish-eye', () {
      final camera = ChaseCamera(world: CollisionWorld());

      settle(camera, PlacedCar(going: Vector3(0.0, 0.0, 400.0)));

      expect(camera.fov, lessThanOrEqualTo(const ChaseTuning().maxFov + 1e-9));
    });

    test('a boost widens it further, and it comes back', () {
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(going: Vector3(0.0, 0.0, 30.0));
      settle(camera, car);
      final resting = camera.fov;

      camera
        ..widen(0.25)
        ..follow(car, 1 / 60);
      expect(camera.fov, greaterThan(resting));

      settle(camera, car, seconds: 3.0);
      expect(camera.fov, closeTo(resting, 1e-3));
    });
  });

  group('walls', () {
    test('the camera does not end up inside the scenery', () {
      // The rig does the work; this is the racing camera asking it to.
      final world = CollisionWorld()
        ..add(
          Collider(
            shape: CollisionBox(Vector3(20.0, 6.0, 1.0)),
            position: Vector3(0.0, 3.0, -6.0),
          ),
        );
      final camera = ChaseCamera(world: world);
      final car = PlacedCar(at: Vector3(0.0, 0.5, 0.0));

      settle(camera, car);

      expect(camera.eye.z, greaterThan(-6.0));
    });
  });

  group('what the player sees', () {
    test('steering right takes the car to the right of the screen', () {
      // The claim in the form it is actually made — through a camera, in the
      // picture, where the player reads it. The two tests either side of this
      // one talk about world axes and a driver's terms; this one is the reason
      // those definitions were chosen, and it is the test that would have
      // caught the wheel being backwards on the first run rather than the
      // twentieth.
      final world = CollisionWorld();
      final camera = ChaseCamera(world: world);
      final car = SphereVehicle(
        world: world,
        ground: _FlatGround(),
        position: Vector3(0.0, 0.55, 0.0),
      );

      final input = VehicleInput()..throttle = 1.0;
      for (var i = 0; i < 120; i++) {
        car.step(1 / 60, input);
        camera.follow(car, 1 / 60);
      }

      // The camera is frozen where it was, so that the car moves in the frame
      // rather than the frame moving with the car.
      final view = makeViewMatrix(
        camera.eye.clone(),
        camera.target.clone(),
        Vector3(0.0, 1.0, 0.0),
      );
      final projection = makePerspectiveMatrix(camera.fov, 4 / 3, 0.3, 1000.0);
      // Typed: `Matrix4.operator*` returns `dynamic`, so `transform` below it
      // would be a call the compiler cannot check.
      final Matrix4 viewProjection = projection * view;

      input
        ..throttle = 0.6
        ..steer = 1.0;
      for (var i = 0; i < 45; i++) {
        car.step(1 / 60, input);
      }

      final clip = Vector4(car.position.x, car.position.y, car.position.z, 1.0);
      viewProjection.transform(clip);

      expect(
        clip.x / clip.w,
        greaterThan(0.05),
        reason: 'a positive wheel should put the car right of centre on screen',
      );
    });
  });

  group('cutting', () {
    test('a cut puts the camera behind the car at once', () {
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar(at: Vector3.zero());
      settle(camera, car);

      car.placeAt(Vector3(500.0, 0.5, 500.0), 0.0);
      camera
        ..cut()
        ..follow(car, 1 / 60);

      expect(camera.eye.distanceTo(car.position), lessThan(12.0));
    });

    test('a cut leaves nothing shaking', () {
      // A camera that arrives still shaking from the crash is a camera
      // reporting an event that has been undone.
      final camera = ChaseCamera(world: CollisionWorld());
      final car = PlacedCar();
      settle(camera, car);

      camera
        ..shake(2.0)
        ..widen(0.3)
        ..cut()
        ..follow(car, 1 / 60);

      expect(camera.rig.extraFov, 0.0);
      expect(camera.eye.distanceTo(camera.rig.eye), 0.0);
    });
  });
}
