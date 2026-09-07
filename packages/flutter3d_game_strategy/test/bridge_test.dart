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
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
    final visuals = StrategyVisuals(simulation: sim, device: device);
    final scene = Scene(name: 'map');
    visuals.addTo(scene);

    expect(scene.meshes.where((MeshNode m) => m.name == 'ground'), isNotEmpty);
  });

  test('the crowd is one batch, however many are in it', () {
    // The reason a strategy is the genre that exercises instancing: a thousand
    // nodes is a thousand draws. Mutation: add a node per unit instead — the
    // scene then holds a thousand children and this fails on the first.
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
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
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
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

  test('a unit that has been shot is drawn darker than a whole one', () {
    // **Damage costs no new drawing machinery at all**, which is why it is here
    // rather than in a follow-up: the batch has carried four floats of colour
    // per copy since it was written, and every unit has been writing white into
    // them without meaning to. So a wounded one is one different write into a
    // buffer that is uploaded whole anyway — no second batch, no material per
    // unit, no blending this package was not already doing, and no picture that
    // was right before is changed, because a crowd nobody has hit is still
    // white.
    //
    // Mutation: drop the `setColor` call from `sync`. A crowd at the point of
    // collapse is drawn exactly like a fresh one, which is the one thing about
    // a fight that a player has to be able to read at a glance.
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
    final whole = sim.add(Unit(position: Vector3(6.0, 0.0, 6.0)));
    final hurt = sim.add(Unit(position: Vector3(10.0, 0.0, 6.0)))
      ..hurt(UnitType.worker.health * 0.75);

    final visuals = StrategyVisuals(simulation: sim, device: device);
    visuals
      ..addTo(Scene(name: 'map'))
      ..sync();

    // The tint sits in the four floats after the three rows of the transform.
    List<double> tintOf(int index) => <double>[
      for (var i = 0; i < 4; i++)
        visuals.crowd.instanceData[index * InstancedMeshNode.floatsPerInstance +
            12 +
            i],
    ];

    expect(whole.health, UnitType.worker.health);
    expect(tintOf(0), <double>[1.0, 1.0, 1.0, 1.0], reason: 'an unhurt unit');

    final List<double> wounded = tintOf(1);
    expect(hurt.health, lessThan(UnitType.worker.health));
    expect(wounded[1], lessThan(0.5), reason: 'it is not visibly hurt');
    expect(
      wounded[0],
      greaterThan(wounded[1]),
      reason: 'it dimmed rather than reddened, which reads as shadow',
    );
    expect(wounded[3], 1.0, reason: 'damage turned a unit see-through');
  });

  test('draws no more than the batch can hold', () {
    // Mutation: pass `simulation.units.length` to `count` unclamped. The batch
    // then reports more instances than its buffer has, and the draw reads past
    // the end of it.
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
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
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
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

  test('each building keeps a material of its own', () {
    // What lets a game light the one the cursor is over. Mutation: hand every
    // node the same material — lighting a hall then lights every hall on the
    // map, which is the sort of thing that looks like a renderer bug and is
    // not.
    final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
    final visuals = StrategyVisuals(simulation: sim, device: device);
    visuals.addTo(Scene(name: 'map'));
    sim
      ..build(Building(centre: Vector3(8.0, 0.0, 8.0), width: 4.0, depth: 4.0))
      ..build(
        Building(centre: Vector3(30.0, 0.0, 30.0), width: 4.0, depth: 4.0),
      );
    visuals.sync();

    final materials = visuals.buildings.map((MeshNode m) => m.material);
    expect(materials.length, 2);
    expect(identical(materials.first, materials.last), isFalse);
  });

  group('under fog', () {
    test('a spectator is given no fog at all', () {
      // Mutation: build the tile batches whatever `viewer` says. A test
      // harness, a replay or an editor then looks at a map through somebody
      // else's ignorance, which is the one view that has to be honest.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      final visuals = StrategyVisuals(simulation: sim, device: device);

      expect(visuals.unseen, isNull);
      expect(visuals.remembered, isNull);
    });

    test('a side is not drawn a crowd it cannot see', () {
      // **The saving the phase was partly for.** Mutation: write every unit
      // into the batch regardless. Nothing looks wrong in a small test — the
      // enemy is simply visible through the dark — and the instance bill,
      // which is what this genre's ceiling is made of, is paid in full for a
      // crowd nobody is allowed to look at.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      sim
        ..add(Unit(position: Vector3(6.0, 0.0, 6.0)))
        ..add(Unit(position: Vector3(34.0, 0.0, 34.0), side: 1));
      sim.step(1.0 / 60.0);

      final visuals = StrategyVisuals(
        simulation: sim,
        device: device,
        viewer: 0,
      );
      visuals
        ..addTo(Scene(name: 'map'))
        ..sync();

      expect(visuals.crowd.count, 1, reason: 'it was shown the other side');
    });

    test('covers what nobody went to and thins behind a crowd that did', () {
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      final scout = sim.add(
        Unit(
          position: Vector3(6.0, 0.0, 6.0),
          type: UnitType.worker.copyWith(sight: 8.0),
        ),
      );
      final visuals = StrategyVisuals(
        simulation: sim,
        device: device,
        viewer: 0,
      );
      visuals
        ..addTo(Scene(name: 'map'))
        ..sync();

      final int dark = visuals.unseen!.count;
      expect(dark, greaterThan(0), reason: 'the map opened uncovered');
      expect(visuals.remembered!.count, 0, reason: 'nothing to remember yet');

      scout.order = UnitOrder.moveTo(Vector3(34.0, 0.0, 34.0));
      for (var i = 0; i < 60 * 20; i++) {
        sim.step(1.0 / 60.0);
      }
      visuals.sync();

      expect(
        visuals.unseen!.count,
        lessThan(dark),
        reason: 'walking across the map uncovered none of it',
      );
      expect(
        visuals.remembered!.count,
        greaterThan(0),
        reason: 'the ground it walked over is not remembered',
      );
    });

    test('holds back a building the viewer has never found', () {
      // Mutation: make a node for every building the moment it is placed. The
      // other side's hall then appears out of the dark the instant it is built,
      // which is the fog telling you exactly what it was there to hide.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      final visuals = StrategyVisuals(
        simulation: sim,
        device: device,
        viewer: 0,
      );
      final scene = Scene(name: 'map');
      visuals
        ..addTo(scene)
        ..sync();
      final int before = scene.meshes.length;

      sim.build(
        Building(
          centre: Vector3(34.0, 0.0, 34.0),
          width: 6.0,
          depth: 6.0,
          name: 'their hall',
          side: 1,
        ),
      );
      visuals.sync();

      expect(scene.meshes.length, before, reason: 'it was drawn unseen');
      expect(
        scene.meshes.map((MeshNode m) => m.name),
        isNot(contains('their hall')),
      );
    });
  });
}
