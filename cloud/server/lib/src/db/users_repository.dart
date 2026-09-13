/// Accounts, as rows.
///
/// **The hash never leaves as part of a [User].** It is returned only by
/// [passwordHashOf], which the sign-in handler calls and nothing else does, so
/// there is one place to look when asking whether a hash can reach a page.
library;

import 'package:postgres/postgres.dart';

import '../domain/user.dart';
import 'database.dart';

class UsersRepository {
  const UsersRepository(this._db);

  final Database _db;

  // `email::text`, because the driver has no decoder for `citext` and hands the
  // column back as undecoded bytes. The folding still happens where it matters
  // — in the unique index and in the comparison below.
  static const _columns =
      'id, email::text as email, handle, display_name, email_verified_at, created_at';

  Future<User?> byId(int id) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('select $_columns from users where id = @id'),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _user(rows.first);
  });

  Future<User?> byEmail(String email) => _db.run((session) async {
    final rows = await session.execute(
      // **The cast is what makes this case-insensitive.** The driver sends the
      // parameter as `text`, and `citext = text` resolves to a plain text
      // comparison — `Ann@Example.com` would then find no account for
      // `ann@example.com`, which is the whole reason the column is `citext`.
      Sql.named('select $_columns from users where email = @email::citext'),
      parameters: {'email': email},
    );
    return rows.isEmpty ? null : _user(rows.first);
  });

  Future<User?> byHandle(String handle) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('select $_columns from users where handle = @handle'),
      parameters: {'handle': handle},
    );
    return rows.isEmpty ? null : _user(rows.first);
  });

  /// Creates an account with an unverified address.
  ///
  /// Returns null when the address or the handle is taken — a caller cannot
  /// tell which, and the registration page is careful not to say either.
  Future<User?> create({
    required String email,
    required String handle,
    required String displayName,
    required String passwordHash,
  }) => _db.run((session) async {
    try {
      final rows = await session.execute(
        Sql.named('''
          insert into users (email, handle, display_name, password_hash)
          values (@email, @handle, @name, @hash)
          returning $_columns
        '''),
        parameters: {
          'email': email,
          'handle': handle,
          'name': displayName,
          'hash': passwordHash,
        },
      );
      return _user(rows.first);
    } on ServerException catch (error) {
      // 23505 is a unique violation, which here means the address or the
      // handle is already in use. Anything else is a fault rather than an
      // answer, so it goes up.
      if (error.code == '23505') return null;
      rethrow;
    }
  });

  /// The stored hash, or null when there is no such account.
  Future<String?> passwordHashOf(int userId) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('select password_hash from users where id = @id'),
      parameters: {'id': userId},
    );
    return rows.isEmpty ? null : rows.first[0]! as String;
  });

  Future<void> setPasswordHash(int userId, String hash) =>
      _db.run((session) async {
        await session.execute(
          Sql.named('''
        update users set password_hash = @hash, updated_at = now()
        where id = @id
      '''),
          parameters: {'id': userId, 'hash': hash},
        );
      });

  /// Marks the address confirmed. Confirming twice changes nothing.
  Future<void> markEmailVerified(int userId) => _db.run((session) async {
    await session.execute(
      Sql.named('''
        update users
        set email_verified_at = coalesce(email_verified_at, now()),
            updated_at = now()
        where id = @id
      '''),
      parameters: {'id': userId},
    );
  });

  Future<void> setDisplayName(int userId, String displayName) =>
      _db.run((session) async {
        await session.execute(
          Sql.named('''
            update users set display_name = @name, updated_at = now()
            where id = @id
          '''),
          parameters: {'id': userId, 'name': displayName},
        );
      });

  /// Removes the account, its sessions, its tokens and its models.
  ///
  /// The rows go by cascade; the files they pointed at are swept separately,
  /// because a blob can be shared by another account's identical upload.
  Future<void> delete(int userId) => _db.run((session) async {
    await session.execute(
      Sql.named('delete from users where id = @id'),
      parameters: {'id': userId},
    );
  });

  /// A handle that is free, derived from [email].
  ///
  /// `ann.smith@example.com` becomes `ann-smith`, then `ann-smith-2` and on
  /// until one is unused. It is a starting point rather than a decision: the
  /// settings page can change it.
  Future<String> freeHandleFor(String email) async {
    final base = email
        .split('@')
        .first
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    final stem = base.isEmpty ? 'modeller' : base;

    for (var suffix = 1; suffix < 100; suffix++) {
      final candidate = suffix == 1 ? stem : '$stem-$suffix';
      if (await byHandle(candidate) == null) return candidate;
    }
    // A hundred people whose addresses start the same way is not a case worth
    // a cleverer scheme; the row's own id is unique by construction.
    return '$stem-${DateTime.now().microsecondsSinceEpoch}';
  }

  static User _user(ResultRow row) {
    final map = row.toColumnMap();
    return User(
      id: map['id'] as int,
      email: map['email'] as String,
      handle: map['handle'] as String,
      displayName: map['display_name'] as String,
      emailVerifiedAt: map['email_verified_at'] as DateTime?,
      createdAt: map['created_at'] as DateTime,
    );
  }
}
