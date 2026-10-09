/// Virtual cameras: the framings, the director's priorities and blends, the
/// walls a blend passes, the shake seeded by the step, and the plugin that
/// runs it all in the frame phase `camera`.
///
///     dart test test/camera_test.dart
///
/// Each test was written against the mutation named in it: the change to the
/// package that would let it pass while the package was wrong.
library;

import 'dart:math' as math;

import 'package:flutter3d_camera/flutter3d_camera.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _frame = 1.0 / 60.0;

final class _Blast extends BusEvent {
  const _Blast(this.at);

  final Vector3 at;

  /// A step event is declared with its codec.
  static final EventCodec<_Blast> codec = EventCodec<_Blast>.of(
    encode: (event) => <double>[event.at.x, event.at.y, event.at.z],
    decode: (data, _) => switch (data) {
      [final num x, final num y, final num z] => _Blast(
        Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      ),
      _ => null,
    },
  );

  @override
  String get name => 'test.blast';
}

/// A camera that stands still at [eye], looking at [target].
VirtualCamera _still(
  String name,
  Vector3 eye,
  Vector3 target, {
  int priority = 0,
}) {
  final framing = LookAtFraming(from: eye, aim: Vector3.zero())
    ..subject.setFrom(target);
  return VirtualCamera(name, framing, priority: priority);
}

void main() {
  group('blends', () {
    test('an ease starts and stops gently and a cut is there at once', () {
      // Mutation: make `ease` the straight line. A blend would leave at full
      // speed, which reads as a fumbled cut.
      const ease = CameraBlend.ease(1.0);
      expect(ease.weight(0.0), 0.0);
      expect(ease.weight(0.5), closeTo(0.5, 1e-12));
      expect(ease.weight(1.0), 1.0);
      expect(ease.weight(0.1), lessThan(0.1));
      expect(const CameraBlend.linear(1.0).weight(0.1), closeTo(0.1, 1e-12));
      expect(CameraBlend.cut.isCut, isTrue);
      expect(CameraBlend.cut.weight(0.0), 1.0);
    });

    test('a custom curve that overshoots is held to the range', () {
      // Mutation: drop the clamp in `weight`. A springy curve would fling the
      // view past the camera it is blending to.
      final springy = CameraBlend.custom(1.0, (t) => t * 1.6, name: 'springy');
      expect(springy.weight(0.9), 1.0);
      expect(springy.weight(-1.0), 0.0);
      expect(springy.name, 'springy');
    });

    test('a shot blended halfway turns the view rather than sliding it', () {
      // Mutation: lerp the targets. Between two shots looking in opposite
      // directions the camera would look at the point between them — here,
      // at its own eye.
      final from = CameraShot(
        eye: Vector3.zero(),
        target: Vector3(0.0, 0.0, -10.0),
      );
      final to = CameraShot(
        eye: Vector3.zero(),
        target: Vector3(10.0, 0.0, 0.0),
      );
      final half = CameraShot()..blend(from, to, 0.5);
      final look = (half.target - half.eye)..normalize();
      expect(look.x, closeTo(math.sqrt1_2, 1e-6));
      expect(look.z, closeTo(-math.sqrt1_2, 1e-6));
      expect((half.target - half.eye).length, closeTo(10.0, 1e-4));

      final end = CameraShot()..blend(from, to, 1.0);
      expect((end.target - to.target).length, lessThan(1e-4));
    });
  });

  group('framings', () {
    test('a subject inside the dead zone moves on screen, not the camera', () {
      // Mutation: ignore `deadZone` in `_follow`. The camera would twitch
      // with every step of a walk.
      final framing = FollowFraming(deadZone: Vector3(1.0, 1.0, 1.0));
      final shot = CameraShot();
      framing.frame(shot, _frame);
      final eye = shot.eye.clone();

      framing.subject.setValues(0.8, 0.0, -0.5);
      framing.frame(shot, _frame);
      expect((shot.eye - eye).length, 0.0);

      // Out of the zone by half a metre: dragged by exactly that.
      framing.subject.setValues(1.5, 0.0, 0.0);
      framing.frame(shot, _frame);
      expect(framing.anchor.x, closeTo(0.5, 1e-6));
    });

    test('damping eases the anchor instead of snapping it', () {
      // Mutation: treat a damping rate as "at once". A tuned camera would
      // keep up with a fall as rigidly as an untuned one.
      final framing = FollowFraming(damping: Vector3(0.0, 4.0, 0.0));
      final shot = CameraShot();
      framing.frame(shot, _frame);
      framing.subject.setValues(2.0, -2.0, 0.0);
      framing.frame(shot, _frame);
      expect(framing.anchor.x, closeTo(2.0, 1e-6), reason: 'undamped axis');
      expect(framing.anchor.y, greaterThan(-2.0));
      expect(framing.anchor.y, lessThan(0.0));
    });

    test('a look-at camera stands still and turns to watch', () {
      // Mutation: move `from` with the subject. A security camera would walk
      // after the intruder.
      final framing = LookAtFraming(from: Vector3(0.0, 5.0, 0.0));
      final shot = CameraShot();
      framing.subject.setValues(10.0, 0.0, 0.0);
      framing.frame(shot, _frame);
      expect(shot.eye, Vector3(0.0, 5.0, 0.0));
      expect(shot.target.x, 10.0);
    });

    test('a group shot keeps every subject in the picture', () {
      // Mutation: use the full field of view rather than half of it in the
      // fit. The camera would stand at half the distance and cut both
      // subjects off at the edges.
      final framing = GroupFraming(
        targets: <FramedTarget>[
          FramedTarget(position: Vector3(-20.0, 0.0, 0.0)),
          FramedTarget(position: Vector3(20.0, 0.0, 0.0)),
        ],
        aspect: 1.0,
      );
      final shot = CameraShot();
      framing.frame(shot, _frame);
      final axis = (shot.target - shot.eye)..normalize();
      for (final target in framing.targets) {
        final to = (target.position - shot.eye)..normalize();
        final angle = math.acos(axis.dot(to).clamp(-1.0, 1.0));
        expect(angle, lessThan(shot.fovY / 2.0));
      }
      expect(framing.distance, greaterThan(20.0));
    });

    test('a first-person view is not smoothed and not pulled off a wall', () {
      // Mutation: give `FirstPersonFraming` a finite lag. The view would
      // trail the mouse, which is what makes people ill.
      final framing = FirstPersonFraming();
      final camera = VirtualCamera('eyes', framing);
      framing.eye.setValues(0.0, 1.7, 0.0);
      camera.update(_frame);
      framing.eye.setValues(3.0, 1.7, 0.0);
      framing.direction.setValues(1.0, 0.0, 0.0);
      camera.update(_frame);
      expect((camera.shot.eye - Vector3(3.0, 1.7, 0.0)).length, lessThan(1e-5));
      expect(
        (camera.shot.target - Vector3(4.0, 1.7, 0.0)).length,
        lessThan(1e-5),
      );
    });
  });

  group('presets keep the feel they came with', () {
    test('an orbit on a virtual camera is the rig and arithmetic it was', () {
      // Mutation: drop the cosine of the pitch from the eye's reach. The
      // camera would stand further back on every tilt than the game it came
      // from tuned it to.
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, 2.0, -2.0), Vector3(20.0, 8.0, 0.5));
      final framing = OrbitFraming(yaw: 0.3);
      final camera = VirtualCamera(
        'orbit',
        framing,
        rig: CameraRig(world: world),
      );
      final reference = CameraRig(world: world);

      for (var i = 0; i < 90; i++) {
        final runner = Vector3(i * 0.05, 0.0, -i * 0.02);
        final traveling = Vector3(3.0, 0.0, -1.2);
        framing
          ..subject.setFrom(runner)
          ..traveling = traveling;
        camera.update(_frame);

        // The arithmetic the third-person camera did before it was a preset.
        final target = runner.clone()..y += 1.2;
        target
          ..x += traveling.x * 0.34
          ..z += traveling.z * 0.34;
        final cosPitch = math.cos(framing.pitch);
        final eye = Vector3(
          target.x - math.sin(framing.yaw) * 7.0 * cosPitch,
          target.y + 2.6 - math.sin(framing.pitch) * 7.0,
          target.z - math.cos(framing.yaw) * 7.0 * cosPitch,
        );
        reference.place(
          desiredEye: eye,
          desiredTarget: target,
          lag: 9.0,
          dt: _frame,
        );
        expect(camera.shot.eye, reference.eye);
        expect(camera.shot.target, reference.target);
      }
    });

    test('a chase widens with speed and adds what the rig was asked for', () {
      // Mutation: leave `rig.extraFovY` out of the shot. A boost that widens
      // the view would show nothing.
      final framing = ChaseFraming();
      final camera = VirtualCamera('chase', framing);
      framing
        ..velocity.setValues(0.0, 0.0, 30.0)
        ..speed = 30.0;
      camera.update(_frame);
      expect(camera.shot.fovY, closeTo(1.05 + 30.0 * 0.006, 1e-9));
      camera.rig.widen(0.2);
      camera.update(_frame);
      expect(camera.shot.fovY, greaterThan(1.05 + 30.0 * 0.006 + 0.1));
    });

    test(
      'a chase sits behind the travel once fast and behind the nose slow',
      () {
        // Mutation: swap `headingFrom` and `headingTo`. A parked car would spin
        // its camera on rounding error.
        final framing = ChaseFraming()
          ..velocity.setValues(1e-4, 0.0, 0.0)
          ..speed = 1e-4;
        framing.frame(CameraShot(), _frame);
        expect(framing.heading, 0.0);

        framing
          ..velocity.setValues(20.0, 0.0, 0.0)
          ..speed = 20.0;
        framing.frame(CameraShot(), _frame);
        expect(framing.heading, closeTo(math.pi / 2.0 * 0.75, 1e-9));
      },
    );

    test('an overhead view is held to the ground and rides its height', () {
      // Mutation: clamp `pan` to the wrong axis's bounds. A long, narrow
      // map would let the view off its short side.
      final framing = OverheadFraming(
        minX: 0.0,
        minZ: 0.0,
        maxX: 100.0,
        maxZ: 10.0,
        groundHeight: (x, z) => x * 0.1,
      )..pan(500.0, 500.0);
      expect(framing.focus.x, 100.0);
      expect(framing.focus.z, 10.0);
      final shot = CameraShot();
      framing.frame(shot, _frame);
      expect(shot.target.y, closeTo(10.0, 1e-5));
      framing.zoom(-1000.0);
      expect(framing.distance, 12.0);
    });
  });

  group('the director', () {
    test('the highest priority is live, and a tie goes to the newest', () {
      // Mutation: break ties by the order added. Switching a camera on at
      // the same priority would do nothing.
      final director = CameraDirector(defaultBlend: CameraBlend.cut);
      final low = _still('low', Vector3(0.0, 1.0, 5.0), Vector3.zero());
      final high = _still(
        'high',
        Vector3(5.0, 1.0, 0.0),
        Vector3.zero(),
        priority: 2,
      );
      final also = _still(
        'also',
        Vector3(-5.0, 1.0, 0.0),
        Vector3.zero(),
        priority: 2,
      )..enabled = false;
      director
        ..add(low)
        ..add(high)
        ..add(also)
        ..update(_frame);
      expect(director.live, high);

      also.enabled = true;
      director.update(_frame);
      expect(director.live, also);

      also.enabled = false;
      high.enabled = false;
      director.update(_frame);
      expect(director.live, low);
      expect(director.shot.eye, Vector3(0.0, 1.0, 5.0));
    });

    test('a switch eases over the blend and ends on the new camera', () {
      // Mutation: start the blend at the new camera's shot. The ease would
      // be a cut with extra steps.
      final director = CameraDirector(
        defaultBlend: const CameraBlend.ease(0.5),
      );
      final a = _still('a', Vector3(0.0, 1.0, 10.0), Vector3.zero());
      final b = _still('b', Vector3(10.0, 1.0, 0.0), Vector3.zero());
      director
        ..add(a)
        ..update(_frame);
      expect(
        director.shot.eye,
        Vector3(0.0, 1.0, 10.0),
        reason: 'first: a cut',
      );

      director
        ..add(b)
        ..update(_frame);
      expect(director.isBlending, isTrue);
      expect(director.blendingFrom, a);
      expect(director.shot.eye.z, greaterThan(9.0));

      for (var i = 0; i < 40; i++) {
        director.update(_frame);
      }
      expect(director.isBlending, isFalse);
      expect(director.shot.eye, Vector3(10.0, 1.0, 0.0));
    });

    test('a pair blend beats the camera\'s own, which beats the default', () {
      // Mutation: look `blendIn` up before the pair table. A game could not
      // say "from the map to the battle, cut" for a camera that eases in from
      // everywhere else.
      final director = CameraDirector();
      final a = _still('a', Vector3(0.0, 1.0, 10.0), Vector3.zero());
      final b = _still('b', Vector3(10.0, 1.0, 0.0), Vector3.zero())
        ..blendIn = const CameraBlend.linear(2.0);
      final c = _still('c', Vector3(-10.0, 1.0, 0.0), Vector3.zero());
      director
        ..add(a)
        ..add(b)
        ..add(c)
        ..blendBetween('a', 'b', CameraBlend.cut)
        ..blendBetween('*', 'c', const CameraBlend.linear(3.0));
      expect(director.blendFor(a, b), CameraBlend.cut);
      expect(director.blendFor(c, b).name, 'linear');
      expect(director.blendFor(c, b).seconds, 2.0);
      expect(director.blendFor(a, c).seconds, 3.0);
      expect(director.blendFor(b, a), director.defaultBlend);
    });

    test('a blend interrupted blends on from where the view is', () {
      // Mutation: always blend from the previous live camera. A second switch
      // mid-blend would jump the view back to the first camera.
      final director = CameraDirector(
        defaultBlend: const CameraBlend.linear(1.0),
      );
      final a = _still('a', Vector3(0.0, 1.0, 10.0), Vector3.zero());
      final b = _still('b', Vector3(10.0, 1.0, 0.0), Vector3.zero());
      final c = _still('c', Vector3(0.0, 1.0, -10.0), Vector3.zero());
      director
        ..add(a)
        ..update(_frame)
        ..add(b);
      for (var i = 0; i < 30; i++) {
        director.update(_frame);
      }
      final before = director.shot.eye.clone();
      director
        ..add(c)
        ..update(_frame);
      expect(director.blendingFrom, isNull, reason: 'from a frozen shot');
      expect((director.shot.eye - before).length, lessThan(0.5));
    });

    test('a camera nobody kept up is cut into place when it goes live', () {
      // Mutation: drop the cut in `_switchTo`. The camera would ease in from
      // the origin, inside the blend, and the blend would aim at a lie.
      final director = CameraDirector(defaultBlend: CameraBlend.cut);
      final a = _still('a', Vector3(0.0, 1.0, 10.0), Vector3.zero());
      final framing = FollowFraming(offset: Vector3(0.0, 2.0, 6.0))
        ..subject.setValues(100.0, 0.0, 0.0);
      final b = VirtualCamera('b', framing)..enabled = false;
      director
        ..add(a)
        ..add(b)
        ..update(_frame);
      b.update(_frame); // placed once, at x = 100
      framing.subject.setValues(-100.0, 0.0, 0.0);
      for (var i = 0; i < 5; i++) {
        director.update(_frame);
      }
      b.enabled = true;
      director.update(_frame);
      expect(director.shot.eye.x, closeTo(-100.0, 1e-4));
    });

    test('a blend between two clear cameras is kept out of a wall', () {
      // Mutation: skip `_keepClear` on a blended shot. Halfway between two
      // cameras either side of a pillar, the view would be inside it.
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, 1.0, 5.0), Vector3(1.0, 4.0, 1.0));
      final director = CameraDirector(
        world: world,
        defaultBlend: const CameraBlend.linear(1.0),
      );
      final a = _still('a', Vector3(-8.0, 1.0, 10.0), Vector3.zero());
      final b = _still('b', Vector3(8.0, 1.0, 10.0), Vector3.zero());
      director
        ..add(a)
        ..update(_frame)
        ..add(b);
      for (var i = 0; i < 30; i++) {
        director.update(_frame);
      }
      final hit = RayHit();
      final toEye = director.shot.eye - director.shot.target;
      final reach = toEye.length;
      toEye.scale(1.0 / reach);
      expect(world.raycast(director.shot.target, toEye, reach, hit), isFalse);
    });

    test('two cameras of one name are refused', () {
      // Mutation: let `add` take a duplicate. A blend table keyed by name
      // would blend into whichever it met first.
      final director = CameraDirector()
        ..add(_still('a', Vector3(0, 0, 1), Vector3.zero()));
      expect(
        () => director.add(_still('a', Vector3(0, 0, 2), Vector3.zero())),
        throwsArgumentError,
      );
      expect(director.named('a'), isNotNull);
    });
  });

  group('the shake', () {
    Vector3 offsetAfter(ImpulseShake shake, double seconds) {
      final shot = CameraShot(eye: Vector3.zero(), target: Vector3(0, 0, -1));
      var t = 0.0;
      while (t < seconds - 1e-9) {
        shake.advance(_frame);
        t += _frame;
      }
      shake.apply(shot);
      return shot.eye;
    }

    test('the same step shakes the same way, a different step differently', () {
      // Mutation: seed the noise from a counter of impulses received. A
      // replay joined halfway would shake differently from the run.
      ImpulseShake shaken(int step) =>
          ImpulseShake(seed: 7)
            ..impulse(const CameraImpulse(amplitude: 1.0), step: step);
      final one = offsetAfter(shaken(120), 0.1);
      final again = offsetAfter(shaken(120), 0.1);
      final other = offsetAfter(shaken(121), 0.1);
      expect(one, again);
      expect((one - other).length, greaterThan(1e-4));
    });

    test('it starts from still and dies away', () {
      // Mutation: use value noise, which is not nought at the start. The
      // view would jump on the frame the blow landed.
      final shake = ImpulseShake()
        ..impulse(const CameraImpulse(amplitude: 1.0, seconds: 0.3), step: 1);
      final shot = CameraShot(eye: Vector3.zero(), target: Vector3(0, 0, -1));
      shake.apply(shot);
      expect(shot.eye.length, 0.0);
      expect(offsetAfter(shake, 0.1).length, greaterThan(0.0));
      offsetAfter(shake, 0.3);
      expect(shake.isShaking, isFalse);
    });

    test(
      'far from the blast it is felt less, and the motion setting holds',
      () {
        // Mutation: ignore `strengthAt`. A blast across the map would rattle
        // the view as hard as one underfoot.
        final at = Vector3(0.0, 0.0, 0.0);
        final near = ImpulseShake()
          ..impulse(
            CameraImpulse(amplitude: 1.0, at: at, radius: 20.0),
            step: 3,
            eye: Vector3(1.0, 0.0, 0.0),
          );
        final far = ImpulseShake()
          ..impulse(
            CameraImpulse(amplitude: 1.0, at: at, radius: 20.0),
            step: 3,
            eye: Vector3(19.0, 0.0, 0.0),
          );
        final beyond = ImpulseShake()
          ..impulse(
            CameraImpulse(amplitude: 1.0, at: at, radius: 20.0),
            step: 3,
            eye: Vector3(25.0, 0.0, 0.0),
          );
        expect(
          offsetAfter(far, 0.1).length,
          lessThan(offsetAfter(near, 0.1).length),
        );
        expect(beyond.isShaking, isFalse);

        final off = ImpulseShake(motion: 0.0)
          ..impulse(const CameraImpulse(amplitude: 1.0), step: 3);
        expect(off.isShaking, isFalse);
      },
    );
  });

  group('the plugin', () {
    test('it places the cameras in the frame phase and shakes on events', () {
      // Mutation: add the system to a step phase. A view plugin would be
      // refused, and a camera would move inside a rollback.
      final director = CameraDirector()
        ..add(_still('a', Vector3(0.0, 2.0, 10.0), Vector3.zero()));
      final impulses = ImpulseTable()
        ..on<_Blast>((e) => CameraImpulse(amplitude: 0.5, at: e.at));
      final plugin = CameraPlugin(director, impulses: impulses);
      expect(plugin.manifest.touches, PluginTouches.view);
      expect(plugin.manifest.idProblem, isNull);
      expect(impulses.types, <Type>[_Blast]);

      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      loop.events.declare<_Blast>('test.blast', codec: _Blast.codec);
      var published = false;
      loop.addSystem('blast once', LoopPhase.rules, (c) {
        if (published) return;
        published = true;
        c.publish(_Blast(Vector3(0.0, 0.0, 9.0)));
      });
      loop.frame(_frame);
      expect(director.live?.name, 'a');
      expect(director.shake.isShaking, isTrue);
      loop.frame(_frame);
      expect(director.shake.count, 1, reason: 'one blast, one impulse');
    });
  });
}
