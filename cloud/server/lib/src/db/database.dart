/// The connection to Postgres, and the migrations that shape it.
///
/// **Migrations run at start, under a lock.** Two copies of the service coming
/// up at once would otherwise both find the schema one version behind and both
/// try to move it; an advisory lock makes the second one wait and then find
/// nothing left to do.
library;

import 'package:postgres/postgres.dart';

import 'migrations.g.dart';

/// A pool of connections, opened from a `postgres://` URL.
///
/// The URL is the one thing about the database this service knows: a host, a
/// user and a name it was handed. Nothing here builds one.
class Database {
  Database._(this._pool);

  final Pool<void> _pool;

  /// Opens the pool and brings the schema up to date.
  static Future<Database> open(String url, {int maxConnections = 8}) async {
    final endpoint = _endpointOf(url);
    final pool = Pool<void>.withEndpoints(
      [endpoint],
      settings: PoolSettings(
        maxConnectionCount: maxConnections,
        // Cloudflare's tunnel and Postgres are both on this machine, so TLS
        // between them would encrypt a loopback hop. It is off by name rather
        // than by default, so that a database that moves off this machine
        // fails loudly here instead of quietly sending a password in clear.
        sslMode: url.contains('sslmode=require')
            ? SslMode.require
            : SslMode.disable,
      ),
    );

    final database = Database._(pool);
    await database._migrate();
    return database;
  }

  /// Runs [body] on a connection from the pool.
  Future<T> run<T>(Future<T> Function(Session session) body) =>
      _pool.run((session) => body(session));

  /// Runs [body] inside a transaction.
  Future<T> transaction<T>(Future<T> Function(TxSession session) body) =>
      _pool.runTx((session) => body(session));

  Future<void> close() => _pool.close();

  Future<void> _migrate() async {
    await _pool.run((session) async {
      await session.execute('''
        create table if not exists schema_migrations (
          version    integer     primary key,
          name       text        not null,
          applied_at timestamptz not null default now()
        )
      ''');

      // Any constant will do as the lock's name; this one is the digits of
      // "f3d" in decimal, and it only has to differ from other services on the
      // same cluster.
      await session.execute('select pg_advisory_lock(1023100)');
      try {
        final applied = await session.execute('select version from schema_migrations');
        final done = {for (final row in applied) row[0]! as int};

        for (final migration in migrations) {
          if (done.contains(migration.version)) continue;
          // **The simple protocol, and the bookkeeping in the same string.** A
          // migration is many statements, which a prepared statement refuses;
          // and a multi-statement simple query runs as one transaction, so the
          // schema change and the row saying it happened land together or not
          // at all. Inlining the values is safe because both are ours: an int
          // and a file name from this repository.
          final name = migration.name.replaceAll("'", "''");
          await session.execute(
            '${migration.sql}\n;\n'
            "insert into schema_migrations (version, name) values (${migration.version}, '$name');",
            queryMode: QueryMode.simple,
          );
        }
      } finally {
        await session.execute('select pg_advisory_unlock(1023100)');
      }
    });
  }

  static Endpoint _endpointOf(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw ArgumentError.value(
        url,
        'url',
        'expected a postgres:// connection string',
      );
    }
    final [username, password] = switch (uri.userInfo.split(':')) {
      [final user] => [user, ''],
      [final user, final pass] => [user, pass],
      _ => throw ArgumentError.value(url, 'url', 'malformed credentials'),
    };
    return Endpoint(
      host: uri.host.isEmpty ? 'localhost' : uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isEmpty ? 'postgres' : uri.pathSegments.first,
      username: username.isEmpty ? null : Uri.decodeComponent(username),
      password: password.isEmpty ? null : Uri.decodeComponent(password),
    );
  }
}

/// One numbered step of the schema.
class Migration {
  const Migration(this.version, this.name, this.sql);

  final int version;
  final String name;
  final String sql;
}
