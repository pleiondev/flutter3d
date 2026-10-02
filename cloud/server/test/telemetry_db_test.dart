/// [TelemetryRepository] against a real database: the trail through `jsonb`
/// and back, and an erase that needs the key.
@Tags(['db'])
library;

import 'dart:io';

import 'package:flutter3d_models/src/db/database.dart';
import 'package:flutter3d_models/src/db/telemetry_repository.dart';
import 'package:flutter3d_models/src/telemetry/telemetry_store.dart';
import 'package:test/test.dart';

TelemetryRunRow _row({String level = 'abcd1234', String outcome = 'lost'}) =>
    TelemetryRunRow(
      game: 'walk',
      levelHash: level,
      level: 'levels/strip.json',
      outcome: outcome,
      steps: 120,
      trail: const <(double, double)>[(0.5, 0.0), (-2.5, 1.25)],
      eraseKeySha256: 'hash-of-key',
      policy: '2026-10',
      consentedAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  late Database db;
  late TelemetryRepository runs;

  setUpAll(() async {
    final url =
        Platform.environment['MODELS_TEST_DATABASE_URL'] ??
        'postgres://models:models@localhost:55432/models';
    db = await Database.open(url);
    runs = TelemetryRepository(db);
  });

  tearDownAll(() => db.close());

  setUp(
    () => db.run(
      (s) => s.execute('truncate telemetry_runs restart identity cascade'),
    ),
  );

  test('a kept run comes back as the trail it was, newest first, and only '
      'for its own level', () async {
    // Mutation: writing the trail as `[x, z]` objects keyed differently, or
    // reading it back in another order, moves every cell of the heatmap.
    final first = await runs.add(_row());
    final second = await runs.add(_row(outcome: 'won'));
    await runs.add(_row(level: 'other'));

    final trails = await runs.trails('abcd1234', limit: 10);

    expect(trails.map((t) => t.run), <int>[second, first]);
    expect(trails.last.positions, const <(double, double)>[
      (0.5, 0.0),
      (-2.5, 1.25),
    ]);
    expect(trails.last.endedBadly, isTrue);
    expect(trails.first.endedBadly, isFalse);
    expect(await runs.trails('abcd1234', limit: 1), hasLength(1));
  });

  test('a run is erased with its key and with nothing else', () async {
    final id = await runs.add(_row());

    expect(await runs.erase(id, 'wrong'), isFalse);
    expect(await runs.trails('abcd1234', limit: 10), hasLength(1));
    expect(await runs.erase(id, 'hash-of-key'), isTrue);
    expect(await runs.trails('abcd1234', limit: 10), isEmpty);
  });
}
