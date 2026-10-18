/// N10: levels shared behind short codes, and what a moderator and a report do
/// to them.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show ShareBundle, ShareFormatException, ShareStatus;

import '../config.dart';
import 'share_store.dart';
import 'short_code.dart';

/// An answer: the status, and a JSON body. A refusal's body is
/// `{"message": …}` — the sentence `RunService` hands the player, saying what
/// was asked for, why it cannot be, and what to do instead.
typedef ShareAnswer = ({int status, Map<String, Object?> body});

ShareAnswer _say(int status, String message) =>
    (status: status, body: <String, Object?>{'message': message});

/// The longest title and reason kept. A title is a line under a code; a
/// reason is a sentence to a moderator.
const int _titleLimit = 80;
const int _reasonLimit = 500;

final RegExp _gameName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');

/// Files levels by their bytes, hands out codes, and answers them.
///
/// **No account, on purpose, the same as telemetry.** The person pressing
/// Share is the consent, the code is the only handle, and what is shared is a
/// level and a tape — nothing that names who made it unless they typed it
/// into the title. Tying a share to a session would make the code's reader
/// able to find its author, which a short code read aloud should not.
final class ShareService {
  ShareService({
    required this.store,
    this.moderation = ShareModeration.review,
    this.moderatorToken,
    this.reportsToHide = 3,
    this.maxBodyBytes = 4 * 1024 * 1024,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ShareStore store;
  final ShareModeration moderation;

  /// What `Authorization: Bearer …` has to carry on the moderation routes;
  /// null switches them off.
  final String? moderatorToken;

  final int reportsToHide;

  /// The largest bundle accepted. A tape is a few bytes a step, so four
  /// megabytes is hours of play; a level with a heightfield is the larger
  /// half.
  final int maxBodyBytes;

  final DateTime Function() _now;

  /// Whether anything shared here could ever open: in review, only with a
  /// moderator to publish it.
  bool get takesShares =>
      moderation == ShareModeration.open || moderatorToken != null;

  /// `POST /api/v1/shares`.
  Future<ShareAnswer> share(String body) async {
    if (!takesShares) {
      return _say(
        503,
        'this server takes no shares: every one waits for a moderator, and '
        'it has none (MODELS_SHARES_MODERATOR_TOKEN is not set)',
      );
    }
    if (body.length > maxBodyBytes) return tooLarge(maxBodyBytes);
    final json = _object(body);
    if (json == null) return _say(400, 'the body is not a JSON object');
    final ShareBundle bundle;
    try {
      bundle = ShareBundle.fromJson(json);
    } on ShareFormatException catch (error) {
      return _say(422, 'this is not a bundle: ${error.message}');
    }
    if (!_gameName.hasMatch(bundle.game)) {
      return _say(
        422,
        'the game is called "${bundle.game}"; a game name here is up to 40 '
        'lower-case letters, digits, "-" and "_"',
      );
    }
    final title = bundle.title;
    if (title != null && (title.length > _titleLimit || _hasControl(title))) {
      return _say(
        422,
        'the title is ${title.length} characters or has a line break in it; '
        'a title is one line of up to $_titleLimit',
      );
    }
    // Filed by the bytes this server writes, not the ones it was sent: the
    // same bundle with its keys in another order is the same bundle.
    final text = jsonEncode(bundle.toJson());
    final (:record, :created) = await store.file(
      NewShare(
        address: sha256.convert(utf8.encode(text)).toString(),
        bundle: text,
        game: bundle.game,
        levelHash: bundle.levelHash,
        title: title,
        hasRun: bundle.run != null,
        status: switch (moderation) {
          ShareModeration.review => ShareStatus.pending,
          ShareModeration.open => ShareStatus.published,
        },
        createdAt: _now(),
      ),
    );
    return (
      status: created ? 201 : 200,
      body: <String, Object?>{
        'code': record.code,
        'address': record.address,
        'status': record.status.name,
        'message': _statusSentence(record),
      },
    );
  }

  /// `GET /api/v1/shares/<code>`: the bundle when it is published, and where
  /// it stands when it is not.
  Future<ShareAnswer> open(String typed) async {
    final record = await _find(typed);
    if (record == null) return _unknownCode(typed);
    if (record.status == ShareStatus.published) {
      final text = await store.bundleText(record.code);
      return (
        status: 200,
        body: <String, Object?>{
          'code': record.code,
          'status': record.status.name,
          'bundle': jsonDecode(text!),
        },
      );
    }
    return (
      status: record.status == ShareStatus.pending ? 202 : 410,
      body: <String, Object?>{
        'code': record.code,
        'status': record.status.name,
        'message': _statusSentence(record),
      },
    );
  }

  /// `POST /api/v1/shares/<code>/reports` with `{reason}`.
  Future<ShareAnswer> report(String typed, String body) async {
    final code = normaliseCode(Uri.decodeComponent(typed));
    final reason = _object(body)?['reason'];
    if (reason is! String || reason.trim().isEmpty) {
      return _say(422, 'a report says what is wrong with it: {"reason": …}');
    }
    final record = code == null
        ? null
        : await store.report(
            code,
            ShareReport(
              reason: reason.length > _reasonLimit
                  ? reason.substring(0, _reasonLimit)
                  : reason,
              at: _now(),
            ),
            reportsToHide: reportsToHide,
          );
    if (record == null) return _unknownCode(typed);
    return _say(202, 'reported; a moderator will look at "${record.code}"');
  }

  /// `GET /api/v1/moderation/queue`.
  Future<ShareAnswer> queue(String? authorization) async {
    if (_refusedModerator(authorization) case final refused?) return refused;
    final records = await store.queue(limit: 500);
    return (
      status: 200,
      body: <String, Object?>{
        'items': <Map<String, Object?>>[
          for (final record in records) record.toJson(),
        ],
      },
    );
  }

  /// `GET /api/v1/moderation/shares/<code>`: one bundle with its record,
  /// whatever its status.
  Future<ShareAnswer> inspect(String? authorization, String typed) async {
    if (_refusedModerator(authorization) case final refused?) return refused;
    final record = await _find(typed);
    if (record == null) return _unknownCode(typed);
    final text = await store.bundleText(record.code);
    return (
      status: 200,
      body: <String, Object?>{...record.toJson(), 'bundle': jsonDecode(text!)},
    );
  }

  /// `POST /api/v1/moderation/shares/<code>` with
  /// `{decision: publish | remove, reason}`.
  Future<ShareAnswer> decide(
    String? authorization,
    String typed,
    String body,
  ) async {
    if (_refusedModerator(authorization) case final refused?) return refused;
    final json = _object(body);
    if (json == null) return _say(400, 'the body is not a JSON object');
    final decision = switch (json['decision']) {
      'publish' => ShareStatus.published,
      'remove' => ShareStatus.removed,
      _ => null,
    };
    if (decision == null) {
      return _say(422, 'a decision is "publish" or "remove"');
    }
    final note = switch (json['reason']) {
      final String reason when reason.trim().isNotEmpty => reason,
      _ => null,
    };
    if (decision == ShareStatus.removed && note == null) {
      return _say(
        422,
        'a removal says why: the reason is what the code answers with',
      );
    }
    final code = normaliseCode(Uri.decodeComponent(typed));
    final record = code == null
        ? null
        : await store.decide(code, decision, note);
    if (record == null) return _unknownCode(typed);
    return (
      status: 200,
      body: <String, Object?>{
        'code': record.code,
        'status': record.status.name,
        'message': _statusSentence(record),
      },
    );
  }

  Future<ShareRecord?> _find(String typed) async {
    final code = normaliseCode(Uri.decodeComponent(typed));
    return code == null ? null : store.byCode(code);
  }

  /// Null when [authorization] carries the moderator token; otherwise the
  /// refusal.
  ///
  /// Compared in full whatever the first difference, so how long a wrong
  /// token took to refuse says nothing about how much of it was right.
  ShareAnswer? _refusedModerator(String? authorization) {
    final token = moderatorToken;
    if (token == null) {
      return _say(
        503,
        'moderation is off on this server: MODELS_SHARES_MODERATOR_TOKEN is '
        'not set',
      );
    }
    final header = authorization ?? '';
    final given = utf8.encode(
      header.startsWith('Bearer ') ? header.substring(7) : '',
    );
    final wanted = utf8.encode(token);
    final difference = Iterable<int>.generate(wanted.length).fold<int>(
      given.length ^ wanted.length,
      (sum, i) => sum | (wanted[i] ^ (i < given.length ? given[i] : 0)),
    );
    return difference == 0
        ? null
        : _say(
            401,
            'this is for moderators: send Authorization: Bearer '
            '<MODELS_SHARES_MODERATOR_TOKEN>',
          );
  }
}

/// What a code answers, as a sentence.
String _statusSentence(ShareRecord record) => switch (record.status) {
  ShareStatus.published => '"${record.code}" is open to anyone with the code',
  ShareStatus.pending =>
    '"${record.code}" is kept and waits for a moderator before anyone can '
        'open it',
  _ => '"${record.code}" was taken down: ${record.note ?? 'no reason given'}',
};

Map<String, Object?>? _object(String body) {
  try {
    final json = jsonDecode(body);
    return json is Map<String, Object?> ? json : null;
  } on FormatException {
    return null;
  }
}

bool _hasControl(String text) => text.runes.any((int r) => r < 0x20);

/// The answer for a body over [limit] bytes — here, and in the routes that
/// refuse one before it is read whole.
ShareAnswer tooLarge(int limit) =>
    _say(413, 'the body is over the $limit bytes this server takes');

ShareAnswer _unknownCode(String typed) =>
    _say(404, 'no level is shared under "$typed"; check the code');
