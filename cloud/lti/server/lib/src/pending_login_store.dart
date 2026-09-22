/// The `state`/`nonce` pairs `/login` has handed out and `/launch` has not
/// yet redeemed.
///
/// In-process memory, not a database — the same reasoning `cloud/lessons`
/// gives for having none at all: a pending login lives for the seconds a
/// browser takes to bounce through the platform's own login screen, not
/// across a restart. A second service instance behind a load balancer would
/// need this shared (Redis, the database `cloud/server` already has) — out
/// of scope for a service `lti-05` deploys as one `systemd` unit.
library;

/// One login this service started and is waiting for the platform to answer.
final class PendingLogin {
  const PendingLogin({required this.nonce, required this.issuedAt});

  final String nonce;
  final DateTime issuedAt;
}

/// A login not redeemed within this long is treated as if it never
/// happened — long enough for a real login screen, short enough that a
/// forgotten tab cannot be replayed hours later.
const pendingLoginTtl = Duration(minutes: 10);

final class PendingLoginStore {
  final _byState = <String, PendingLogin>{};

  void add(String state, String nonce) {
    _byState[state] = PendingLogin(nonce: nonce, issuedAt: DateTime.now());
  }

  /// Removes and returns the pending login for [state] — single-use, so the
  /// same `state` cannot be redeemed twice even if a launch is replayed.
  /// Null when there is none, or the one that was there has expired.
  PendingLogin? take(String state) {
    final pending = _byState.remove(state);
    if (pending == null) return null;
    if (DateTime.now().difference(pending.issuedAt) > pendingLoginTtl) {
      return null;
    }
    return pending;
  }
}
