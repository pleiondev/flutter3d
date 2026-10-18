/// `ai-01`'s own JSON shape (`Playtest.heatmap()`), read back — this file
/// deliberately does not depend on `flutter3d_sim_mcp`: the editor is
/// genre-agnostic, and a heatmap is nothing but cells, deaths and a count,
/// none of which name a genre.
final class HeatmapCell {
  /// A cell at grid [x], [z] with its [samples] and [runs].
  const HeatmapCell({
    required this.x,
    required this.z,
    required this.samples,
    required this.runs,
  });

  /// Grid coordinates, in units of the report's own [PlaytestReport.cellSize]
  /// — multiply by it to get world metres.
  final int x;

  /// The cell's z on the grid. See [x].
  final int z;

  /// How many sampled positions fell in the cell, over every run.
  final int samples;

  /// How many runs passed through the cell.
  final int runs;
}

/// Where one playthrough ended in death, and which run to look at for it.
final class DeathPoint {
  /// A death at [x], [z] at [step] of the run seeded [seed].
  const DeathPoint({
    required this.seed,
    required this.step,
    required this.x,
    required this.z,
  });

  /// The seed of the run that died, which plays it again.
  final int seed;

  /// The simulation step it died on.
  final int step;

  /// Where it died along x, in metres.
  final double x;

  /// Where it died along z, in metres.
  final double z;
}

/// A whole `Playtest.heatmap()` answer, parsed once rather than read as a
/// raw map everywhere it is used.
final class PlaytestReport {
  /// A report of [cells] [cellSize] metres a side, [deaths] and [outcomes].
  const PlaytestReport({
    required this.cellSize,
    required this.cells,
    required this.deaths,
    required this.outcomes,
  });

  /// Reads a `Playtest.heatmap()` answer; throws if a field is missing or of
  /// the wrong type.
  factory PlaytestReport.fromJson(Map<String, Object?> json) {
    final cells = <HeatmapCell>[
      for (final row
          in (json['cells']! as List<Object?>).cast<Map<Object?, Object?>>())
        HeatmapCell(
          x: (row['x']! as num).toInt(),
          z: (row['z']! as num).toInt(),
          samples: (row['samples']! as num).toInt(),
          runs: (row['runs']! as num).toInt(),
        ),
    ];
    final deaths = <DeathPoint>[
      for (final row
          in (json['deaths']! as List<Object?>).cast<Map<Object?, Object?>>())
        DeathPoint(
          seed: (row['seed']! as num).toInt(),
          step: (row['step']! as num).toInt(),
          x: (row['x']! as num).toDouble(),
          z: (row['z']! as num).toDouble(),
        ),
    ];
    final outcomes = <String, int>{
      for (final entry in (json['outcomes']! as Map<Object?, Object?>).entries)
        entry.key! as String: (entry.value! as num).toInt(),
    };
    return PlaytestReport(
      cellSize: (json['cellSize']! as num).toDouble(),
      cells: cells,
      deaths: deaths,
      outcomes: outcomes,
    );
  }

  /// A grid cell's side, in metres.
  final double cellSize;

  /// Every cell a run passed through.
  final List<HeatmapCell> cells;

  /// Every run that ended in death, where it did.
  final List<DeathPoint> deaths;

  /// How many runs ended each way, by the outcome's name.
  final Map<String, int> outcomes;

  /// How many runs the report is over: every outcome's count, added.
  int get totalRuns => outcomes.values.fold(0, (a, b) => a + b);

  /// The most samples any cell has; nought with no cells.
  int get maxSamples => cells.isEmpty
      ? 0
      : cells.map((c) => c.samples).reduce((a, b) => a > b ? a : b);
}
