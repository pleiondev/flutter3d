/// The solver hook: forces computed in Dart each step, before the core
/// steps — applied, left out when there are none, saved and restored, and
/// the same in two worlds.
///
///     dart test test/native_force_fields_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A steady push along x on one body, counting the steps it was asked for.
final class _Push extends NativeForceField {
  _Push(this.body);

  final NativeBody body;
  int applied = 0;

  @override
  String get name => 'push';

  @override
  void apply(NativeForceContext context) {
    applied++;
    context.addForce(body, Vector3(6.0, 0.0, 0.0));
  }

  @override
  Object? saveState() => <String, Object?>{'applied': applied};

  @override
  void restoreState(Object? state) =>
      applied = state is Map ? state['applied'] as int : 0;
}

/// Two bodies two metres apart, at rest, with nothing pulling them down.
(NativeWorld, NativeBody, NativeBody) _pair() {
  final world = NativeWorld()..gravity = Vector3.zero();
  addTearDown(world.dispose);
  final a = world.addBody(position: Vector3(-1.0, 0.0, 0.0));
  final b = world.addBody(position: Vector3(1.0, 0.0, 0.0));
  return (world, a, b);
}

NativeSpring _spring(NativeBody a, NativeBody b, {double? breakingForce}) =>
    NativeSpring(
      name: 'spring',
      a: a,
      b: b,
      restLength: 1.0,
      stiffness: 40.0,
      damping: 2.0,
      breakingForce: breakingForce,
    );

void main() {
  test('a field\'s force moves the body on the step it is applied to', () {
    final (world, a, _) = _pair();
    final fields = NativeForceFields(world)..add(_Push(a));
    fields.step(_dt);

    // Mutation: step the world before applying the fields. The force is
    // added after the step that should spend it, and the body is still.
    expect(world.velocityOf(a).x, greaterThan(0.0));
    expect(fields.steps, 1);
  });

  test('a spring pulls a stretched pair together, equal and opposite', () {
    final (world, a, b) = _pair();
    final fields = NativeForceFields(world)..add(_spring(a, b));
    for (var i = 0; i < 10; i++) {
      fields.step(_dt);
    }

    // Mutation: add the pull to both bodies with one sign. The pair drifts
    // off together instead of closing.
    expect(world.velocityOf(a).x, greaterThan(0.0));
    expect(world.velocityOf(b).x, lessThan(0.0));
    expect(
      (world.velocityOf(a) + world.velocityOf(b)).length,
      closeTo(0.0, 1e-4),
    );
  });

  test('with no field, the world steps and saves to the same bytes', () {
    final (plain, a, _) = _pair();
    final (hooked, b, _) = _pair();
    plain.addForce(a, Vector3(1.0, 2.0, 3.0));
    hooked.addForce(b, Vector3(1.0, 2.0, 3.0));
    final fields = NativeForceFields(hooked);
    for (var i = 0; i < 30; i++) {
      plain.step(_dt);
      fields.step(_dt);
    }

    // Mutation: count steps or touch the world with no field in it. The
    // hook is no longer free for the worlds that never use it.
    expect(hooked.snapshot(), plain.snapshot());
    expect(fields.steps, 0);
  });

  test('NativeDynamics saves what it always saved until a field is added', () {
    final world = CollisionWorld();
    final dynamics = NativeDynamics(world: world);
    addTearDown(dynamics.dispose);

    // Mutation: write `fields` whatever. Every save a game recorded before
    // this hook existed differs from the one it makes now.
    expect((dynamics.saveState()! as Map).containsKey('fields'), isFalse);
    final body = dynamics.native.addBody(position: Vector3.zero());
    dynamics
      ..keep(body)
      ..forceFields.add(_Push(body));
    expect((dynamics.saveState()! as Map).containsKey('fields'), isTrue);
  });

  test('a field\'s state comes back with the world', () {
    final (world, a, b) = _pair();
    final spring = _spring(a, b, breakingForce: 30.0);
    final fields = NativeForceFields(world)..add(spring);
    final whole = fields.saveState();
    final bytes = world.snapshot();
    fields.step(_dt);
    // Stretched a metre past its rest at 40 N/m: 40 N, past the 30 it holds.
    expect(spring.isBroken, isTrue);

    world.restore(bytes);
    fields.restoreState(whole);

    // Mutation: leave `restoreState` out of the spring, or out of the
    // fields. The restored world's spring stays broken, and a replay from
    // the save pulls nothing where the run it replays did.
    expect(spring.isBroken, isFalse);
    expect(fields.steps, 0);
    expect(fields.saveState(), whole);
  });

  test('two worlds given the same fields step to the same bits', () {
    List<int> run() {
      final (world, a, b) = _pair();
      final fields = NativeForceFields(world)
        ..add(_spring(a, b))
        ..add(_Push(a));
      for (var i = 0; i < 120; i++) {
        fields.step(_dt);
      }
      return world.snapshot();
    }

    // Mutation: apply the fields in an order that is not the order added
    // (a set, a map keyed by something else). The bytes can still agree by
    // luck; what this holds is that nothing in the hook reads a clock.
    expect(run(), run());
  });

  test('a second field of one name is refused', () {
    final (world, a, _) = _pair();
    final fields = NativeForceFields(world)..add(_Push(a));

    // Mutation: drop the check. Two fields would save under one key and
    // one of them would restore the other's state.
    expect(() => fields.add(_Push(a)), throwsArgumentError);
  });
}
