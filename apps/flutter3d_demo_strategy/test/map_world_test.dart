/// The map's world as part of the match: water that slows whoever wades it,
/// fire that hurts whoever stands near it, each by its law.
///
///     flutter test test/map_world_test.dart
///
/// The laws first, each held to its closed form with the numbers its
/// sources give; then the two doors into the match, on the shipped map and
/// its own world, with no device: a squad sent over the ford covers less
/// ground than the same squad sent over a map with no water, and a unit
/// beside a fire loses health while one thirty metres off loses none.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/map_world.dart';
import 'package:flutter3d_demo_strategy/src/run.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Snapshot;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

StrategyMap _map() =>
    StrategyMap.parse(File('assets/levels/map_a.json').readAsStringSync());

/// The pace that balances c·m·(v₀ − v) = ½ρ·C_d·A·v³/η in still water,
/// found by Newton's method rather than the bisection the game uses: the
/// same law solved a second way.
double _balanced(double area, double dry) {
  const double budget = costOfTransport * 70.0;
  final double k =
      0.5 * NativeLiquidProperties.water.density * 1.2 * area / 0.25;
  var v = dry;
  for (var i = 0; i < 60; i++) {
    final double f = budget * (dry - v) - k * v * v * v;
    final double slope = -budget - 3.0 * k * v * v;
    v -= f / slope;
  }
  return v;
}

void main() {
  group('wading', () {
    test('a person wading water a foot deep goes at the pace the power '
        'balance gives', () {
      // Two legs 0.12 m across, wet 0.3 m up. Mutation: the muscles'
      // efficiency taken as 0.3, or the leg's drag coefficient as 1.0,
      // moves the pace off this root.
      expect(
        wadingPace(depth: 0.3, dry: 3.0),
        closeTo(_balanced(2.0 * 0.12 * 0.3, 3.0), 1e-6),
      );
    });

    test('past the crotch the hips are pushed back too', () {
      // 0.8 m of two legs and 0.2 m of hips 0.36 m across. Mutation: the
      // hips left out leaves the area at the legs' and the pace faster.
      expect(
        wadingPace(depth: 1.0, dry: 3.0),
        closeTo(_balanced(2.0 * 0.12 * 0.8 + 0.36 * 0.2, 3.0), 1e-6),
      );
    });

    test('the deeper the water, the slower, and never as fast as dry', () {
      // Mutation: the wetted area not growing with the depth makes all
      // three paces one.
      final double ankle = wadingPace(depth: 0.1, dry: 3.0);
      final double knee = wadingPace(depth: 0.45, dry: 3.0);
      final double waist = wadingPace(depth: 1.0, dry: 3.0);
      expect(ankle, lessThan(3.0));
      expect(knee, lessThan(ankle));
      expect(waist, lessThan(knee));
    });

    test('a current along the way helps and one against it hinders', () {
      // Mutation: the current dropped from the relative speed makes all
      // three the same.
      final double still = wadingPace(depth: 0.3, dry: 3.0);
      expect(
        wadingPace(depth: 0.3, dry: 3.0, current: 1.0),
        greaterThan(still),
      );
      expect(wadingPace(depth: 0.3, dry: 3.0, current: -1.0), lessThan(still));
      // A current faster than the walk carries nobody past their dry pace.
      // Mutation: the early return on a surplus at the dry pace taken out
      // leaves the bisection at its upper bound less half a step's width.
      expect(wadingPace(depth: 0.3, dry: 3.0, current: 4.0), 3.0);
    });
  });

  group('gravity, the world\'s', () {
    test('a stone lobbed in a world on the Moon comes down on its mark', () {
      final world = NativeWorld()
        ..gravity = Vector3(0.0, -1.62, 0.0)
        // No air, so the arc is the gravity's alone.
        ..setAir(temperature: standardAirTemperature, density: 1e-30);
      final Vector3 from = Vector3(0.0, 1.5, 0.0), to = Vector3(6.0, 0.3, 2.0);
      final NativeBody stone = world.addBody(position: from, mass: 120.0);
      world
        ..setShape(stone, const NativeShape.sphere(0.22))
        ..setVelocity(
          stone,
          lobVelocity(from, to, flight: 0.8, g: world.gravityMagnitude),
        );
      for (var i = 0; i < 48; i++) {
        world.step(0.8 / 48);
      }
      // Mutation: the lob's gravity written back as 9.81 — on the Moon the
      // stone is thrown 3.3 m/s too steeply and is still 2.6 m over its
      // mark when it should be on it.
      expect((world.localPositionOf(stone) - to).length, lessThan(0.05));
      world.dispose();
    });

    test('the pond\'s weir is set by its world\'s gravity, and the '
        'Earth\'s to the bit', () {
      final earth = NativeWorld();
      final moon = NativeWorld()..gravity = Vector3(0.0, -1.62, 0.0);
      // The same river over the same sill backs up a higher head where the
      // water pours slower: H ∝ g^(−1/3). Mutation: the head worked out
      // from 9.81 whatever the world — the two heads are equal.
      expect(
        weirHead(flow: 2.0, width: 8.0, g: moon.gravityMagnitude) /
            weirHead(flow: 2.0, width: 8.0, g: earth.gravityMagnitude),
        closeTo(math.pow(9.81 / 1.62, 1.0 / 3.0), 1e-6),
      );
      // On the Earth the head is the number the pond was always set by, to
      // the last bit, so the match's tapes do not move. Mutation:
      // `gravityMagnitude` reading the core's f32 9.8100004 — the head
      // moves in its eighth figure and this fails.
      expect(
        weirHead(flow: 2.0, width: 8.0, g: earth.gravityMagnitude),
        Portable.pow(
          2.0 / (2.0 / 3.0 * 0.611 * math.sqrt(2.0 * 9.81) * 8.0),
          2.0 / 3.0,
        ),
      );
      earth.dispose();
      moon.dispose();
    });
  });

  group('heat', () {
    test('a flame radiates its share as a point source from its middle', () {
      // 300 kW radiated, 5 m off: 3e5 / (4π·25). Mutation: 2π for 4π, or
      // the distance not squared.
      expect(
        radiantFlux(radiated: 3e5, soot: 1200.0, distance: 5.0),
        closeTo(3e5 / (4.0 * math.pi * 25.0), 1e-6),
      );
    });

    test('close in, no more than the soot glowing as a black body', () {
      // σ·1200⁴ = 117 579 W/m². Mutation: the cap taken out lets the point
      // source run to 2.4e8 a centimetre off.
      expect(
        radiantFlux(radiated: 3e5, soot: 1200.0, distance: 0.01),
        closeTo(stefanBoltzmann * math.pow(1200.0, 4), 1e-6),
      );
    });

    test('below 2.5 kW/m² a person bears it, above it is burnt by '
        'ISO 13571\'s dose', () {
      // Mutation: the threshold dropped makes 2 kW/m² harm.
      expect(harmRate(2000.0), 0.0);
      // 10 kW/m²: burnt in 6.9·10^−1.56 minutes, 11.4 s. Mutation: the
      // pain law, 4·q^−1.35, in its place.
      expect(
        harmRate(10000.0),
        closeTo(1.0 / (6.9 * 60.0 * math.pow(10.0, -1.56)), 1e-12),
      );
    });
  });

  group('on the shipped map', () {
    test('a squad sent over the ford is held back by the water', () {
      // The same squad, sent the same way, on the map with its world and on
      // the bare map: with the water, it has covered less ground.
      final wetStart = openMatch(_map());
      final MapWorld river = mapWorldOf(wetStart.simulation);
      final Vector3 ford = river.fords.first;
      ({double covered, double wettest}) cross(
        StrategyStart start,
        MapWorld? world,
      ) {
        final List<Building> halls = start.simulation.buildings;
        final Vector3 way = halls[1].center - halls[0].center
          ..y = 0.0
          ..normalize();
        final Vector3 from = ford - way * 8.0;
        final List<StrategyUnit> squad = start.mine.take(8).toList();
        for (final (int i, StrategyUnit unit) in squad.indexed) {
          final double x = from.x + (i % 4) * 0.8, z = from.z + (i ~/ 4) * 0.8;
          unit.position.setValues(x, start.simulation.ground.heightAt(x, z), z);
        }
        final command = CommandPost(
          simulation: start.simulation,
          side: viewerSide,
        );
        expect(
          command.selectWithin(
            from - Vector3(0.5, 0.0, 0.5),
            from + Vector3(3.0, 0.0, 1.5),
          ),
          squad.length,
        );
        command.orderTo(ford + way * 8.0);
        var wettest = 0.0;
        for (var i = 0; i < 200; i++) {
          start.match.step(strategyStep);
          if (world == null) continue;
          for (final StrategyUnit unit in squad) {
            final NativeShallowSample? s = world.world.sampleShallow(
              world.river,
              unit.position.x,
              unit.position.z,
            );
            if (s != null) wettest = math.max(wettest, s.depth);
          }
        }
        final double covered =
            squad
                .map((StrategyUnit unit) => (unit.position - from).dot(way))
                .reduce((a, b) => a + b) /
            squad.length;
        world?.dispose();
        return (covered: covered, wettest: wettest);
      }

      final dry = cross(openMatch(_map()), null);
      final wet = cross(wetStart, river);
      // The squad stood in the river on the way over, or the test proves
      // nothing about the river.
      expect(wet.wettest, greaterThan(0.05));
      // Mutation: the world's pace not hung on the simulation
      // (`simulation.pace` left null) leaves the two squads level.
      expect(wet.covered, lessThan(dry.covered - 0.5));
    });

    test('a unit beside a fire is hurt by its heat, and one thirty metres '
        'off is not', () {
      final start = openMatch(_map());
      final world = mapWorldOf(start.simulation);
      final ground = start.simulation.ground;
      StrategyUnit stand(StrategyUnit unit, double x, double z) {
        unit
          ..job = null
          ..order = const UnitOrder.hold();
        unit.position.setValues(x, ground.heightAt(x, z), z);
        return unit;
      }

      final StrategyUnit near = stand(start.mine[0], 31.0, 60.0);
      final StrategyUnit far = stand(start.mine[1], 60.0, 75.0);
      // A heap of dry brush burning a tenth of a kilogram a second a metre
      // from the near one: a megawatt and a third, its flame standing
      // metres over the heap, so the near one stands at its foot.
      final NativeBody heap = world.world.addBody(
        position: Vector3(32.0, ground.heightAt(32.0, 60.0) + 0.5, 60.0),
        type: NativeBodyType.fixed,
        mass: 50.0,
      );
      world.world
        ..setShape(heap, NativeShape.box(Vector3.all(0.5)))
        ..setMaterial(heap, MapWorld.dry)
        ..setBurner(
          heap,
          NativeBurner(fuel: NativeMaterial.paper(), rate: 0.1),
        );
      for (var i = 0; i < 120; i++) {
        start.match.step(strategyStep);
      }
      world.dispose();
      // Mutation: the fires' heat not taken off anybody (`_scorch` not
      // called) leaves the near one whole.
      expect(near.health, lessThan(near.type.health));
      // Mutation: the threshold dropped from `harmRate` hurts the far one
      // by the little that reaches it.
      expect(far.health, far.type.health);
    });

    test('a match saved with a fire burning resumes with it burning, to the '
        'bit', () {
      // A heap of dry brush by the near camp, hot through, as one thrown out
      // of a fire would be, and the match played on while it burns.
      final live = openMatch(_map());
      final MapWorld world = mapWorldOf(live.simulation);
      final ground = live.simulation.ground;
      final NativeBody heap = world.world.addBody(
        position: Vector3(32.0, ground.heightAt(32.0, 60.0) + 0.5, 60.0),
        mass: 20.0,
      );
      world.world
        ..setShape(heap, NativeShape.box(Vector3.all(0.5)))
        ..setMaterial(heap, MapWorld.dry)
        ..setTemperature(heap, 900.0);
      for (var i = 0; i < 120; i++) {
        live.match.step(strategyStep);
      }
      expect(world.world.fires(), isNotEmpty, reason: 'nothing caught');
      final Snapshot saved = live.match.save();

      // Resumed as the run resumes a match: the map staged, its world stood
      // over it, and then the save put back.
      final resumed = openMatch(_map());
      final MapWorld again = mapWorldOf(resumed.simulation);
      resumed.match.restore(saved);
      // Mutation: the world not hung on the simulation's entities — the
      // resumed match has a fresh river and nothing alight.
      expect(again.world.fires(), hasLength(world.world.fires().length));

      for (var i = 0; i < 120; i++) {
        live.match.step(strategyStep);
        resumed.match.step(strategyStep);
      }
      // Mutation: the world's clock left out of the save (`'clock'` not
      // written) — the resumed wind blows as at the start of a match, leans
      // the flame another way, and the two worlds part.
      // The world's bits, not the whole match's: a restore moves a worker
      // found standing inside a hall's footprint, at its drop-off, out to
      // open ground — `StrategySimulation._settle`, on purpose — so the
      // crowd of a resumed match is not promised to the bit. The world is.
      expect(again.world.snapshot(), world.world.snapshot());
      world.dispose();
      again.dispose();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
