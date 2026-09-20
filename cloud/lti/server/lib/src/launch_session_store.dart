import 'package:flutter3d_lti/flutter3d_lti.dart';

/// A launch this service has verified, kept long enough for the lesson
/// viewer to load and — once `lti-04` wires it up — to report a `check`
/// result back against.
///
/// In-process memory, same reasoning as `PendingLoginStore`; see that file.
/// Outlives the redirect that creates it (unlike a pending login, which is
/// consumed the moment it succeeds) because the viewer reads it again when
/// the student answers a question, on a separate request.
final class LaunchSession {
  const LaunchSession({
    required this.claims,
    required this.lessonAsset,
    required this.issuedAt,
  });

  final LtiLaunchClaims claims;
  final String lessonAsset;
  final DateTime issuedAt;
}

/// A launch session not used within this long is forgotten — long enough
/// for a lesson to actually be worked through, not so long that a sandbox
/// left running for days accumulates every launch anyone ever tried.
const launchSessionTtl = Duration(hours: 4);

final class LaunchSessionStore {
  final _byToken = <String, LaunchSession>{};

  void add(String token, LaunchSession session) {
    _byToken[token] = session;
  }

  /// The session for [token], or null when there is none or it has expired.
  /// Read-only — unlike [PendingLoginStore.take], a launch session is meant
  /// to answer more than one request (the viewer loading, then `lti-04`'s
  /// check-result post), so looking it up does not consume it.
  LaunchSession? get(String token) {
    final session = _byToken[token];
    if (session == null) return null;
    if (DateTime.now().difference(session.issuedAt) > launchSessionTtl) {
      _byToken.remove(token);
      return null;
    }
    return session;
  }
}
