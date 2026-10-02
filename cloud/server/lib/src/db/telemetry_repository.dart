/// Telemetry runs, as rows — `TelemetryStore` over Postgres.
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart' show HeatmapTrail;
import 'package:postgres/postgres.dart';

import '../telemetry/telemetry_store.dart';
import 'database.dart';

class TelemetryRepository implements TelemetryStore {
  const TelemetryRepository(this._db);

  final Database _db;

  @override
  Future<int> add(TelemetryRunRow row) => _db.run((session) async {
    final inserted = await session.execute(
      Sql.named('''
        insert into telemetry_runs
          (game, level_hash, level, outcome, steps, trail, erase_key_sha256,
           policy, consented_at)
        values
          (@game, @levelHash, @level, @outcome, @steps, @trail::jsonb,
           @eraseKey, @policy, @consentedAt)
        returning id
      '''),
      parameters: {
        'game': row.game,
        'levelHash': row.levelHash,
        'level': row.level,
        'outcome': row.outcome,
        'steps': row.steps,
        'trail': jsonEncode(<List<double>>[
          for (final (x, z) in row.trail) <double>[x, z],
        ]),
        'eraseKey': row.eraseKeySha256,
        'policy': row.policy,
        'consentedAt': row.consentedAt.toUtc(),
      },
    );
    return inserted.first[0]! as int;
  });

  @override
  Future<bool> erase(int id, String eraseKeySha256) => _db.run((session) async {
    final deleted = await session.execute(
      Sql.named(
        'delete from telemetry_runs '
        'where id = @id and erase_key_sha256 = @key',
      ),
      parameters: {'id': id, 'key': eraseKeySha256},
    );
    return deleted.affectedRows == 1;
  });

  @override
  Future<List<HeatmapTrail>> trails(
    String levelHash, {
    required int limit,
  }) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
            select id, steps, outcome, trail from telemetry_runs
            where level_hash = @level
            order by id desc
            limit @limit
          '''),
      parameters: {'level': levelHash, 'limit': limit},
    );
    return <HeatmapTrail>[
      for (final row in rows)
        HeatmapTrail(
          run: row[0]! as int,
          steps: row[1]! as int,
          outcome: row[2]! as String,
          positions: <(double, double)>[
            for (final List<Object?> point in (row[3]! as List<Object?>).cast())
              ((point[0]! as num).toDouble(), (point[1]! as num).toDouble()),
          ],
          endedBadly: row[2] == 'lost',
        ),
    ];
  });
}
