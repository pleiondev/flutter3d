import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A solver that has nothing worked out until it is let, as one on another
/// isolate is before its answer comes.
final class _Later extends LiquidShapeSolver {
  bool ready = false;
  int asked = 0;

  @override
  bool get answersAtOnce => false;

  @override
  SurfaceModes? surfaceModes(SurfaceModesRequest request) {
    asked++;
    return ready ? super.surfaceModes(request) : null;
  }

  @override
  TubeMeniscus? meniscus(MeniscusRequest request) =>
      ready ? super.meniscus(request) : null;
}

LiquidBody _tube({double fill = 0.05}) => LiquidBody(
  shape: RevolvedVessel([
    Vector2(0, 0),
    Vector2(0.008, 0),
    Vector2(0.008, 0.1),
  ]),
  medium: FluidMedium.water,
  volume: 3.14159 * 0.008 * 0.008 * fill,
  modes: 4,
);

void main() {
  test('one cross-section is solved once, for every vessel', () {
    // Two tubes of one bore and a third filled higher: one cut, one solve,
    // the same modes handed to all three. Mutation: key the cache by the
    // vessel, and each solves its own.
    LiquidShapeCache.shared.clear();
    final tubes = [_tube(), _tube(), _tube(fill: 0.07)];
    for (final tube in tubes) {
      tube.place(Matrix3.identity(), Vector3.zero());
    }
    final first = tubes.first.surface.wavenumbers;
    expect(first, isNotEmpty);
    for (final tube in tubes.skip(1)) {
      expect(tube.surface.wavenumbers, first);
    }
  });

  test('a surface whose modes are still being worked out keeps its own', () {
    // The answer has not come: the surface rings on the grid it had, and
    // takes the new one when it comes. Mutation: lay the new grid out with
    // no modes, and the waves vanish while the solver works.
    LiquidShapeCache.shared.clear();
    final tube = _tube()..place(Matrix3.identity(), Vector3.zero());
    final before = tube.surface.wavenumbers;
    final later = _Later();
    tube.shapes = later;
    // Turned well past what keeps the modes: a new cut is asked for.
    final turned = Matrix3.rotationZ(0.4);
    var time = 0.0;
    void run() {
      for (var i = 0; i < 60; i++) {
        time += 1 / 240;
        tube
          ..place(turned, Vector3.zero(), time: time)
          ..step(1 / 240, gravity: Vector3(0, -9.81, 0));
      }
    }

    run();
    expect(later.asked, greaterThan(0));
    expect(tube.surface.wavenumbers, before);
    later.ready = true;
    run();
    expect(tube.surface.wavenumbers, isNot(before));
  });

  test('a world that must replay takes only answers given at once', () {
    expect(
      () => FluidWorld(gravity: Vector3(0, -9.81, 0), shapes: _Later()),
      throwsArgumentError,
    );
    expect(
      FluidWorld(
        gravity: Vector3(0, -9.81, 0),
        shapes: _Later(),
        profile: SimulationProfile.accurate,
      ).shapes,
      isA<_Later>(),
    );
  });

  test('a meniscus is one for every vessel of its liquid and gravity', () {
    LiquidShapeCache.shared.clear();
    final request = MeniscusRequest(
      medium: FluidMedium.water,
      radius: 0.004,
      g: 9.81,
    );
    final first = LiquidShapeSolver.immediate.meniscus(request);
    expect(LiquidShapeSolver.immediate.meniscus(request), same(first));
    // It climbs water's wetted glass: Jurin's height, roughly.
    expect(first!.wallRise, greaterThan(0.0));
  });
}
