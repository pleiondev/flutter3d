/// Being signed in, as rows.
library;

import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import '../auth/tokens.dart';
import '../domain/user.dart';
import 'database.dart';

/// How long a session lasts without being used.
const sessionLifetime = Duration(days: 30);

class SessionsRepository {
  const SessionsRepository(this._db);

  final Database _db;

  /// Starts a session and returns the token the cookie carries.
  ///
  /// The token is returned once and never stored: the row holds its digest, so
  /// this is the only moment the value exists outside the browser that gets it.
  Future<String> start(
    int userId, {
    String? userAgent,
    String? ip,
    Duration lifetime = sessionLifetime,
  }) async {
    final token = newToken();
    await _db.run((session) async {
      await session.execute(
        Sql.named('''
          insert into sessions (user_id, token_sha256, expires_at, user_agent, ip)
          values (@user, @digest, now() + @life::interval, @agent, @ip::inet)
        '''),
        parameters: {
          'user': userId,
          'digest': Uint8List.fromList(tokenDigest(token)),
          'life': '${lifetime.inSeconds} seconds',
          'agent': userAgent,
          'ip': ip,
        },
      );
    });
    return token;
  }

  /// Who [token] belongs to, or null when it is unknown, expired or gone.
  ///
  /// Also pushes the expiry out: a person who used the service today should not
  /// be signed out because they first signed in thirty days ago.
  Future<User?> whoIs(String token, {Duration lifetime = sessionLifetime}) =>
      _db.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            update sessions
            set last_seen_at = now(), expires_at = now() + @life::interval
            where token_sha256 = @digest and expires_at > now()
            returning user_id
          '''),
          parameters: {
            'digest': Uint8List.fromList(tokenDigest(token)),
            'life': '${lifetime.inSeconds} seconds',
          },
        );
        if (rows.isEmpty) return null;

        final userRows = await session.execute(
          Sql.named('''
            select id, email::text as email, handle, display_name, email_verified_at, created_at
            from users where id = @id
          '''),
          parameters: {'id': rows.first[0]! as int},
        );
        if (userRows.isEmpty) return null;

        final map = userRows.first.toColumnMap();
        return User(
          id: map['id'] as int,
          email: map['email'] as String,
          handle: map['handle'] as String,
          displayName: map['display_name'] as String,
          emailVerifiedAt: map['email_verified_at'] as DateTime?,
          createdAt: map['created_at'] as DateTime,
        );
      });

  /// Ends one session — the sign-out button.
  Future<void> end(String token) => _db.run((session) async {
    await session.execute(
      Sql.named('delete from sessions where token_sha256 = @digest'),
      parameters: {'digest': Uint8List.fromList(tokenDigest(token))},
    );
  });

  /// Ends every session of an account.
  ///
  /// A password that has just changed makes every cookie issued before it
  /// suspect, including the one held by whoever changed it.
  Future<void> endAllFor(int userId) => _db.run((session) async {
    await session.execute(
      Sql.named('delete from sessions where user_id = @id'),
      parameters: {'id': userId},
    );
  });

  /// Removes what has expired. Called by the sweeper, not by a request.
  Future<int> sweep() => _db.run((session) async {
    final rows = await session.execute('delete from sessions where expires_at < now()');
    return rows.affectedRows;
  });
}
