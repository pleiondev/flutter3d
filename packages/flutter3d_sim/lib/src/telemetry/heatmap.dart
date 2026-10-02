/// Where many runs of one level went, binned into cells.
///
/// **One shape for two sources.** `ai-01`'s playtest bins the trails of a
/// random policy, and N7's telemetry bins the trails of real players
/// re-simulated on a server; the editor draws both through the same view. The
/// shape was `Playtest.heatmap`'s map before it was a class here, and the
/// JSON is that map unchanged, so a report written by either reads in the
/// other's reader.
library;

/// The path of one run across a level, as [Heatmap.bin] takes it.
final class HeatmapTrail {
  const HeatmapTrail({
    required this.run,
    required this.steps,
    required this.outcome,
    required this.positions,
    this.endedBadly = false,
  });

  /// Which run this was, by the number its source gives runs: a playtest's
  /// seed, a telemetry server's run id.
  final int run;

  /// The step the run stopped at.
  final int steps;

  /// How it ended, in the source's own word — counted under [Heatmap.outcomes].
  final String outcome;

  /// `(x, z)` samples, in order.
  final List<(double, double)> positions;

  /// Whether the last of [positions] is a place worth marking: where the run
  /// was lost.
  final bool endedBadly;
}

/// One cell of a [Heatmap].
final class HeatmapCell {
  const HeatmapCell({
    required this.x,
    required this.z,
    required this.samples,
    required this.runs,
  });

  /// In cells, not metres: multiply by [Heatmap.cellSize].
  final int x;
  final int z;

  /// How many positions landed here.
  final int samples;

  /// How many distinct runs those positions came from. A run that stood in
  /// one corner for a minute is many samples and one run, and the two numbers
  /// answer different questions: where players linger, and where they pass.
  final int runs;
}

/// Where a run was lost.
final class HeatmapEnd {
  const HeatmapEnd({
    required this.run,
    required this.step,
    required this.x,
    required this.z,
  });

  final int run;
  final int step;
  final double x;
  final double z;
}

/// Thrown when a heatmap document cannot be read.
final class HeatmapFormatException implements Exception {
  const HeatmapFormatException(this.message);

  final String message;

  @override
  String toString() => 'HeatmapFormatException: $message';
}

final class Heatmap {
  const Heatmap({
    required this.cellSize,
    required this.cells,
    required this.ends,
    required this.outcomes,
  });

  /// Bins every position of every trail into squares [cellSize] metres on a
  /// side.
  ///
  /// [outcomeNames] are counted even when no trail ended that way, so a
  /// reader sees `stuck: 0` rather than wondering whether stuck was measured.
  factory Heatmap.bin(
    Iterable<HeatmapTrail> trails, {
    double cellSize = 1.0,
    Iterable<String> outcomeNames = const <String>[],
  }) {
    final listed = trails.toList();
    final samples = <(int, int), int>{};
    final runsThrough = <(int, int), Set<int>>{};
    for (final trail in listed) {
      for (final (x, z) in trail.positions) {
        final cell = ((x / cellSize).floor(), (z / cellSize).floor());
        samples[cell] = (samples[cell] ?? 0) + 1;
        (runsThrough[cell] ??= <int>{}).add(trail.run);
      }
    }
    return Heatmap(
      cellSize: cellSize,
      cells: <HeatmapCell>[
        for (final MapEntry(key: (x, z), value: count) in samples.entries)
          HeatmapCell(
            x: x,
            z: z,
            samples: count,
            runs: runsThrough[(x, z)]!.length,
          ),
      ],
      ends: <HeatmapEnd>[
        for (final trail in listed)
          if (trail.endedBadly && trail.positions.isNotEmpty)
            HeatmapEnd(
              run: trail.run,
              step: trail.steps,
              x: trail.positions.last.$1,
              z: trail.positions.last.$2,
            ),
      ],
      outcomes: <String, int>{
        for (final name in outcomeNames) name: 0,
        for (final name in listed.map((trail) => trail.outcome).toSet())
          name: listed.where((trail) => trail.outcome == name).length,
      },
    );
  }

  /// Reads what [toJson] wrote, or throws a [HeatmapFormatException] naming
  /// the field that is wrong.
  factory Heatmap.fromJson(Map<String, Object?> json) {
    final cellSize = json['cellSize'];
    final cells = json['cells'];
    final ends = json['deaths'];
    final outcomes = json['outcomes'];
    if (cellSize is! num || cellSize <= 0) {
      throw const HeatmapFormatException('the heatmap has no cell size');
    }
    if (cells is! List || ends is! List || outcomes is! Map) {
      throw const HeatmapFormatException(
        'a heatmap has cells, deaths and outcomes, and this lacks one',
      );
    }
    try {
      return Heatmap(
        cellSize: cellSize.toDouble(),
        cells: <HeatmapCell>[
          for (final Map<Object?, Object?> row in cells.cast())
            HeatmapCell(
              x: (row['x']! as num).toInt(),
              z: (row['z']! as num).toInt(),
              samples: (row['samples']! as num).toInt(),
              runs: (row['runs']! as num).toInt(),
            ),
        ],
        ends: <HeatmapEnd>[
          for (final Map<Object?, Object?> row in ends.cast())
            HeatmapEnd(
              run: (row['seed']! as num).toInt(),
              step: (row['step']! as num).toInt(),
              x: (row['x']! as num).toDouble(),
              z: (row['z']! as num).toDouble(),
            ),
        ],
        outcomes: <String, int>{
          for (final MapEntry(:key, :value) in outcomes.entries)
            key! as String: (value! as num).toInt(),
        },
      );
    } on TypeError catch (error) {
      throw HeatmapFormatException('a cell or a death is malformed: $error');
    }
  }

  final double cellSize;
  final List<HeatmapCell> cells;
  final List<HeatmapEnd> ends;
  final Map<String, int> outcomes;

  /// How many runs went in.
  int get runs => outcomes.values.fold(0, (a, b) => a + b);

  /// **`deaths` and `seed` are the keys, and a run id goes under `seed`.**
  /// They are `ai-01`'s, already in reports on disk and in the editor's
  /// reader; renaming them for telemetry would split one format into two for
  /// the sake of a word.
  Map<String, Object?> toJson() => <String, Object?>{
    'cellSize': cellSize,
    'cells': <Map<String, Object?>>[
      for (final cell in cells)
        <String, Object?>{
          'x': cell.x,
          'z': cell.z,
          'samples': cell.samples,
          'runs': cell.runs,
        },
    ],
    'deaths': <Map<String, Object?>>[
      for (final end in ends)
        <String, Object?>{
          'seed': end.run,
          'step': end.step,
          'x': end.x,
          'z': end.z,
        },
    ],
    'outcomes': outcomes,
  };
}
