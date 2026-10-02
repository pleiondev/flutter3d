/// One run on its way to a telemetry server, and what sends it.
library;

import 'dart:convert';

import '../save/demo.dart';
import 'telemetry_consent.dart';

/// Thrown when an upload cannot be read.
final class TelemetryUploadFormatException implements Exception {
  const TelemetryUploadFormatException(this.message);

  final String message;

  @override
  String toString() => 'TelemetryUploadFormatException: $message';
}

/// What goes over the wire: which game, the run as a [Demo], and the consent
/// it was sent under.
///
/// **The consent travels with the run**, so the server can refuse a run that
/// arrives without one rather than trusting that every client checked. A
/// client that lies about it can lie; one that forgot is caught.
///
/// **Anonymous by construction.** [Demo.recordedBy] is dropped on the way in:
/// where a level is hard needs no name, and a field that is never sent is a
/// field nobody has to promise to delete.
final class TelemetryUpload {
  TelemetryUpload._({
    required this.game,
    required this.demo,
    required this.policy,
    required this.consentedAt,
  });

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  /// An upload of [demo], or a sentence saying why there is none.
  ///
  /// The only way to build one, and it asks [consent] first: an upload that
  /// exists is an upload somebody agreed to.
  static ({TelemetryUpload? upload, String says}) prepare({
    required String game,
    required Demo demo,
    required TelemetryConsent consent,
    required String policy,
  }) {
    if (!consent.allows(policy)) {
      return (
        upload: null,
        says: switch ((consent.asked, consent.granted)) {
          (false, _) =>
            'not sent: the player has not been asked whether runs may be '
                'sent — ask, and send once they say yes',
          (true, false) => 'not sent: the player said no to sending runs',
          (true, true) =>
            'not sent: the player agreed to policy "${consent.policy}", '
                'and runs go out under "$policy" now — ask again',
        },
      );
    }
    if (demo.steps == 0) {
      return (upload: null, says: 'not sent: the run has no steps');
    }
    return (
      upload: TelemetryUpload._(
        game: game,
        demo: Demo(
          level: demo.level,
          levelHash: demo.levelHash,
          start: demo.start,
          tape: demo.tape,
          buildStamp: demo.buildStamp,
          checkpoints: demo.checkpoints,
          platform: demo.platform,
          dataSources: demo.dataSources,
        ),
        policy: policy,
        consentedAt: consent.at!,
      ),
      says: 'ready: ${demo.steps} steps of ${demo.level}',
    );
  }

  /// Reads an upload, or throws a [TelemetryUploadFormatException] that says
  /// why not — a server's side of [toJson].
  factory TelemetryUpload.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! num) {
      throw const TelemetryUploadFormatException('the upload has no version');
    }
    if (version > formatVersion) {
      throw TelemetryUploadFormatException(
        'the upload is format $version and this reads $formatVersion',
      );
    }
    final game = json['game'];
    if (game is! String || game.isEmpty) {
      throw const TelemetryUploadFormatException('the upload names no game');
    }
    final consent = json['consent'];
    final policy = consent is Map ? consent['policy'] : null;
    final at = consent is Map
        ? DateTime.tryParse(consent['at'] as String? ?? '')
        : null;
    if (policy is! String || policy.isEmpty || at == null) {
      throw const TelemetryUploadFormatException(
        'the upload carries no consent, so it was not agreed to',
      );
    }
    final run = json['run'];
    if (run is! Map<String, Object?>) {
      throw const TelemetryUploadFormatException('the upload has no run');
    }
    final Demo demo;
    try {
      demo = Demo.fromJson(run);
    } on DemoFormatException catch (error) {
      throw TelemetryUploadFormatException('the run: ${error.message}');
    }
    return TelemetryUpload._(
      game: game,
      demo: demo,
      policy: policy,
      consentedAt: at,
    );
  }

  final String game;
  final Demo demo;
  final String policy;
  final DateTime consentedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': formatVersion,
    'game': game,
    'consent': <String, Object?>{
      'policy': policy,
      'at': consentedAt.toUtc().toIso8601String(),
    },
    'run': demo.toJson(),
  };
}

/// What a server gave back for an accepted run: its number there, and the key
/// that takes it back out.
final class TelemetryReceipt {
  const TelemetryReceipt({required this.run, required this.eraseKey});

  final int run;

  /// Shown to nobody but the player who sent the run. With it, and only with
  /// it, the run is deleted — consent withdrawn is a run that is gone, not a
  /// flag on one that stays.
  final String eraseKey;
}

/// The answer to sending one run.
typedef TelemetrySent = ({bool did, String says, TelemetryReceipt? receipt});

/// Where uploads go. The HTTP one is [HttpTelemetrySink]; a test hands in its
/// own.
abstract interface class TelemetrySink {
  Future<TelemetrySent> deliver(TelemetryUpload upload);
}

/// One POST, as this package needs it: a body out, a status and a body back.
///
/// **Handed in rather than imported.** This package runs in a browser and on
/// a server and imports neither `dart:io` nor a client library; whoever has a
/// network wraps theirs in this.
typedef JsonPost =
    Future<({int status, String body})> Function(Uri url, String json);

/// Sends uploads to a server's `POST /api/telemetry/runs`, which the
/// reference server in `cloud/` answers.
final class HttpTelemetrySink implements TelemetrySink {
  const HttpTelemetrySink({required this.endpoint, required this.post});

  /// The server's runs endpoint, in full.
  final Uri endpoint;
  final JsonPost post;

  @override
  Future<TelemetrySent> deliver(TelemetryUpload upload) async {
    final ({int status, String body}) answer;
    try {
      answer = await post(endpoint, jsonEncode(upload.toJson()));
    } catch (error) {
      return (
        did: false,
        says: 'could not reach $endpoint: $error',
        receipt: null,
      );
    }
    final Object? body;
    try {
      body = jsonDecode(answer.body);
    } on FormatException {
      return (
        did: false,
        says: '$endpoint answered ${answer.status} with no JSON',
        receipt: null,
      );
    }
    final says = body is Map && body['says'] is String
        ? body['says'] as String
        : '$endpoint answered ${answer.status}';
    if (answer.status != 201 || body is! Map) {
      return (did: false, says: says, receipt: null);
    }
    final run = body['run'];
    final key = body['eraseKey'];
    if (run is! num || key is! String) {
      return (
        did: false,
        says: '$endpoint took the run and gave no receipt for it',
        receipt: null,
      );
    }
    return (
      did: true,
      says: says,
      receipt: TelemetryReceipt(run: run.toInt(), eraseKey: key),
    );
  }
}

/// Sends a finished run, if and only if the player agreed.
///
/// **The check is here and not in every game**, so a game cannot forget it:
/// [send] reads [consent] at the moment of sending, and the sink is never
/// called without a grant to [policy].
final class TelemetryUploader {
  TelemetryUploader({
    required this.game,
    required this.policy,
    required this.consent,
    required this.sink,
  });

  /// The game's name, as the server knows the games it can re-simulate.
  final String game;

  /// The wording consent is asked under now.
  final String policy;

  /// The player's answer as it stands, read on every send — a player who
  /// withdraws mid-session stops the next run, not the next launch.
  final TelemetryConsent Function() consent;

  final TelemetrySink sink;

  Future<TelemetrySent> send(Demo demo) async {
    final prepared = TelemetryUpload.prepare(
      game: game,
      demo: demo,
      consent: consent(),
      policy: policy,
    );
    final upload = prepared.upload;
    if (upload == null) {
      return (did: false, says: prepared.says, receipt: null);
    }
    return sink.deliver(upload);
  }
}
