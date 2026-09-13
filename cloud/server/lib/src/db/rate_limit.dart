/// Counting attempts, so that guessing a password costs more than trying one.
library;

import 'package:postgres/postgres.dart';

import 'database.dart';

/// How many attempts a bucket allows, over how long.
class RateRule {
  const RateRule(this.limit, this.window);

  final int limit;
  final Duration window;

  /// Sign-in attempts from one address: enough for a person who mistypes,
  /// far too few for a list.
  static const signInPerIp = RateRule(20, Duration(minutes: 15));

  /// Sign-in attempts against one account, from anywhere. This is the one that
  /// stops a guesser who rotates addresses.
  static const signInPerAccount = RateRule(10, Duration(minutes: 15));

  static const registerPerIp = RateRule(5, Duration(hours: 1));

  /// Letters of any kind to one address. A reset form is otherwise a way to
  /// send somebody a hundred letters with our name on them.
  static const lettersPerAddress = RateRule(3, Duration(hours: 1));

  static const lettersPerIp = RateRule(10, Duration(hours: 1));
}

class RateLimiter {
  const RateLimiter(this._db);

  final Database _db;

  /// Records an attempt in [bucket] and says whether it is within [rule].
  ///
  /// **An attempt over the limit is not recorded.** Otherwise somebody who keeps
  /// hammering would keep the window full forever, and a person locked out by
  /// their own typos would stay locked out while an attacker waited next door.
  Future<bool> allow(String bucket, RateRule rule) => _db.transaction((
    session,
  ) async {
    // Serialises attempts on the same bucket, so two requests arriving together
    // cannot both read "one under the limit" and both be let through.
    await session.execute(
      Sql.named('select pg_advisory_xact_lock(hashtext(@bucket))'),
      parameters: {'bucket': bucket},
    );
    final counted = await session.execute(
      Sql.named('''
        select count(*) from rate_events
        where bucket = @bucket and at > now() - @window::interval
      '''),
      parameters: {
        'bucket': bucket,
        'window': '${rule.window.inSeconds} seconds',
      },
    );
    if ((counted.first[0]! as int) >= rule.limit) return false;

    await session.execute(
      Sql.named('insert into rate_events (bucket) values (@bucket)'),
      parameters: {'bucket': bucket},
    );
    return true;
  });

  /// Forgets the attempts in [bucket] — a successful sign-in clears the count
  /// against that account.
  Future<void> clear(String bucket) => _db.run((session) async {
    await session.execute(
      Sql.named('delete from rate_events where bucket = @bucket'),
      parameters: {'bucket': bucket},
    );
  });

  /// Removes events older than any rule looks at.
  Future<int> sweep() => _db.run((session) async {
    final rows = await session.execute(
      "delete from rate_events where at < now() - interval '1 day'",
    );
    return rows.affectedRows;
  });
}
