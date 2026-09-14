/// `tpl-04`'s three non-game templates — each is a real level document,
/// opened the same headless way `level_cubit_test.dart` already opens
/// `first.json`: `Level.fromJson`, `LevelLoader().build` with the seed's own
/// open registry, `CpuDevice` in place of a window.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetBuilder;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_template_app/main.dart';
import 'package:flutter3d_template_app/src/template_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Level _readLevel(String path) => Level.fromJson(
  jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
);

Future<LoadedLevel> _build(Level level, GraphicsDevice device) =>
    LevelLoader().build(
      level,
      device: device,
      registry: EntityRegistry(<EntityKind>[
        for (final type in level.entities.map((EntityDef e) => e.type).toSet())
          OpenKind(type),
      ]),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('viewer.json', () {
    final level = _readLevel('assets/levels/viewer.json');

    test('opens through the seed\'s own open registry', () async {
      final loaded = await _build(level, _device());
      expect(loaded.issues, isEmpty);
    });

    test('names a three-step tour, in order', () {
      expect(stepCaptions(level), <String>[
        'Вид спереди',
        'Вид сбоку',
        'Вид сверху',
      ]);
    });

    test('carries one widget_surface, naming a widget an empty registry '
        'reports as missing rather than silently drops', () async {
      final device = _device();
      final loaded = await _build(level, device);
      final issues = <String>[];
      final visuals = WidgetSurfaceVisuals(
        loaded.scene,
        device: device,
        registry: const <String, WidgetBuilder>{},
        onIssue: (issue) => issues.add(issue.message),
      );
      for (final entity in level.entities) {
        visuals.add(entity);
      }
      const expected =
          'widget_surface "view-caption" names "viewer-caption", which this '
          "application's widget registry does not have";
      expect(issues, <String>[expected]);
      visuals.dispose();
    });

    test('has no bound step: nothing in it is a live twin', () {
      expect(stepWithBindings(level), isNull);
    });
  });

  group('configurator.json', () {
    final level = _readLevel('assets/levels/configurator.json');

    test('opens through the seed\'s own open registry', () async {
      final loaded = await _build(level, _device());
      expect(loaded.issues, isEmpty);
    });

    test('names exactly one widget_surface: the configurator panel', () {
      final surfaces = level.entities.where((e) => e.type == 'widget_surface');
      expect(surfaces, hasLength(1));
      expect(surfaces.first.string('widget'), 'configurator-panel');
    });

    test(
      'has no steps and no bound step: it is neither a viewer nor a twin',
      () {
        expect(stepCaptions(level), isEmpty);
        expect(stepWithBindings(level), isNull);
      },
    );

    test("ls-i-01's own geometry half: one part per ConfiguratorController "
        'option, not one unnamed brush', () {
      final parts = level.entities
          .where((e) => e.type == 'part')
          .map((e) => e.name)
          .toSet();
      for (final (name, _) in ConfiguratorController.options) {
        expect(
          parts,
          contains('product-${name.toLowerCase()}'),
          reason:
              '$name is a ConfiguratorController option with no matching '
              'part in the level, so the panel would cycle to it and show '
              'nothing',
        );
      }
      expect(
        parts.length,
        ConfiguratorController.options.length,
        reason:
            'a part with no matching option would just sit there, '
            'always hidden',
      );
    });

    test(
      'the three product parts load as real, distinctly coloured nodes',
      () async {
        // Through `LevelCubit.open`, not `_build`: `_addParts` — the code
        // that actually turns a `part` entity into a named `MeshNode` — runs
        // there, not inside `LevelLoader.build` itself.
        final cubit = LevelCubit();
        await cubit.open(
          _device(),
          world: CollisionWorld(),
          camera: CameraNode(),
          asset: 'assets/levels/configurator.json',
        );
        final ready = cubit.state as LevelReady;
        final byName = <String, MeshNode>{
          for (final mesh in ready.scene.meshes)
            if (mesh.name != null) mesh.name!: mesh,
        };

        expect(
          byName.keys,
          containsAll(<String>['product-red', 'product-blue', 'product-green']),
        );

        final colors = byName.entries
            .where((e) => e.key.startsWith('product-'))
            .map((e) {
              final c = e.value.material.baseColor;
              return (c.x, c.y, c.z);
            })
            .toSet();
        expect(
          colors,
          hasLength(3),
          reason:
              'three variants that all resolved to the same colour would '
              'be indistinguishable once shown',
        );
      },
    );
  });

  group('twin.json', () {
    final level = _readLevel('assets/levels/twin.json');

    test('opens through the seed\'s own open registry', () async {
      final loaded = await _build(level, _device());
      expect(loaded.issues, isEmpty);
    });

    test('names a data source and a step bound to it', () {
      final step = stepWithBindings(level);
      expect(step, isNotNull);
      expect(step!.name, 'reading');

      final bindings = step.properties['bindings']! as List;
      expect(bindings, hasLength(1));
      final binding = (bindings.first as Map).cast<String, Object?>();
      expect(binding['source'], 'spindle-temp');
      expect(binding['target'], 'dashboard.temperature');
    });

    test('resolveBindings reads a real, changing value off the sampler', () {
      final step = stepWithBindings(level)!;
      final sources = DataSourceRegistry(<String, EduDataSource>{
        'spindle-temp': SamplerDataSource(
          (s) => <String, Object?>{'value': 60.0 + s.toDouble()},
        ),
      });

      final at10 = resolveBindings(step, 10, sources);
      final at20 = resolveBindings(step, 20, sources);
      expect(at10['dashboard.temperature'], 70.0);
      expect(at20['dashboard.temperature'], 80.0);
      expect(at10, isNot(equals(at20)));
    });
  });
}
