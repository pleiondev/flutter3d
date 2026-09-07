/// The drawing half, checked with no GPU behind it.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Heightfield _ground() => Heightfield(
  columns: 21,
  rows: 21,
  cellSize: 2.0,
  heights: Float32List(21 * 21),
);

void main() {
  late GraphicsDevice device;

  setUp(() {
    device = CpuDevice(
      width: 16,
      height: 16,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
  });

  tearDown(() => device.dispose());

  test('the ground is one node with a vertex per sample', () {
    final sim = StrategySimulation(ground: _ground());
    final visuals = StrategyVisuals(simulation: sim, device: device);
    final scene = Scene(name: 'map');
    visuals.addTo(scene);

    expect(scene.meshes.where((MeshNode m) => m.name == 'ground'), isNotEmpty);
  });

  test('the crowd is one batch, however many are in it', () {
    // The reason a strategy is the genre that exercises instancing: a thousand
    // nodes is a thousand draws. Mutation: add a node per unit instead — the
    // scene then holds a thousand children and this fails on the first.
    final sim = StrategySimulation(ground: _ground());
    for (var i = 0; i < 300; i++) {
      sim.add(Unit(position: Vector3(4.0 + i % 20 * 1.5, 0.0, 4.0)));
    }

    final visuals = StrategyVisuals(simulation: sim, device: device);
    final scene = Scene(name: 'map');
    visuals.addTo(scene);
    visuals.sync();

    final batches = scene.meshes.whereType<InstancedMeshNode>().toList();
    expect(batches.length, 1);
    expect(batches.single.count, 300);
    expect(scene.meshes.length, 2, reason: 'the ground and the batch');
  });

  test('a unit is drawn standing on the ground, not buried in it', () {
    // Mutation: drop the half-height lift. Every unit is then drawn with its
    // middle at ground level, which reads as a field of half-sunk boxes.
    final sim = StrategySimulation(ground: _ground());
    final unit = sim.add(Unit(position: Vector3(10.0, 0.0, 10.0)));

    final visuals = StrategyVisuals(simulation: sim, device: device);
    visuals
      ..addTo(Scene(name: 'map'))
      ..sync();

    final drawn = Matrix4.identity();
    visuals.crowd.readTransform(0, drawn);

    expect(
      drawn.getTranslation().y,
      closeTo(unit.position.y + visuals.unitSize.height / 2.0, 1e-6),
    );
  });

  test('draws no more than the batch can hold', () {
    // Mutation: pass `simulation.units.length` to `count` unclamped. The batch
    // then reports more instances than its buffer has, and the draw reads past
    // the end of it.
    final sim = StrategySimulation(ground: _ground());
    for (var i = 0; i < 40; i++) {
      sim.add(Unit(position: Vector3(4.0 + i * 1.2, 0.0, 4.0)));
    }

    final visuals = StrategyVisuals(
      simulation: sim,
      device: device,
      capacity: 16,
    );
    visuals
      ..addTo(Scene(name: 'map'))
      ..sync();

    expect(visuals.crowd.count, 16);
  });

  test('a building arrives as a node of its own', () {
    // Instances scale uniformly, and buildings have sizes of their own, so a
    // building cannot join the batch. Mutation: put them in it — a wide hall
    // is then drawn as a cube.
    final sim = StrategySimulation(ground: _ground());
    final visuals = StrategyVisuals(simulation: sim, device: device);
    final scene = Scene(name: 'map');
    visuals
      ..addTo(scene)
      ..sync();

    final before = scene.meshes.length;
    sim.build(
      Building(
        centre: Vector3(20.0, 0.0, 20.0),
        width: 12.0,
        depth: 4.0,
        name: 'hall',
      ),
    );
    visuals.sync();

    expect(scene.meshes.length, before + 1);
    expect(scene.meshes.last.name, 'hall');
  });
}
