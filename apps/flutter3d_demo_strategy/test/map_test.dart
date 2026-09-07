/// The map as a document, and the match that comes out of it.
///
///     flutter test test/map_test.dart
///
/// **What this covers is a move.** The hillside was a sum of sines in
/// `staging.dart` and the camps were coordinates beside it; both now live in
/// `assets/levels/map_a.json`, written by `tool/make_map.py`. A move like that
/// fails quietly in two ways — the ground comes back transposed, or a camp
/// arrives somewhere plausible and wrong — and neither shows up in a picture of
/// a hillside, because any hillside looks like a hillside.
///
/// So the sines are written out once more here, and this is the one place in
/// the repository they are allowed to be: what is being asserted is that the
/// document says the same ground the formula did, which is a claim about a
/// migration and cannot be made without both halves of it. Everything else is
/// read out of the document.
///
/// Nothing here draws. That is the point of the split this test came with: the
/// simulation half of `stage` needs no device, so a match can be assembled — and
/// one day played to its end — without a rasteriser.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The document, read off the disk rather than out of the bundle, so that the
/// tests below are about the file that is committed.
StrategyMap _map() =>
    StrategyMap.parse(File('assets/levels/map_a.json').readAsStringSync());

/// The hillside as `staging.dart` used to compute it, before it became a file.
double _formula(int column, int row, int samples) {
  final double x = column / (samples - 1);
  final double z = row / (samples - 1);
  return math.sin(x * math.pi * 2.0) * 9.0 +
      math.sin(z * math.pi * 3.0 + 1.0) * 6.0 +
      math.sin((x + z) * math.pi * 5.0) * 1.5 +
      14.0;
}

void main() {
  // For the bundle at the foot of this file, and for nothing else here: the
  // asset bundle is a platform channel, and a channel needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the map is a level this build can read, whole', () {
    final Level level = _map().level;

    // Not "no errors" but "nothing at all". A warning here is a real answer —
    // a material nobody defined, a light with no intensity, geometry a body
    // would fall through — and a map that collects them is a map whose
    // warnings nobody reads a year from now.
    expect(
      strategyValidator.validate(level).map((LevelIssue it) => '$it'),
      isEmpty,
    );
  });

  test('the ground is the hillside the code used to compute', () {
    final Heightfield ground = _map().ground;
    expect(ground.columns, 81);
    expect(ground.rows, 81);
    expect(ground.cellSize, 2.0);
    expect(ground.width, 160.0);

    // Every sample, because the failures worth catching here are the ones that
    // are right at the corners: a field written column-major reads back
    // transposed, and this hillside is transposed onto itself along its own
    // diagonal — the two camps sit on it, and both would still be on ground.
    var worst = 0.0;
    for (var row = 0; row < ground.rows; row++) {
      for (var column = 0; column < ground.columns; column++) {
        final double off =
            (ground.sample(column, row) - _formula(column, row, ground.columns))
                .abs();
        if (off > worst) worst = off;
      }
    }
    // A centimetre, which is what the generator quantises to so that the file
    // is the same file on every machine — `math.sin` is the platform's libm,
    // and the `levels` step regenerates this document and diffs it.
    expect(
      worst,
      lessThanOrEqualTo(0.005),
      reason: 'the ground drifted from the formula it was written from',
    );
  });

  test('the document stands the crowd where the code stood it', () {
    final StrategyMap map = _map();
    final StrategyStart start = openMatch(map);
    final StrategySimulation sim = start.simulation;

    // The numbers below are the ones the formula produced on the day it was
    // moved into the file: two camps on the hillside's diagonal, a seam
    // thirty-six metres towards the middle of the map from each, and sixty
    // workers ten to a row eleven-tenths of a metre apart, beginning twelve
    // metres to the near side of the hall and eight beyond it.
    expect(sim.sides, 2);
    expect(sim.units.length, 120);
    expect(start.mine.length, 60);

    expect(sim.buildings.map((Building it) => it.name), <String>[
      'hall',
      'their hall',
    ]);
    expect(sim.buildings.map((Building it) => it.side), <int>[0, 1]);
    expect(sim.buildings[0].centre.x, 36.0);
    expect(sim.buildings[0].centre.z, 36.0);
    expect(sim.buildings[1].centre.x, 124.0);
    expect(sim.buildings[1].centre.z, 124.0);
    expect(sim.buildings.map((Building it) => it.width), <double>[12.0, 12.0]);
    expect(sim.buildings.map((Building it) => it.depth), <double>[10.0, 10.0]);

    expect(sim.resources.map((ResourceNode it) => it.at.x), <double>[
      36.0,
      124.0,
    ]);
    expect(sim.resources.map((ResourceNode it) => it.at.z), <double>[
      72.0,
      88.0,
    ]);
    expect(sim.resources.map((ResourceNode it) => it.amount), <double>[
      1600.0,
      1600.0,
    ]);

    // The corners of each block. The first and the last say the origin, the
    // stride and the wrap all at once; a block that lost its wrap would put
    // sixty units in one row and still start in the right place.
    //
    // A tenth of a millimetre, because a `Vector3` is three single-precision
    // floats: a unit asked to stand at 33.9 stands at 33.900001525878906 and
    // always will. Far below the spacing being checked, which is metres.
    const double stored = 1e-4;
    expect(sim.units.first.position.x, closeTo(24.0, stored));
    expect(sim.units.first.position.z, closeTo(44.0, stored));
    expect(sim.units[59].position.x, closeTo(33.9, stored));
    expect(sim.units[59].position.z, closeTo(49.5, stored));
    expect(sim.units[60].position.x, closeTo(112.0, stored));
    expect(sim.units[60].position.z, closeTo(132.0, stored));
    expect(sim.units.last.position.x, closeTo(121.9, stored));
    expect(sim.units.last.position.z, closeTo(137.5, stored));
    expect(sim.units.first.side, 0);
    expect(sim.units.last.side, 1);

    // Everybody is on the ground rather than at the height the document
    // happened to write for the block they came from.
    for (final Unit unit in sim.units) {
      expect(
        unit.position.y,
        closeTo(map.ground.heightAt(unit.position.x, unit.position.z), stored),
      );
    }

    // A job each, and each pointed at its own side's seam: one job shared
    // would have sixty units filling the same sack, and a job pointed at the
    // wrong seam is a side digging for its opponent.
    final Set<HarvestJob> jobs = <HarvestJob>{};
    for (var i = 0; i < sim.units.length; i++) {
      final HarvestJob job = sim.units[i].job!;
      jobs.add(job);
      expect(identical(job.node, sim.resources[i < 60 ? 0 : 1]), isTrue);
      expect(identical(job.dropOff, sim.buildings[i < 60 ? 0 : 1]), isTrue);
    }
    expect(jobs.length, 120);

    // A hall each that makes more of them, and a purse each that opens empty.
    expect(sim.producers.length, 2);
    expect(sim.producers.map((Producer it) => it.cost), <double>[25.0, 25.0]);
    expect(sim.stock.map((Stockpile it) => it.amount), <double>[0.0, 0.0]);
  });

  test('a smaller crowd is the map with a number changed, not another map', () {
    // What the frame tests ask for: the same document, fewer of them, because
    // a software rasteriser draws a hundred and twenty walking bodies slowly.
    final StrategyStart start = openMatch(_map(), workers: 8);
    expect(start.simulation.units.length, 16);
    expect(start.mine.length, 8);
    expect(start.simulation.buildings.length, 2);
  });

  test('map A is two camps, two seams and a line to cross', () {
    final StrategyMap map = _map();
    expect(map.level.name, 'Map A');
    expect(
      map.level.ofType(StrategyEntities.camp).map((EntityDef it) => it.name),
      <String>['hall', 'their hall'],
    );
    expect(map.level.ofType(StrategyEntities.resourceNode).length, 2);
    expect(map.goal.delivered, 1200.0);

    // The line is inside one seam and well past half of it, which is what
    // makes this a race and not a formality. Above a seam and neither side
    // could win without taking the other's, which this game has no way to do;
    // below half and the match is over before the walk to the seam matters.
    final Iterable<double> seams = map.level
        .ofType(StrategyEntities.resourceNode)
        .map((EntityDef it) => it.number('amount')!);
    for (final double seam in seams) {
      expect(map.goal.delivered, lessThan(seam));
      expect(map.goal.delivered, greaterThan(seam / 2.0));
    }

    // Side nought is the one somebody plays; every other camp is answered by a
    // policy, and a map that staged a camp nobody runs would sit there.
    final StrategyStart start = openMatch(map);
    expect(start.match.bots.map((Bot it) => it.side), <int>[1]);
  });

  test('the bundle hands over the map the demo opens on', () async {
    // `main` asks the asset bundle rather than the disk, and an asset missing
    // from `pubspec.yaml` is a demo that opens to a black screen — which no
    // other test here would notice, because every one of them reads the file.
    final StrategyMap map = await StrategyMap.load();
    expect(map.level.name, 'Map A');
    expect(map.ground.columns, 81);
  });
}
