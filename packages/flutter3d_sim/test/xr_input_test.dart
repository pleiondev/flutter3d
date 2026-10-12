/// What an XR session hands the simulation: the runtime's display time as
/// the loop's clock, poses as external input on the tape, and controls as
/// sources of actions.
///
///     dart test test/xr_input_test.dart
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const Duration _period = Duration(microseconds: 16667);

/// A head that walks and turns a little every step, with numbers no
/// decimal writes exactly.
RigidPose _headAt(int step) => RigidPose(
  position: Vector3(0.1 * step, 1.6 + math.sin(step / 7), -0.03 * step),
  orientation: Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), step / 11),
);

/// Where the head is seen at each step, as a system reading [XrPoses].
List<RigidPose?> _heads(EngineLoop loop, int steps) => <RigidPose?>[
  for (var i = 0; i < steps; i++)
    (loop..runSteps(1)).world.resource<XrPoses>()?.head,
];

void main() {
  group('display time', () {
    test('a frame brings the gap between two predicted display times', () {
      final time = TimeSource.display() as DisplayTime;
      expect(
        time.elapsed(FrameSpan(from: Duration.zero, to: _period)),
        0.0,
        reason: 'none yet',
      );
      time.predict(100.0);
      expect(
        time.elapsed(FrameSpan(from: Duration.zero, to: _period)),
        0.0,
        reason: 'the first',
      );
      time.predict(100.0125);
      // Mutation: hand the vsync gap instead of the runtime's.
      expect(
        time.elapsed(FrameSpan(from: _period, to: _period * 2)),
        closeTo(0.0125, 1e-12),
      );
      expect(
        time.elapsed(FrameSpan(from: _period * 2, to: _period * 3)),
        0.0,
        reason: 'no new',
      );
      time.predict(100.05);
      expect(
        time.elapsed(FrameSpan(from: _period * 3, to: _period * 4)),
        closeTo(0.0375, 1e-12),
      );
      expect(() => time.predict(99.0), throwsArgumentError);
      expect(() => time.predict(double.nan), throwsArgumentError);
      time
        ..reset()
        ..predict(3.0);
      expect(time.elapsed(FrameSpan(from: Duration.zero, to: _period)), 0.0);
    });

    test('the loop steps by the display times and keeps its fixed step', () {
      final time = DisplayTime();
      final loop = EngineLoop(input: InputState())..time = time;
      final dt = loop.stepSeconds;
      time.predict(10.0);
      expect(loop.frameAtVsync(Duration.zero), 0);
      // A 90 Hz headset's frames, two steps' worth in three frames: the
      // step does not stretch to the display's.
      time.predict(10.0 + 3 * dt);
      expect(loop.frameAtVsync(_period * 500), 3);
      expect(loop.stepSeconds, dt);
    });
  });

  group('poses', () {
    test('a pose is seven numbers and back, bit for bit', () {
      final pose = _headAt(13);
      final input = pose.toInput(XrPoseSources.head, displayTime: 4.5);
      expect(input.value, hasLength(7));
      expect(input.kind, ReadingKind.predicted);
      expect(input.sourceTime, 4.5);
      final back = XrPoseInput.fromInput(
        ExternalStateInput.fromJson(jsonDecode(jsonEncode(input.toJson()))),
      );
      expect(back, pose);
      expect(
        () => RigidPose.fromComponents(<double>[1, 2, 3]),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('the sources are spelled once', () {
      expect(XrPoseSources.grip(XrHand.left), 'xr.left.grip');
      expect(XrPoseSources.aim(XrHand.right), 'xr.right.aim');
      expect(
        XrPoseSources.joint(XrHand.left, XrHandJoint.indexTip),
        'xr.left.hand.indexTip',
      );
      expect(XrPoseSources.isPose(XrPoseSources.head), isTrue);
      expect(XrPoseSources.isPose('tank.level'), isFalse);
      expect(XrHandJoint.values, hasLength(26));
      expect(XrHandJoint.littleTip.index, 25);
      expect(XrHand.byName('none'), XrHand.none);
    });

    test('a session recorded on a tape replays its poses bit for bit', () {
      const steps = 30;
      final live = EngineLoop(input: InputState());
      XrPoses.install(live);
      final recorder = InputTapeRecorder(seed: 7);
      live.recorders.add(recorder);
      var fed = 0;
      live.onStepInput((input) {
        // A controller that is seen on every third step only.
        input.feedExternal(_headAt(fed).toInput(XrPoseSources.head));
        if (fed % 3 == 0) {
          input.feedExternal(
            RigidPose.identity().toInput(XrPoseSources.grip(XrHand.right)),
          );
        }
        fed++;
      });
      final seen = _heads(live, steps);
      expect(seen.first, _headAt(0));
      expect(seen.last, _headAt(steps - 1));

      // Through the tape's own document, as a server would get it.
      final tape = InputTape.fromJson(
        jsonDecode(jsonEncode(recorder.tape.toJson())) as Map<String, Object?>,
      );
      final replay = EngineLoop(input: InputState())
        ..playback = InputTapePlayback(tape);
      XrPoses.install(replay);
      // Mutation: skip the inputs in `XrPoses.assimilate` and every head is
      // null; write the pose as floats and the equality below fails.
      expect(_heads(replay, steps), seen);
      final poses = replay.world.resource<XrPoses>()!;
      expect(poses[XrPoseSources.grip(XrHand.right)], RigidPose.identity());
      expect(poses.sources, contains(XrPoseSources.head));
    });
  });

  group('controls', () {
    const lift = AxisAction('lift');
    XrActionSource source(InputState input) => XrActionSource(
      input: input,
      bindings: <String, InputAction<Object>>{
        XrActionSource.sourceId(XrHand.right, XrControl.trigger):
            GameAction.use,
        XrActionSource.sourceId(XrHand.left, XrControl.thumbstick):
            DualAxisAction.move,
        XrActionSource.sourceId(XrHand.right, XrControl.thumbstick): lift,
      },
    );

    test('a trigger presses its action on the edge and gives its travel', () {
      final input = InputState();
      final xr = source(input);
      final trigger = XrActionSource.sourceId(XrHand.right, XrControl.trigger);
      expect(trigger, 'xr:right/trigger');
      xr.apply(<String, XrControlReading>{
        trigger: const XrControlReading(pressed: true, value: 0.8),
      });
      // Mutation: press on every frame it is held and `pressed` stays true
      // after the step; drop the travel and `value` reads one.
      expect(input.pressed(GameAction.use), isTrue);
      expect(input.value(GameAction.use), closeTo(0.8, 1e-12));
      input.endStep();
      xr.apply(<String, XrControlReading>{
        trigger: const XrControlReading(pressed: true, value: 0.9),
      });
      expect(input.pressed(GameAction.use), isFalse, reason: 'held, not new');
      xr.apply(<String, XrControlReading>{trigger: const XrControlReading()});
      expect(input.released(GameAction.use), isTrue);
      expect(input.held(GameAction.use), isFalse);
    });

    test('a stick drives a pair and an axis, and letting go clears them', () {
      final input = InputState();
      final xr = source(input)
        ..apply(<String, XrControlReading>{
          XrActionSource.sourceId(XrHand.left, XrControl.thumbstick):
              const XrControlReading(x: 0.25, y: -0.5),
          XrActionSource.sourceId(XrHand.right, XrControl.thumbstick):
              const XrControlReading(x: -0.75),
          'xr:left/menu': const XrControlReading(pressed: true),
        });
      expect(input.moveAxis.x, closeTo(0.25, 1e-12));
      expect(input.moveAxis.y, closeTo(-0.5, 1e-12));
      expect(input.axis(lift), -0.75);
      xr.letGo();
      expect(input.axis(lift), 0.0);
      expect(input.moveAxis.length, 0.0);
    });
  });

  group('the room', () {
    final table = XrPlane(
      id: 'table-1',
      pose: RigidPose(
        position: Vector3(0.5, 0.75, -1.0),
        orientation: Quaternion.identity(),
      ),
      width: 1.2,
      depth: 0.8,
      orientation: XrPlaneOrientation.horizontalUp,
    );

    test('a plane is input and back, and a collider under its top', () {
      final back = XrPlane.fromInput(
        ExternalStateInput.fromJson(
          jsonDecode(jsonEncode(table.toInput(displayTime: 2.0).toJson())),
        ),
      );
      expect(back.id, 'table-1');
      expect(back.pose, table.pose);
      expect(back.orientation, XrPlaneOrientation.horizontalUp);
      final bounds = table.toCollider().bounds;
      expect(bounds.max.y, closeTo(0.75, 1e-6), reason: 'the top is the top');
      expect(bounds.min.y, closeTo(0.73, 1e-6));
      expect(bounds.min.x, closeTo(-0.1, 1e-6));
      expect(bounds.max.z, closeTo(-0.6, 1e-6));
      // A wall turned a quarter about y is bounded by its turned corners.
      final wall = XrPlane(
        id: 'wall',
        pose: RigidPose(
          position: Vector3.zero(),
          orientation: Quaternion(0.0, math.sqrt1_2, 0.0, math.sqrt1_2),
        ),
        width: 2.0,
        depth: 0.0,
      ).toCollider().bounds;
      // Mutation: lay the plane out unturned and x spans two meters.
      expect(wall.max.x - wall.min.x, lessThan(0.05));
      expect(wall.max.z - wall.min.z, closeTo(2.0, 1e-6));
    });

    test('a scene mesh is input and back, and collides as its box', () {
      final mesh = XrSceneMesh(
        id: 'sofa',
        pose: RigidPose.identity(),
        vertices: Float32List.fromList(<double>[0, 0, 0, 2, 0, 0, 0, 0.5, 1]),
        indices: Uint32List.fromList(<int>[0, 1, 2]),
      );
      final back = XrSceneMesh.fromInput(mesh.toInput());
      expect(back.vertices, mesh.vertices);
      expect(back.indices, mesh.indices);
      final bounds = back.toCollider().bounds;
      expect(bounds.max.x, closeTo(2.0, 1e-6));
      expect(bounds.max.y, closeTo(0.5, 1e-6));
    });

    test('a recorded session puts the same colliders in the same steps', () {
      List<int> colliders(EngineLoop loop, CollisionWorld world) => <int>[
        for (var i = 0; i < 4; i++) (loop..runSteps(1)).collidersIn(world),
      ];
      final world = CollisionWorld();
      final live = EngineLoop(input: InputState())
        ..addAssimilation(XrSceneColliders.systemName, XrSceneColliders(world));
      final recorder = InputTapeRecorder(seed: 3);
      live.recorders.add(recorder);
      var step = 0;
      live.onStepInput((input) {
        switch (step++) {
          case 0:
            input.feedExternal(table.toInput());
          case 1:
            input.feedExternal(
              XrPlane(
                id: 'floor',
                pose: RigidPose.identity(),
                width: 4,
                depth: 4,
              ).toInput(),
            );
          case 2:
            input.feedExternal(XrPlane.lost('table-1'));
        }
      });
      // Mutation: skip `XrPlane.lost` and the table is never taken away.
      final counts = colliders(live, world);
      expect(counts, <int>[1, 2, 1, 1]);

      final replayWorld = CollisionWorld();
      final replay = EngineLoop(input: InputState())
        ..playback = InputTapePlayback(
          InputTape.fromJson(
            jsonDecode(jsonEncode(recorder.tape.toJson()))
                as Map<String, Object?>,
          ),
        )
        ..addAssimilation(
          XrSceneColliders.systemName,
          XrSceneColliders(replayWorld),
        );
      expect(colliders(replay, replayWorld), counts);
    });
  });
}

extension on EngineLoop {
  /// How many static colliders [world] holds after this step.
  int collidersIn(CollisionWorld world) => world.statics.length;
}
