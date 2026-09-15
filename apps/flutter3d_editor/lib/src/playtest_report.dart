/// `ai-01`'s own JSON shape (`Playtest.heatmap()`), read back — this file
/// deliberately does not depend on `flutter3d_sim_mcp`: the editor is
/// genre-agnostic, and a heatmap is nothing but cells, deaths and a count,
/// none of which name a genre.
final class HeatmapCell {
  const HeatmapCell({
    required this.x,
    required this.z,
    required this.samples,
    required this.runs,
  });

  /// Grid coordinates, in units of the report's own [PlaytestReport.cellSize]
  /// — multiply by it to get world metres.
  final int x;
  final int z;
  final int samples;
  final int runs;
}

/// Where one playthrough ended in death, and which run to look at for it.
final class DeathPoint {
  const DeathPoint({
    required this.seed,
    required this.step,
    required this.x,
    required this.z,
  });

  final int seed;
  final int step;
  final double x;
  final double z;
}

/// A whole `Playtest.heatmap()` answer, parsed once rather than read as a
/// raw map everywhere it is used.
final class PlaytestReport {
  const PlaytestReport({
    required this.cellSize,
    required this.cells,
    required this.deaths,
    required this.outcomes,
  });

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

  final double cellSize;
  final List<HeatmapCell> cells;
  final List<DeathPoint> deaths;
  final Map<String, int> outcomes;

  int get totalRuns => outcomes.values.fold(0, (a, b) => a + b);

  int get maxSamples => cells.isEmpty
      ? 0
      : cells.map((c) => c.samples).reduce((a, b) => a > b ? a : b);
}
