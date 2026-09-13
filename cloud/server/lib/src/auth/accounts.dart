/// Registering, confirming, signing in and getting back in.
///
/// Every rule about an account is here, above the rows and below the pages: a
/// handler turns a form into a call and an outcome into a response, and this is
/// where "the reset link works once" and "a changed password signs everybody
/// out" are true.
library;

import 'dart:isolate';

import '../db/email_tokens_repository.dart';
import '../db/models_repository.dart';
import '../db/rate_limit.dart';
import '../db/sessions_repository.dart';
import '../db/users_repository.dart';
import '../domain/user.dart';
import '../mail/letters.dart';
import '../mail/mailer.dart';
import '../storage/blob_store.dart';
import 'password_policy.dart';
import 'passwords.dart';

// The rules live beside this file and are re-exported, so that a page that
// already reads outcomes from here reads the password rules from here too.
export 'password_policy.dart';

class Accounts {
  Accounts({
    required this.users,
    required this.sessions,
    required this.tokens,
    required this.models,
    required this.limiter,
    required this.mailer,
    required this.blobs,
    required this.baseUrl,
  });

  final UsersRepository users;
  final SessionsRepository sessions;
  final EmailTokensRepository tokens;
  final ModelsRepository models;
  final RateLimiter limiter;
  final Mailer mailer;
  final BlobStore blobs;
  final String baseUrl;

  /// Compared against when the address has no account, so that a wrong
  /// address takes as long to refuse as a wrong password. Otherwise the time a
  /// sign-in takes says which addresses are registered.
  late final Future<String> _decoy = _hash('a password nobody has');

  Future<RegisterOutcome> register({
    required String email,
    required String password,
    required String passwordConfirmation,
    required String displayName,
    required String ip,
    String? userAgent,
  }) async {
    final address = email.trim();
    final name = displayName.trim().isEmpty
        ? address.split('@').first
        : displayName.trim();
    final weak = passwordProblems(password, email: address, displayName: displayName.trim());

    final problems = {
      if (!isPlausibleEmail(address)) 'email': 'That does not look like an email address.',
      if (weak.isNotEmpty) 'password': weak.join(' '),
      // Compared exactly, spaces and all: a confirmation exists to catch the
      // typo, and trimming would hide the one typo a phrase is prone to.
      if (passwordConfirmation != password) 'passwordConfirm': 'The two passwords do not match.',
      if (name.length > 60) 'displayName': 'Keep the name under 60 characters.',
    };
    if (problems.isNotEmpty) return RegisterInvalid(problems);

    if (!await limiter.allow('register:ip:$ip', RateRule.registerPerIp)) {
      return const RegisterLimited();
    }

    // **Taken addresses are said to be taken.** Hiding it would mean not
    // signing a new person in either, and registration is already the most
    // rate-limited door there is; the trade is stated here so it can be
    // revisited, not made quietly.
    if (await users.byEmail(address) != null) {
      return const RegisterInvalid({
        'email': 'An account with this address already exists. Sign in, or '
            'reset the password if it is forgotten.',
      });
    }

    final created = await users.create(
      email: address,
      handle: await users.freeHandleFor(address),
      displayName: name,
      passwordHash: await _hash(password),
    );
    // Lost a race with a second registration of the same address or handle.
    if (created == null) {
      return const RegisterInvalid({
        'email': 'An account with this address already exists.',
      });
    }

    await _sendVerification(created);
    final session = await sessions.start(created.id, userAgent: userAgent, ip: ip);
    return Registered(created, session);
  }

  /// Sends the confirmation letter again, when the first one went missing.
  Future<bool> resendVerification(User user, {required String ip}) async {
    if (user.emailVerified) return true;
    final allowed =
        await limiter.allow('letters:to:${user.email.toLowerCase()}', RateRule.lettersPerAddress) &&
        await limiter.allow('letters:ip:$ip', RateRule.lettersPerIp);
    if (!allowed) return false;
    await _sendVerification(user);
    return true;
  }

  /// Confirms the address [token] was issued for. Returns the account, or null
  /// when the link is unknown, used or expired.
  Future<User?> verify(String token) async {
    final userId = await tokens.spend(token, LetterPurpose.verify);
    if (userId == null) return null;
    await users.markEmailVerified(userId);
    return users.byId(userId);
  }

  Future<SignInOutcome> signIn({
    required String email,
    required String password,
    required String ip,
    String? userAgent,
  }) async {
    final address = email.trim().toLowerCase();
    final allowed =
        await limiter.allow('signin:ip:$ip', RateRule.signInPerIp) &&
        await limiter.allow('signin:to:$address', RateRule.signInPerAccount);
    if (!allowed) return const SignInLimited();

    final user = await users.byEmail(address);
    final stored = user == null ? null : await users.passwordHashOf(user.id);
    final matches = await _verify(password, stored ?? await _decoy);
    if (user == null || stored == null || !matches) return const SignInRefused();

    await limiter.clear('signin:to:$address');
    if (needsRehash(stored)) {
      await users.setPasswordHash(user.id, await _hash(password));
    }
    final token = await sessions.start(user.id, userAgent: userAgent, ip: ip);
    return SignedIn(user, token);
  }

  Future<void> signOut(String sessionToken) => sessions.end(sessionToken);

  /// Sends a reset letter when [email] has an account, and does the same
  /// visible nothing when it does not.
  ///
  /// Returns false only when rate limited — and the limit is counted whether
  /// or not the address exists, so the limit itself says nothing either.
  Future<bool> requestReset({required String email, required String ip}) async {
    final address = email.trim().toLowerCase();
    final allowed =
        await limiter.allow('letters:ip:$ip', RateRule.lettersPerIp) &&
        await limiter.allow('letters:to:$address', RateRule.lettersPerAddress);
    if (!allowed) return false;

    final user = await users.byEmail(address);
    if (user == null) return true;

    final token = await tokens.issue(user.id, LetterPurpose.reset);
    await mailer.send(
      resetLetter(to: user.email, name: user.displayName, link: _link('/reset', token)),
    );
    return true;
  }

  /// Sets a new password from a reset link.
  ///
  /// **The password is judged before the link is spent.** A link used up on a
  /// password the rules then refuse would send the person back to their mailbox
  /// for a new letter, for a mistake the form could have shown them in place.
  Future<ResetOutcome> reset({
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    final owner = await tokens.peek(token, LetterPurpose.reset);
    final account = owner == null ? null : await users.byId(owner);
    if (account == null) return const ResetLinkInvalid();

    final weak = passwordProblems(password, email: account.email, displayName: account.displayName);
    if (weak.isNotEmpty) return ResetPasswordRefused(weak.join(' '));
    if (passwordConfirmation != password) {
      return const ResetPasswordRefused('The two passwords do not match.');
    }

    // Spent only now, and atomically: a second click that got here first wins,
    // and this one finds the link gone.
    final userId = await tokens.spend(token, LetterPurpose.reset);
    if (userId != account.id) return const ResetLinkInvalid();
    final user = account;

    await _replacePassword(user, password);
    // Following a reset link proves the address, so an account that never
    // confirmed it has now.
    await users.markEmailVerified(user.id);
    return ResetDone(user);
  }

  /// Changes the password of a signed-in account, which must know the old one.
  ///
  /// Null when the password changed; otherwise the sentence saying why not.
  Future<String?> changePassword(
    User user, {
    required String current,
    required String next,
    required String confirmation,
  }) async {
    // Counted against the same bucket as signing in: a stolen session should
    // not be an unlimited way to guess the password it was not given.
    if (!await limiter.allow('signin:to:${user.email.toLowerCase()}', RateRule.signInPerAccount)) {
      return 'Too many attempts. Wait fifteen minutes and try again.';
    }
    final stored = await users.passwordHashOf(user.id);
    if (stored == null || !await _verify(current, stored)) {
      return 'The current password is not right.';
    }
    final weak = passwordProblems(next, email: user.email, displayName: user.displayName);
    if (weak.isNotEmpty) return weak.join(' ');
    if (confirmation != next) return 'The two new passwords do not match.';
    if (next == current) return 'The new password is the same as the current one.';

    await _replacePassword(user, next);
    return null;
  }

  /// Deletes the account and every file nobody else's model still points at.
  Future<bool> deleteAccount(User user, {required String password}) async {
    final stored = await users.passwordHashOf(user.id);
    if (stored == null || !await _verify(password, stored)) return false;

    final hashes = await models.blobsOfOwner(user.id);
    await users.delete(user.id);
    for (final hash in hashes.toSet()) {
      if (!await models.isReferenced(hash)) await blobs.delete(hash);
    }
    return true;
  }

  Future<void> _replacePassword(User user, String password) async {
    await users.setPasswordHash(user.id, await _hash(password));
    await sessions.endAllFor(user.id);
    await mailer.send(
      passwordChangedLetter(
        to: user.email,
        name: user.displayName,
        resetLink: Uri.parse('$baseUrl/forgot'),
      ),
    );
  }

  Future<void> _sendVerification(User user) async {
    final token = await tokens.issue(user.id, LetterPurpose.verify);
    await mailer.send(
      verificationLetter(to: user.email, name: user.displayName, link: _link('/verify', token)),
    );
  }

  Uri _link(String path, String token) => Uri.parse('$baseUrl$path?token=$token');

  // Argon2 is a hundred-odd milliseconds of arithmetic. On the request isolate
  // that is a hundred milliseconds in which no other page is served, so it goes
  // to its own isolate and the event loop keeps turning.
  static Future<String> _hash(String password) => Isolate.run(() => hashPassword(password));

  static Future<bool> _verify(String password, String stored) =>
      Isolate.run(() => verifyPassword(password, stored));
}

/// Good enough to catch a typo, deliberately not a validator. The only real
/// check of an address is a letter that arrives.
bool isPlausibleEmail(String value) =>
    value.length <= 254 && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

sealed class RegisterOutcome {
  const RegisterOutcome();
}

final class Registered extends RegisterOutcome {
  const Registered(this.user, this.sessionToken);

  final User user;
  final String sessionToken;
}

/// The form, with a sentence for each field that is wrong.
final class RegisterInvalid extends RegisterOutcome {
  const RegisterInvalid(this.problems);

  final Map<String, String> problems;
}

final class RegisterLimited extends RegisterOutcome {
  const RegisterLimited();
}

sealed class SignInOutcome {
  const SignInOutcome();
}

final class SignedIn extends SignInOutcome {
  const SignedIn(this.user, this.sessionToken);

  final User user;
  final String sessionToken;
}

/// Wrong address or wrong password — deliberately one outcome.
final class SignInRefused extends SignInOutcome {
  const SignInRefused();
}

final class SignInLimited extends SignInOutcome {
  const SignInLimited();
}

sealed class ResetOutcome {
  const ResetOutcome();
}

final class ResetDone extends ResetOutcome {
  const ResetDone(this.user);

  final User user;
}

final class ResetLinkInvalid extends ResetOutcome {
  const ResetLinkInvalid();
}

/// The link is good and the password is not. The link has not been spent.
final class ResetPasswordRefused extends ResetOutcome {
  const ResetPasswordRefused(this.because);

  final String because;
}
