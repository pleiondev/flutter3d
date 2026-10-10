/// What is drawn of the water and the wood is the run's, not a world of its
/// own.
///
///     flutter test test/elements_drawn_test.dart
///
/// The run steps the level's elements (`run_elements.dart`); `elements.dart`
/// draws them from a copy of that world, taken whole by snapshot each frame
/// the run has stepped. What could go wrong is the copy: a drawing that
/// stepped its own world, or kept the one it was dressed with, would show a
/// plank somewhere the run has none. So this dresses the Cisterns the way
/// `main.dart` does — the shipped level, `stage`, `Elements.adopt` — steps
/// the run, and asks where the planks are drawn.
///
/// The water's material has no stage the software rasteriser can run, so it
/// is drawn unlit here, as `flutter3d_effects`' own tests draw it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_platformer/src/elements.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a plank is drawn where the run has it, a second of current on',
    () async {
      // Mutation: leave the copy out of `LevelElements.update`, and every
      // plank is drawn where it was put in while the run's has drifted.
      await startPhysics(asked: 'native');
      final device = CpuDevice(
        width: 32,
        height: 32,
        shaders: CpuShaderLibrary(<String, CpuStage>{
          ...builtinCpuShaders(),
          'Liquid': cpuUnlitStage,
        }),
      );
      final renderer = Renderer.create(device: device);
      final (:kinds, :loaded, :fixtures) = await openLevel(
        'assets/levels/cisterns.json',
        device: device,
      );
      final input = InputState();
      final staged = stage(
        loaded.level,
        loaded.collision,
        input: input,
        registry: kinds,
        onFixture: fixtures.add,
      );
      final bundle = ByteData.sublistView(
        File(
          '../../packages/flutter3d_effects/assets/liquid.f3dshaders',
        ).readAsBytesSync(),
      );
      final drawn = LevelElements(
        elements: await Elements.adopt(
          NativeWorld(),
          device: device,
          renderer: renderer,
          scene: Scene(),
          load: (_) async => bundle,
        ),
        device: device,
        liquidBundle: bundle,
      );
      addTearDown(() {
        drawn.dispose();
        staged.elements?.dispose();
      });
      drawn.stage(
        LevelReady(loaded: loaded, staged: staged, fixtures: fixtures),
      );
      final run = staged.elements!;
      expect(
        loaded.scene.meshes.where((m) => m.name == 'water'),
        hasLength(run.pools.length),
      );

      final planks = <MeshNode>[
        for (final m in loaded.scene.meshes)
          if (m.name == 'plank') m,
      ];
      final put = <Vector3>[for (final p in planks) p.readPosition()];
      for (var i = 0; i < 60; i++) {
        input.beginStep();
        staged.step(1.0 / 60.0);
        input.endStep();
        drawn.update(1.0 / 60.0, eye: Vector3(0.0, 3.0, -10.0));
      }

      final inRun = <Vector3>[
        for (final a in run.afloat)
          if (!a.raft) run.world.localPositionOf(a.body),
      ];
      expect(planks, hasLength(inRun.length));
      for (final (k, plank) in planks.indexed) {
        final at = plank.readPosition();
        expect(at, isNot(put[k]), reason: 'plank $k has not moved at all');
        expect(
          inRun.any((p) => p.x == at.x && p.y == at.y && p.z == at.z),
          isTrue,
          reason: 'plank $k is drawn at $at, where the run has none',
        );
      }
    },
  );
}
