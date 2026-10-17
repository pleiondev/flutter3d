/// [SharesRepository] against a real database: the bytes through `text` and
/// back unchanged, the unique address deciding a second filing, a code that
/// lengthens when a different bundle holds it, and reports that hide and are
/// answered.
@Tags(['db'])
library;

import 'dart:io';

import 'package:flutter3d_models/src/db/database.dart';
import 'package:flutter3d_models/src/db/shares_repository.dart';
import 'package:flutter3d_models/src/shares/share_store.dart';
import 'package:flutter3d_models/src/shares/short_code.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show ShareStatus;
import 'package:test/test.dart';

/// Not a real SHA-256 of [bundle] — the repository takes the address it is
/// handed — but the shape the column's check asks for.
NewShare _share({
  String address =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
  String bundle = '{"version":1,"game":"walk","levelHash":"abcd1234"}',
  ShareStatus status = ShareStatus.pending,
}) => NewShare(
  address: address,
  bundle: bundle,
  game: 'walk',
  levelHash: 'abcd1234',
  title: null,
  hasRun: false,
  status: status,
  createdAt: DateTime.utc(2026, 10, 1, 12),
);

void main() {
  late Database db;
  late SharesRepository shares;

  setUpAll(() async {
    final url =
        Platform.environment['MODELS_TEST_DATABASE_URL'] ??
        'postgres://models:models@localhost:55432/models';
    db = await Database.open(url);
    shares = SharesRepository(db);
  });

  tearDownAll(() => db.close());

  setUp(
    () => db.run(
      (s) => s.execute('truncate shares, share_reports restart identity'),
    ),
  );

  test('a bundle is kept byte for byte and filed once', () async {
    // Mutation: a `jsonb` column re-orders keys and re-spells numbers, and
    // the code would open bytes its address is not the hash of.
    const bundle = '{"version":1,"z":1.50,"a":{"b":[2,1]}}';
    final first = await shares.file(_share(bundle: bundle));
    final second = await shares.file(_share(bundle: bundle));

    expect(first.created, isTrue);
    expect(second.created, isFalse);
    expect(second.record.code, first.record.code);
    expect(first.record.code, codeOf(first.record.address, shortestCode));
    expect(await shares.bundleText(first.record.code), bundle);
    expect(first.record.createdAt, DateTime.utc(2026, 10, 1, 12));
  });

  test('a code a different bundle holds is lengthened, not shared', () async {
    const one =
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    // Agrees with `one` for its first 39 bits, so its seven-character code
    // (35 bits) is the same and its eight-character one (40) is not.
    const other =
        'a1b2c3d4e4f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    expect(codeOf(other, shortestCode), codeOf(one, shortestCode));

    final first = await shares.file(_share(address: one));
    final second = await shares.file(_share(address: other));

    expect(second.created, isTrue);
    expect(second.record.code, codeOf(other, shortestCode + 1));
    expect(first.record.code, hasLength(shortestCode));
  });

  test('reports hide a published share at the threshold, and publishing it '
      'answers them', () async {
    final code = (await shares.file(
      _share(status: ShareStatus.published),
    )).record.code;

    final once = await shares.report(
      code,
      ShareReport(reason: 'spam', at: DateTime.utc(2026, 10, 2)),
      reportsToHide: 2,
    );
    expect(once!.status, ShareStatus.published);
    final twice = await shares.report(
      code,
      ShareReport(reason: 'still spam', at: DateTime.utc(2026, 10, 3)),
      reportsToHide: 2,
    );
    expect(twice!.status, ShareStatus.pending);
    expect(twice.reports.map((r) => r.reason), <String>['spam', 'still spam']);
    expect(twice.reports.first.at, DateTime.utc(2026, 10, 2));
    expect((await shares.queue(limit: 10)).single.code, code);

    final published = await shares.decide(code, ShareStatus.published, null);
    expect(published!.reports, isEmpty);
    expect(await shares.queue(limit: 10), isEmpty);

    final removed = await shares.decide(code, ShareStatus.removed, 'spam');
    expect(removed!.note, 'spam');
    expect((await shares.byCode(code))!.status, ShareStatus.removed);
  });

  test('a code nobody holds is reported and decided as nothing', () async {
    expect(
      await shares.report(
        'ZZZZZZZ',
        ShareReport(reason: 'x', at: DateTime.utc(2026)),
        reportsToHide: 1,
      ),
      isNull,
    );
    expect(await shares.decide('ZZZZZZZ', ShareStatus.removed, 'x'), isNull);
    expect(await shares.byCode('ZZZZZZZ'), isNull);
    expect(await shares.bundleText('ZZZZZZZ'), isNull);
  });
}
