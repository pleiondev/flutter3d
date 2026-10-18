/// Shared levels, as rows — `ShareStore` over Postgres.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show ShareStatus;
import 'package:postgres/postgres.dart';

import '../shares/share_store.dart';
import '../shares/short_code.dart';
import 'database.dart';

/// A record with its open reports, read in one query: the reports come back
/// as one `json` array per row rather than a second round trip a share.
const String _record = '''
  select s.code, s.address, s.game, s.level_hash, s.title, s.has_run,
         s.created_at, s.status, s.note,
         coalesce(
           (select json_agg(json_build_object(
                     'reason', r.reason, 'at', r.reported_at) order by r.id)
              from share_reports r where r.code = s.code),
           '[]'::json)
    from shares s
''';

class SharesRepository implements ShareStore {
  const SharesRepository(this._db);

  final Database _db;

  /// **One insert a candidate code, and the unique address decides the
  /// race.** `on conflict do nothing` covers both constraints: when nothing
  /// was inserted, either the same bundle is already filed — whoever filed it
  /// — or a different one holds this code and the next, longer one is tried.
  @override
  Future<({ShareRecord record, bool created})> file(NewShare share) => _db.run((
    session,
  ) async {
    for (final code in codesOf(share.address)) {
      final inserted = await session.execute(
        Sql.named('''
              insert into shares
                (code, address, game, level_hash, title, has_run, bundle,
                 status, created_at)
              values
                (@code, @address, @game, @levelHash, @title:text, @hasRun,
                 @bundle, @status, @createdAt)
              on conflict do nothing
              returning code
            '''),
        parameters: {
          'code': code,
          'address': share.address,
          'game': share.game,
          'levelHash': share.levelHash,
          'title': share.title,
          'hasRun': share.hasRun,
          'bundle': share.bundle,
          'status': share.status.name,
          'createdAt': share.createdAt.toUtc(),
        },
      );
      if (inserted.isNotEmpty) {
        return (record: (await _one(session, 's.code', code))!, created: true);
      }
      final known = await _one(session, 's.address', share.address);
      if (known != null) return (record: known, created: false);
    }
    throw StateError('every code of ${share.address} is taken');
  });

  @override
  Future<ShareRecord?> byCode(String code) =>
      _db.run((session) => _one(session, 's.code', code));

  @override
  Future<String?> bundleText(String code) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('select bundle from shares where code = @code'),
      parameters: {'code': code},
    );
    return rows.isEmpty ? null : rows.first[0]! as String;
  });

  /// The row is locked first, so two reports at once count each other.
  @override
  Future<ShareRecord?> report(
    String code,
    ShareReport report, {
    required int reportsToHide,
  }) => _db.transaction((session) async {
    final locked = await session.execute(
      Sql.named('select 1 from shares where code = @code for update'),
      parameters: {'code': code},
    );
    if (locked.isEmpty) return null;
    await session.execute(
      Sql.named('''
        insert into share_reports (code, reason, reported_at)
        values (@code, @reason, @at)
      '''),
      parameters: {
        'code': code,
        'reason': report.reason,
        'at': report.at.toUtc(),
      },
    );
    await session.execute(
      Sql.named('''
        update shares set status = 'pending'
         where code = @code and status = 'published'
           and (select count(*) from share_reports where code = @code)
               >= @reportsToHide
      '''),
      parameters: {'code': code, 'reportsToHide': reportsToHide},
    );
    return _one(session, 's.code', code);
  });

  @override
  Future<ShareRecord?> decide(String code, ShareStatus status, String? note) =>
      _db.transaction((session) async {
        final updated = await session.execute(
          Sql.named('''
            update shares set status = @status, note = @note:text
             where code = @code
            returning code
          '''),
          parameters: {'code': code, 'status': status.name, 'note': note},
        );
        if (updated.isEmpty) return null;
        if (status == ShareStatus.published) {
          await session.execute(
            Sql.named('delete from share_reports where code = @code'),
            parameters: {'code': code},
          );
        }
        return _one(session, 's.code', code);
      });

  @override
  Future<List<ShareRecord>> queue({required int limit}) =>
      _db.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            $_record
             where s.status = 'pending'
                or exists (select 1 from share_reports r where r.code = s.code)
             order by s.created_at, s.code
             limit @limit
          '''),
          parameters: {'limit': limit},
        );
        return <ShareRecord>[for (final row in rows) _recordOf(row)];
      });

  /// The record whose [column] is [value]; the column is one of two names
  /// written in this file, never anything a request supplied.
  static Future<ShareRecord?> _one(
    Session session,
    String column,
    String value,
  ) async {
    final rows = await session.execute(
      Sql.named('$_record where $column = @value'),
      parameters: {'value': value},
    );
    return rows.isEmpty ? null : _recordOf(rows.first);
  }

  static ShareRecord _recordOf(ResultRow row) => ShareRecord(
    code: row[0]! as String,
    address: row[1]! as String,
    game: row[2]! as String,
    levelHash: row[3]! as String,
    title: row[4] as String?,
    hasRun: row[5]! as bool,
    createdAt: row[6]! as DateTime,
    // The check constraint holds the column to the three names.
    status: ShareStatus.named(row[7])!,
    note: row[8] as String?,
    reports: <ShareReport>[
      for (final Map<String, Object?> report
          in (row[9]! as List<Object?>).cast())
        ShareReport(
          reason: report['reason']! as String,
          at: DateTime.parse(report['at']! as String),
        ),
    ],
  );
}
