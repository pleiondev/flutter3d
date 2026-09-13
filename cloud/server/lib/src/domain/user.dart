/// Who an account belongs to.
///
/// **The password is not here.** A `User` is what a page is allowed to show and
/// what a handler is allowed to reason about; the hash lives in the repository
/// and leaves it only to be compared. Nothing that renders can accidentally put
/// it in front of somebody.
library;

/// An account, as everything above the database sees it.
class User {
  const User({
    required this.id,
    required this.email,
    required this.handle,
    required this.displayName,
    required this.createdAt,
    this.emailVerifiedAt,
  });

  final int id;

  /// The address letters go to, and the name the account is signed in under.
  ///
  /// Stored as `citext`, so `Ann@example.com` and `ann@example.com` are one
  /// account rather than two — the mail system treats them as one, and a
  /// service that disagreed would hand out a second account for the same
  /// mailbox.
  final String email;

  /// What the catalogue calls this person in a URL: `/u/<handle>`.
  ///
  /// Chosen at registration from the address, then editable. It is separate
  /// from [displayName] because a name people read should be allowed to have
  /// spaces and a name in a URL should not.
  final String handle;

  /// The name shown beside a published model, and the attribution a download
  /// carries.
  final String displayName;

  final DateTime createdAt;

  /// When the address was confirmed, or null while it has not been.
  final DateTime? emailVerifiedAt;

  /// Whether this account may upload and publish.
  ///
  /// Signing in is allowed before this — a person who cannot get in cannot ask
  /// for the letter to be sent again.
  bool get emailVerified => emailVerifiedAt != null;

  User copyWith({
    String? handle,
    String? displayName,
    DateTime? emailVerifiedAt,
  }) => User(
    id: id,
    email: email,
    handle: handle ?? this.handle,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt,
    emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
  );
}
