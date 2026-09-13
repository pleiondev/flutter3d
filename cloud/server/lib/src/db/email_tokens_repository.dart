/// The links letters carry.
library;

import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import '../auth/tokens.dart';
import 'database.dart';

/// What a letter is for.
enum LetterPurpose {
  /// Confirming that the address exists and belongs to whoever registered.
  verify('verify', Duration(hours: 24)),

  /// Setting a new password without knowing the old one.
  ///
  /// An hour rather than a day: this link is the account, and it sits in a
  /// mailbox that may be read on a shared machine.
  reset('reset', Duration(hours: 1));

  const LetterPurpose(this.column, this.lifetime);

  final String column;
  final Duration lifetime;
}

class EmailTokensRepository {
  const EmailTokensRepository(this._db);

  final Database _db;

  /// Issues a token for [userId] and returns the value that goes into the link.
  ///
  /// Every earlier unused token of the same purpose is spent first: asking for
  /// a second reset letter must make the first one stop working, or a link read
  /// out of an old mailbox stays a way in.
  Future<String> issue(int userId, LetterPurpose purpose) async {
    final token = newToken();
    await _db.transaction((session) async {
      await session.execute(
        Sql.named('''
          update email_tokens set used_at = now()
          where user_id = @user and purpose = @purpose and used_at is null
        '''),
        parameters: {'user': userId, 'purpose': purpose.column},
      );
      await session.execute(
        Sql.named('''
          insert into email_tokens (user_id, purpose, token_sha256, expires_at)
          values (@user, @purpose, @digest, now() + @life::interval)
        '''),
        parameters: {
          'user': userId,
          'purpose': purpose.column,
          'digest': Uint8List.fromList(tokenDigest(token)),
          'life': '${purpose.lifetime.inSeconds} seconds',
        },
      );
    });
    return token;
  }

  /// Whose account [token] is for, without spending it.
  ///
  /// For checking a new password against the account before the link is used
  /// up: a reset link that is spent on a password the rules then refuse would
  /// send the person back to their mailbox for nothing.
  Future<int?> peek(String token, LetterPurpose purpose) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select user_id from email_tokens
        where token_sha256 = @digest and purpose = @purpose
          and used_at is null and expires_at > now()
      '''),
      parameters: {
        'digest': Uint8List.fromList(tokenDigest(token)),
        'purpose': purpose.column,
      },
    );
    return rows.isEmpty ? null : rows.first[0]! as int;
  });

  /// Spends [token] and returns whose account it was for.
  ///
  /// **One statement, so that two clicks cannot both win.** The `used_at is
  /// null` in the update is what makes the second click find nothing, however
  /// close together they arrive.
  Future<int?> spend(String token, LetterPurpose purpose) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        update email_tokens set used_at = now()
        where token_sha256 = @digest
          and purpose = @purpose
          and used_at is null
          and expires_at > now()
        returning user_id
      '''),
      parameters: {
        'digest': Uint8List.fromList(tokenDigest(token)),
        'purpose': purpose.column,
      },
    );
    return rows.isEmpty ? null : rows.first[0]! as int;
  });

  Future<int> sweep() => _db.run((session) async {
    final rows = await session.execute(
      'delete from email_tokens where expires_at < now() - interval \'7 days\'',
    );
    return rows.affectedRows;
  });
}
