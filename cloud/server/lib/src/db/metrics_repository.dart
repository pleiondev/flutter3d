/// The three counts an operator actually wants at 3am: how many accounts
/// exist, how many models have been uploaded, and how much disk they hold.
///
/// **One query per number, not one query that returns three columns.** The
/// counts come from different tables and nothing needs them to be from the
/// same transaction snapshot to the microsecond — a scrape that lands between
/// two of them is at most one upload old, which is not a number anybody is
/// paging on.
library;

import 'database.dart';

/// A snapshot of the service's own size, at the moment it was taken.
class MetricsSnapshot {
  const MetricsSnapshot({
    required this.registeredUsers,
    required this.verifiedUsers,
    required this.models,
    required this.storageBytes,
  });

  final int registeredUsers;
  final int verifiedUsers;
  final int models;

  /// The bytes actually on disk, not the sum of every upload.
  ///
  /// A blob is content-addressed and stored once, so this sums one row per
  /// distinct hash rather than per model — two people uploading the same cube
  /// cost this number one cube, the same way they cost the disk one.
  final int storageBytes;
}

class MetricsRepository {
  const MetricsRepository(this._db);

  final Database _db;

  Future<MetricsSnapshot> snapshot() => _db.run((session) async {
    final users = await session.execute(
      'select count(*), count(*) filter (where email_verified_at is not null) from users',
    );
    final models = await session.execute('select count(*) from models');
    // `group by blob_sha256` is what turns "every upload" into "every distinct
    // file": two models pointing at the same hash contribute one row here, the
    // way `FileBlobStore` put them on disk as one file.
    // `sum()` over a `bigint` column answers `numeric` in Postgres, which the
    // driver hands back as a string rather than risk losing precision — cast
    // it back to `bigint` here, where the range is not in question, rather
    // than parse a string on the Dart side.
    final storage = await session.execute('''
      select coalesce(sum(bytes), 0)::bigint from (
        select blob_sha256, max(bytes) as bytes from model_files group by blob_sha256
      ) distinct_blobs
    ''');

    return MetricsSnapshot(
      registeredUsers: users.first[0]! as int,
      verifiedUsers: users.first[1]! as int,
      models: models.first[0]! as int,
      storageBytes: storage.first[0]! as int,
    );
  });
}
