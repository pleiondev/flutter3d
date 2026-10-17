/// One run on its way to a telemetry server, and what sends it.
library;

import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show FormatDocument, FormatMigration, FormatSpec, Flutter3dFormatException;

import '../save/demo.dart';
import 'telemetry_consent.dart';

/// Thrown when an upload cannot be read.
final class TelemetryUploadFormatException extends Flutter3dFormatException {
  const TelemetryUploadFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'TelemetryUploadFormatException: $message';
}

/// What [TelemetryUpload.prepare] made: the upload, or none and why.
///
/// A class rather than a record, so a later field is not a break.
final class PreparedUpload {
  const PreparedUpload({required this.upload, required this.says});

  /// The upload, or null when the player did not agree or there is no run.
  final TelemetryUpload? upload;

  /// What happened, in a sentence a settings screen can show.
  final String says;
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
final class TelemetryUpload extends FormatDocument {
  TelemetryUpload._({
    required this.game,
    required this.demo,
    required this.policy,
    required this.consentedAt,
    super.unknown,
  });

  /// Reads an upload, or throws a [TelemetryUploadFormatException] that says
  /// why not — a server's side of [toJson].
  factory TelemetryUpload.fromJson(Map<String, Object?> json) =>
      TelemetryUpload._read(json);

  factory TelemetryUpload._read(Map<String, Object?> document) {
    final version = document['version'];
    if (version is! num || version < 1) {
      throw const TelemetryUploadFormatException('the upload has no version');
    }

    // A server reads every upload any 1.x game sent (decision 8 of
    // `tasks/1.0-stability.md`): older formats are lifted step by step.
    // Mutation: skip the chain and an old upload reads with new meanings.
    // A newer one is refused by the spec, naming both versions.
    final json = format.open(
      document,
      refuse: TelemetryUploadFormatException.new,
    );
    final game = json['game'];
    if (game is! String || game.isEmpty) {
      throw const TelemetryUploadFormatException('the upload names no game');
    }
    final consent = json['consent'];
    final policy = consent is Map ? consent['policy'] : null;
    // A consent whose `at` is anything but a string is no consent: refused
    // with this format's own exception, never a `TypeError` from a cast.
    final at = switch (consent) {
      {'at': final String said} => DateTime.tryParse(said),
      _ => null,
    };
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
    } on DemoFormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        TelemetryUploadFormatException('the run: ${error.message}'),
        stackTrace,
      );
    }
    return TelemetryUpload._(
      game: game,
      demo: demo,
      policy: policy,
      consentedAt: at,
      unknown: FormatDocument.unknownIn(json, known: _known),
    );
  }

  /// Bumped when an existing field changes meaning, with a step in
  /// [_migrations] and a fixture under `test/fixtures/v<N>/`.
  static const int formatVersion = 1;

  /// Entry `i` lifts an upload from version `i + 1` to `i + 2`; empty while
  /// version 1 is the only one, so reading it is the identity.
  static const List<FormatMigration> _migrations = <FormatMigration>[];

  /// The telemetry upload in the registry: `f3d.telemetry`. The envelope is
  /// additive at version 1, so a server from before it reads one.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.telemetry',
    version: formatVersion,
    suffixes: <String>['.upload.json'],
    fixture: 'test/fixtures/v<N>/upload.json',
    migrations: _migrations,
  );

  static const Set<String> _known = <String>{'game', 'consent', 'run'};

  final String game;

  final Demo demo;

  final String policy;
  final DateTime consentedAt;
  @override
  FormatSpec get spec => format;

  /// An upload of [demo], or a sentence saying why there is none.
  ///
  /// The only way to build one, and it asks [consent] first: an upload that
  /// exists is an upload somebody agreed to.
  static PreparedUpload prepare({
    required String game,
    required Demo demo,
    required TelemetryConsent consent,
    required String policy,
  }) {
    if (!consent.allows(policy)) {
      return PreparedUpload(
        upload: null,
        says: switch ((consent.wasAsked, consent.isGranted)) {
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
      return const PreparedUpload(
        upload: null,
        says: 'not sent: the run has no steps',
      );
    }
    return PreparedUpload(
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
          // What the server plays it again on: see `Demo.physics`.
          physics: demo.physics,
          // Everything the run is beyond its tape, so the server plays the
          // same run, or refuses it on its simulation: a swap or a loop
          // change left out replays as another run. Only `recordedBy`, who
          // the player is, stays on the device.
          levelSwaps: demo.levelSwaps,
          loopChanges: demo.loopChanges,
          events: demo.events,
          simulation: demo.simulation,
          poses: demo.poses,
          probes: demo.probes,
          unknown: demo.unknown,
        ),
        policy: policy,
        consentedAt: consent.at!,
      ),
      says: 'ready: ${demo.steps} steps of ${demo.level}',
    );
  }

  Map<String, Object?> toJson() => write(<String, Object?>{
    'game': game,
    'consent': <String, Object?>{
      'policy': policy,
      'at': consentedAt.toUtc().toIso8601String(),
    },
    'run': demo.toJson(),
  });
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
///
/// **A class, so the answer can carry more in a minor** (a server's quota, a
/// retry time): a [TelemetrySink] somebody writes returns one, and a record
/// it returned could never gain a field.
final class TelemetrySent {
  const TelemetrySent({required this.did, required this.says, this.receipt});

  /// Whether the server took the run.
  final bool did;

  /// The sentence to show about it, taken or refused.
  final String says;

  /// What the server gave back for a run it took; null for a refusal.
  final TelemetryReceipt? receipt;

  /// Equal to another answer with the same [did], [says] and [receipt], as
  /// the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is TelemetrySent &&
      other.did == did &&
      other.says == says &&
      other.receipt == receipt;

  @override
  int get hashCode => Object.hash(did, says, receipt);

  @override
  String toString() => 'TelemetrySent(did: $did, says: $says)';
}

/// Where uploads go. The HTTP one is [HttpTelemetrySink]; a test hands in its
/// own.
///
/// **Extended outside this package: an `abstract base class`** (decision 5
/// of `tasks/1.0-api-review.md`), so a member added in a minor arrives with a
/// default body and every sink keeps compiling.
abstract base class TelemetrySink {
  const TelemetrySink();

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
final class HttpTelemetrySink extends TelemetrySink {
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
      return TelemetrySent(
        did: false,
        says: 'could not reach $endpoint: $error',
        receipt: null,
      );
    }
    final Object? body;
    try {
      body = jsonDecode(answer.body);
    } on FormatException {
      return TelemetrySent(
        did: false,
        says: '$endpoint answered ${answer.status} with no JSON',
        receipt: null,
      );
    }
    final says = body is Map && body['says'] is String
        ? body['says'] as String
        : '$endpoint answered ${answer.status}';
    if (answer.status != 201 || body is! Map) {
      return TelemetrySent(did: false, says: says, receipt: null);
    }
    final run = body['run'];
    final key = body['eraseKey'];
    if (run is! num || key is! String) {
      return TelemetrySent(
        did: false,
        says: '$endpoint took the run and gave no receipt for it',
        receipt: null,
      );
    }
    return TelemetrySent(
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
      return TelemetrySent(did: false, says: prepared.says, receipt: null);
    }
    return sink.deliver(upload);
  }
}
