@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_showcase/pages/physics_particles/heightfield_collision.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/actors.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/audio_occlusion.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/baked_visibility.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/ecs_world.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/flow_field.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/headless_run.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/level_format.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/level_mechanisms.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/pendulum_lab.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/portable_math.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/positional_audio.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/replay_digest.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/rewind.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/terrain_tiles.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/voice_limit.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/page_harness.dart';

/// The node called [name] in [run]'s scene.
MeshNode _node(DemoRun run, String name) => run.scene.root.childrenView
    .whereType<MeshNode>()
    .firstWhere((MeshNode n) => n.name == name);

void _tick(DemoRun run, int frames) {
  for (var i = 0; i < frames; i++) {
    run.update(1 / 60);
  }
}

Future<void> _with(
  ShowcaseDemo demo,
  Future<void> Function(DemoRun run) body,
) async {
  final DemoRun run = await DemoRun.start(cpuDevice(), demo);
  try {
    await body(run);
  } finally {
    run.dispose();
  }
}

void _press(ShowcaseDemo demo, DemoRun run, int index) {
  (demo.controls(run.context)[index] as ToggleControl).onChanged(true);
}

void main() {
  group('simulation pages, live', () {
    test('a hit shrinks the goblin\'s health bar and a third kills it', () {
      // Mutation: apply the damage to a copy, or to the brain only, and the
      // bar never moves.
      final ActorsDemo demo = ActorsDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        final double full = _node(run, 'health').readScale().x;
        _press(demo, run, 0);
        _tick(run, 2);
        expect(_node(run, 'health').readScale().x, lessThan(full * 0.7));
        _press(demo, run, 0);
        _tick(run, 2);
        _press(demo, run, 0);
        _tick(run, 2);
        expect(_node(run, 'goblin').readScale().y, lessThan(0.5));
      });
    });

    test('the bell is louder close than far, and dull behind the wall', () {
      final PositionalAudioDemo positional = PositionalAudioDemo()
        ..orbiting = false
        ..distance = 1.0;
      final Future<void> loud = _with(positional, (DemoRun run) async {
        _tick(run, 2);
        final double near = _node(run, 'source').readScale().x;
        positional.distance = 10.0;
        _tick(run, 2);
        expect(_node(run, 'source').readScale().x, lessThan(near));
      });
      final AudioOcclusionDemo occlusion = AudioOcclusionDemo()
        ..walking = false
        ..listenerX = 0.0;
      return loud.then(
        (_) => _with(occlusion, (DemoRun run) async {
          _tick(run, 2);
          final double behind = _node(run, 'bell').material.baseColor.x;
          occlusion.listenerX = 5.0;
          _tick(run, 2);
          expect(
            _node(run, 'bell').material.baseColor.x,
            greaterThan(behind + 0.2),
          );
        }),
      );
    });

    test('the markers behind the wall go off as the eye crosses it', () {
      final BakedVisibilityDemo demo = BakedVisibilityDemo()
        ..walking = false
        ..eyeX = 0.5;
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        expect(_node(run, 'marker 0.0').visible, isTrue);
        expect(_node(run, 'marker 10.0').visible, isFalse);
        demo.eyeX = 9.0;
        _tick(run, 2);
        expect(_node(run, 'marker 0.0').visible, isFalse);
        expect(_node(run, 'marker 10.0').visible, isTrue);
      });
    });

    test('the door rises once the button is pressed', () {
      final LevelMechanismsDemo demo = LevelMechanismsDemo()
        ..automatic = false;
      return _with(demo, (DemoRun run) async {
        _tick(run, 30);
        expect(_node(run, 'door').readPosition().y, closeTo(1.0, 0.01));
        _press(demo, run, 0);
        _tick(run, 150);
        expect(_node(run, 'door').readPosition().y, greaterThan(2.0));
      });
    });

    test('the agents get round the walls to the goal', () {
      // Mutation: never rebuild the field, or read it from the wrong cell, and
      // they stop against the first wall.
      final FlowFieldDemo demo = FlowFieldDemo()..cycling = false;
      return _with(demo, (DemoRun run) async {
        var closest = double.infinity;
        for (var i = 0; i < 1500; i++) {
          run.update(1 / 60);
          for (var a = 0; a < 16; a++) {
            final position = _node(run, 'agent $a').readPosition();
            final double away =
                (position.x - 18.0).abs() + (position.z - 17.0).abs();
            if (away < closest) closest = away;
          }
        }
        expect(closest, lessThan(1.5));
      });
    });

    test('the walker patrols the hills with its feet on them', () {
      final HeightfieldCollisionDemo demo = HeightfieldCollisionDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 600);
        final position = _node(run, 'walker').readPosition();
        // Out of the start and up off the floor plane the hills stand on.
        expect(position.length, greaterThan(3.0));
        expect(position.y, inInclusiveRange(-1.0, 3.0));
      });
    });

    test('the tiles nearest the eye are fine and the far ones coarse', () {
      // Mutation: choose from the tile's own index and not its distance to the
      // eye, and the tile under the eye is as coarse as the far corner.
      final TerrainTilesDemo demo = TerrainTilesDemo()
        ..moving = false
        ..eyeAngle = 0.0;
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        // The eye is at (27, 16): tile (3, 2) is under it and tile (0, 0) far.
        expect(_node(run, 'tile 11').material.name, 'fine');
        expect(_node(run, 'tile 0').material.name, 'coarse');
        demo.eyeAngle = 3.14159;
        _tick(run, 2);
        expect(_node(run, 'tile 11').material.name, 'coarse');
      });
    });

    test('the shout and the nearest footsteps win the voices', () {
      // Mutation: hand voices out in the order they were asked for, and the
      // shout, played last, never gets one.
      final VoiceLimitDemo demo = VoiceLimitDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        bool lit(String name) =>
            _node(run, name).material.baseColor.x > 0.5;
        expect(lit('shout'), isTrue);
        final int steps = <int>[
          for (var i = 0; i < 8; i++)
            if (lit('step $i')) i,
        ].length;
        // Three voices: the shout and two footsteps.
        expect(steps, 2);
        expect(lit('step 0'), isTrue);
        expect(lit('step 7'), isFalse);
      });
    });

    test('the checkpoints agree until the length changes, then go red', () {
      // Mutation: compare the runs from the wrong end, or never change the
      // student's length, and no lamp ever goes red.
      final PendulumLabDemo demo = PendulumLabDemo()..changeAt = 100.0;
      return _with(demo, (DemoRun run) async {
        _tick(run, 366);
        bool red(String name) => _node(run, name).material.baseColor.x > 0.6;
        expect(red('lamp 0'), isFalse);
        expect(red('lamp 1'), isFalse);
        expect(red('lamp 3'), isTrue);
        expect(red('lamp 5'), isTrue);
      });
    });

    test('a rewind puts the runner back where it was a second ago', () {
      final RewindDemo demo = RewindDemo()..automatic = false;
      return _with(demo, (DemoRun run) async {
        _tick(run, 150);
        final double before = _node(run, 'runner').readPosition().x;
        _press(demo, run, 0);
        _tick(run, 1);
        expect(
          _node(run, 'runner').readPosition().x,
          lessThan(before - 1.5),
        );
      });
    });

    test('the replay lamps go red from the checkpoint that covers the drift', () {
      final ReplayDigestDemo demo = ReplayDigestDemo()..driftAt = 9.0;
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        bool red(String name) => _node(run, name).material.baseColor.x > 0.6;
        expect(red('lamp 0'), isFalse);
        expect(red('lamp 1'), isFalse);
        // Checkpoints fall on 4, 8, 12: the drift at 9 first shows at 12.
        expect(red('lamp 2'), isTrue);
        demo.driftAt = 21.0;
        (demo.controls(run.context).first as SliderControl).onChanged(21.0);
        _tick(run, 2);
        expect(red('lamp 4'), isFalse);
      });
    });

    test('a resumed generator rolls what the original rolls', () {
      final PortableMathDemo demo = PortableMathDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 300);
        expect(_node(run, 'lamp').material.baseColor.x, lessThan(0.6));
      });
    });

    test('the validator\'s lamps follow the edit', () {
      final LevelFormatDemo demo = LevelFormatDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        int lit() => <int>[
          for (var i = 0; i < 6; i++)
            if (_node(run, 'issue $i').visible) i,
        ].length;
        final int overlapping = lit();
        expect(overlapping, greaterThan(0));
        (demo.controls(run.context).first as SliderControl).onChanged(2.0);
        _tick(run, 2);
        expect(lit(), lessThan(overlapping));
      });
    });

    test('the blind run, watched, gets to the post', () {
      final HeadlessRunDemo demo = HeadlessRunDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 120);
        expect(_node(run, 'walker').readPosition().x, greaterThan(3.0));
        _tick(run, 200);
        expect(_node(run, 'goal').material.baseColor.y, greaterThan(0.6));
      });
    });

    test('the level reloads into the chosen layout', () {
      final EcsWorldDemo demo = EcsWorldDemo();
      return _with(demo, (DemoRun run) async {
        _tick(run, 2);
        expect(_node(run, 'slot 2').visible, isTrue);
        expect(_node(run, 'entity 1').visible, isFalse);
        demo.reload = 2;
        _tick(run, 2);
        expect(_node(run, 'slot 1').visible, isFalse);
        expect(_node(run, 'entity 0').visible, isTrue);
      });
    });
  });
}
