/// Where many runs of one level went, binned into cells.
///
/// **One shape for two sources.** `ai-01`'s playtest bins the trails of a
/// random policy, and N7's telemetry bins the trails of real players
/// re-simulated on a server; the editor draws both through the same view. The
/// shape was `Playtest.heatmap`'s map before it was a class here, and the
/// JSON is that map unchanged, so a report written by either reads in the
/// other's reader.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException;

/// One sample of where a run was, in plan: a point of a [HeatmapTrail], a
/// [ResimulationRetraced] trail or a playtest run's path.
final class TrailPoint {
  /// A point at ([x], [z]) in metres in the level's frame.
  const TrailPoint({required this.x, required this.z});

  /// Along the world's X axis, in metres.
  final double x;

  /// Along the world's Z axis, in metres.
  final double z;

  @override
  bool operator ==(Object other) =>
      other is TrailPoint && other.x == x && other.z == z;

  @override
  int get hashCode => Object.hash(x, z);

  @override
  String toString() => 'TrailPoint($x, $z)';
}

/// The path of one run across a level, as [Heatmap.bin] takes it.
final class HeatmapTrail {
  /// A trail of [run]; not ending badly unless [endedBadly] says so.
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

  /// Where the run was, sampled, in order.
  final List<TrailPoint> positions;

  /// Whether the last of [positions] is a place worth marking: where the run
  /// was lost.
  final bool endedBadly;
}

/// One cell of a [Heatmap].
final class HeatmapCell {
  /// The cell at ([x], [z]) in cell coordinates, with its counts.
  const HeatmapCell({
    required this.x,
    required this.z,
    required this.samples,
    required this.runs,
  });

  /// In cells, not metres: multiply by [Heatmap.cellSize].
  final int x;

  /// Index of the cell along Z, in cells as [x]: the floor of the metre
  /// coordinate over [Heatmap.cellSize].
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
  /// Run [run] lost at [step], last seen at ([x], [z]).
  const HeatmapEnd({
    required this.run,
    required this.step,
    required this.x,
    required this.z,
  });

  /// The run's number, as [HeatmapTrail.run]; written as `seed` in JSON.
  final int run;

  /// The step the run stopped at, its [HeatmapTrail.steps].
  final int step;

  /// Where the run was last, across, in metres in the level's frame.
  final double x;

  /// Where the run was last, along Z, in metres, as [x].
  final double z;
}

/// Thrown when a heatmap document cannot be read.
final class HeatmapFormatException extends Flutter3dFormatException {
  /// An exception saying, in [message], what was wrong with the document.
  const HeatmapFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'HeatmapFormatException: $message';
}

/// Many runs of one level binned into square cells: how often each cell
/// was visited and by how many runs, where runs were lost, and how they
/// ended.
final class Heatmap {
  /// A heatmap of the given parts; [Heatmap.bin] builds one from trails.
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
      for (final TrailPoint(:x, :z) in trail.positions) {
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
              x: trail.positions.last.x,
              z: trail.positions.last.z,
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
    } on TypeError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HeatmapFormatException('a cell or a death is malformed: $error'),
        stackTrace,
      );
    }
  }

  /// A cell's side, in metres.
  final double cellSize;

  /// Every cell at least one position landed in, in no set order; a cell
  /// absent here had no samples.
  final List<HeatmapCell> cells;

  /// Where each run that ended badly was lost; written as `deaths`.
  final List<HeatmapEnd> ends;

  /// Count of runs per outcome word, including named outcomes at nought.
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
