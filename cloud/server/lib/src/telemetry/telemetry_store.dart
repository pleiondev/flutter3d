/// Where accepted telemetry runs are kept, as the service needs them.
///
/// **Metrics, not input.** What a run did — its trail, how it ended, how long
/// it took — is kept; the tape it was worked out from is not. The tape is the
/// player's every keypress, and nothing the heatmap answers needs it once the
/// replay has run. A run the server re-simulates under new code later is a
/// run the player sends again, under consent that is still current.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show HeatmapTrail;

/// One accepted run, as it is written.
final class TelemetryRunRow {
  const TelemetryRunRow({
    required this.game,
    required this.levelHash,
    required this.level,
    required this.outcome,
    required this.steps,
    required this.trail,
    required this.eraseKeySha256,
    required this.policy,
    required this.consentedAt,
  });

  final String game;
  final String levelHash;

  /// The level's path, as the run named it — for an operator reading rows,
  /// not for finding the level, which goes by [levelHash].
  final String level;

  /// `won`, `lost` or `unfinished`.
  final String outcome;
  final int steps;
  final List<(double, double)> trail;

  /// The erase key's SHA-256, never the key: a leaked table erases nothing.
  final String eraseKeySha256;

  /// The wording the player agreed to, and when — the record of consent the
  /// run was taken under.
  final String policy;
  final DateTime consentedAt;
}

abstract interface class TelemetryStore {
  /// Keeps [row] and answers its id.
  Future<int> add(TelemetryRunRow row);

  /// Deletes run [id] if [eraseKeySha256] is its key's hash. Whether it was
  /// there and the key wrong, or not there at all, is one answer: false.
  Future<bool> erase(int id, String eraseKeySha256);

  /// The newest [limit] runs of the level [levelHash], as trails.
  Future<List<HeatmapTrail>> trails(String levelHash, {required int limit});
}

/// A store in memory: the tests', and a server's that keeps nothing past a
/// restart.
final class MemoryTelemetryStore implements TelemetryStore {
  final Map<int, TelemetryRunRow> rows = <int, TelemetryRunRow>{};
  int _next = 1;

  @override
  Future<int> add(TelemetryRunRow row) async {
    final id = _next++;
    rows[id] = row;
    return id;
  }

  @override
  Future<bool> erase(int id, String eraseKeySha256) async {
    if (rows[id]?.eraseKeySha256 != eraseKeySha256) return false;
    rows.remove(id);
    return true;
  }

  @override
  Future<List<HeatmapTrail>> trails(
    String levelHash, {
    required int limit,
  }) async => <HeatmapTrail>[
    for (final MapEntry(key: id, value: row) in rows.entries.toList().reversed)
      if (row.levelHash == levelHash) trailOf(id, row),
  ].take(limit).toList();
}

/// [row] as the heatmap bins it: a lost run marks where it was lost.
HeatmapTrail trailOf(int id, TelemetryRunRow row) => HeatmapTrail(
  run: id,
  steps: row.steps,
  outcome: row.outcome,
  positions: row.trail,
  endedBadly: row.outcome == 'lost',
);
