import 'dart:convert';

import 'share_bundle.dart';

/// One HTTP request, as [RunService] makes it.
final class RunRequest {
  const RunRequest(this.method, this.uri, {this.body});

  final String method;
  final Uri uri;

  /// JSON, or null for a request with no body.
  final String? body;
}

/// What came back: the status and the body as text.
final class RunResponse {
  const RunResponse(this.status, this.body);

  final int status;
  final String body;
}

/// Sends a [RunRequest] and answers with what the server said.
///
/// **Handed in rather than imported, because this package runs everywhere.**
/// `dart:io`'s client does not exist in a browser and `package:http` would be
/// this package's first dependency for one call; a game passes the client it
/// already has in three lines, and a test passes the server's own handler.
typedef RunTransport = Future<RunResponse> Function(RunRequest request);

/// What a call to a service came to.
sealed class ServiceAnswer<T> {
  const ServiceAnswer();
}

final class ServiceDone<T> extends ServiceAnswer<T> {
  const ServiceDone(this.value);

  final T value;
}

/// Not done, and why — in the server's words when it answered.
final class ServiceRefused<T> extends ServiceAnswer<T> {
  const ServiceRefused(this.reason);

  final String reason;
}

/// Where a shared bundle stands with the service's moderation.
///
/// **Constants rather than an enum, because the server decides the set.** A
/// service that grows an `expired` is a service every client written against
/// three values must still understand; [named] answers null for a word it
/// does not know, and a caller treats that as "not open", which is what any
/// status but [published] means to a player.
final class ShareStatus {
  const ShareStatus._(this.name);

  /// Anyone with the code can open it.
  static const ShareStatus published = ShareStatus._('published');

  /// Kept, and waiting for a moderator before anyone can open it.
  static const ShareStatus pending = ShareStatus._('pending');

  /// Taken down; the code answers with the reason.
  static const ShareStatus removed = ShareStatus._('removed');

  static const List<ShareStatus> values = <ShareStatus>[
    published,
    pending,
    removed,
  ];

  /// The word the protocol writes it as.
  final String name;

  /// The status written as [name], or null for one this build does not know.
  static ShareStatus? named(Object? name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return null;
  }

  @override
  String toString() => name;
}

/// A bundle the service has filed: the code to hand out and where it stands.
final class SharedBundle {
  const SharedBundle({
    required this.code,
    required this.address,
    required this.status,
  });

  /// The short code a person types or reads out.
  final String code;

  /// The SHA-256 of the bundle's bytes, which is what it is filed under.
  final String address;

  final ShareStatus status;
}

/// The client side of a sharing service — the `v1/shares` routes of
/// `cloud/server` in this repository, or anybody's server that speaks them.
///
/// **Nothing here shares on its own.** The person pressing Share is the
/// consent; a player's runs sent for telemetry go through
/// `TelemetryUploader`, which asks for its own.
///
/// Every call answers rather than throws: an unreachable server, a refusal and
/// a reply that is not JSON are all a [ServiceRefused] with a sentence.
final class RunService {
  RunService({required this.base, required this.transport});

  /// Where the service is, e.g. `https://runs.pleion.dev/`.
  final Uri base;

  final RunTransport transport;

  /// Files [bundle] and answers with its code.
  ///
  /// Sending the same bundle twice gives the same code: the service files by
  /// the bytes, not by who sent them.
  Future<ServiceAnswer<SharedBundle>> share(ShareBundle bundle) async {
    return switch (await _call('POST', 'v1/shares', bundle.toJson())) {
      _Answered(:final json) => _shared(json),
      _Refusal(:final reason) => ServiceRefused<SharedBundle>(reason),
    };
  }

  /// The bundle behind [code], when it is published.
  Future<ServiceAnswer<ShareBundle>> open(String code) async {
    final Map<String, Object?> json;
    switch (await _call('GET', 'v1/shares/${Uri.encodeComponent(code)}')) {
      case _Refusal(:final reason):
        return ServiceRefused<ShareBundle>(reason);
      case _Answered(json: final answered):
        json = answered;
    }
    final bundle = json['bundle'];
    if (bundle is! Map<String, Object?>) {
      return ServiceRefused<ShareBundle>(
        json['message'] as String? ?? '"$code" is not open to anyone yet',
      );
    }
    try {
      return ServiceDone<ShareBundle>(ShareBundle.fromJson(bundle));
    } on ShareFormatException catch (error) {
      return ServiceRefused<ShareBundle>(
        '"$code" could not be read: ${error.message}',
      );
    }
  }

  /// Tells the service's moderators that [code] should not be shared, and why.
  Future<ServiceAnswer<String>> report(String code, String reason) async {
    final reply = await _call(
      'POST',
      'v1/shares/${Uri.encodeComponent(code)}/reports',
      <String, Object?>{'reason': reason},
    );
    return _message(reply);
  }

  ServiceAnswer<SharedBundle> _shared(Map<String, Object?> json) {
    final code = json['code'];
    final address = json['address'];
    final status = ShareStatus.named(json['status']);
    if (code is! String || address is! String || status == null) {
      return const ServiceRefused<SharedBundle>(
        'the service filed the bundle but did not say under what',
      );
    }
    return ServiceDone<SharedBundle>(
      SharedBundle(code: code, address: address, status: status),
    );
  }

  ServiceAnswer<String> _message(_Reply reply) => switch (reply) {
    _Refusal(:final reason) => ServiceRefused<String>(reason),
    _Answered(:final json) => ServiceDone<String>(
      json['message'] as String? ?? 'done',
    ),
  };

  Future<_Reply> _call(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final uri = base.resolve(path);
    final RunResponse response;
    try {
      response = await transport(
        RunRequest(method, uri, body: body == null ? null : jsonEncode(body)),
      );
    } catch (error) {
      return _Refusal('could not reach $base: $error', 0);
    }
    final Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      return _Refusal(
        'the service answered ${response.status} with something that is '
        'not JSON',
        response.status,
      );
    }
    final json = decoded is Map<String, Object?> ? decoded : null;
    if (response.status < 200 || response.status >= 300 || json == null) {
      return _Refusal(
        json?['message'] as String? ??
            'the service answered ${response.status}',
        response.status,
      );
    }
    return _Answered(json);
  }
}

/// What [RunService._call] came back with.
sealed class _Reply {
  const _Reply();
}

/// A success status and a JSON object.
final class _Answered extends _Reply {
  const _Answered(this.json);

  final Map<String, Object?> json;
}

/// Anything else, as a sentence — the server's `message` when it sent one —
/// and the status it came with, 0 when the server was not reached.
final class _Refusal extends _Reply {
  const _Refusal(this.reason, this.status);

  final String reason;
  final int status;
}
