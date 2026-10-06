import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Demo,
        HttpTelemetrySink,
        JsonPost,
        TelemetryConsent,
        TelemetrySent,
        TelemetryUploader;
import 'package:http/http.dart' as http;

import '../screens/save_file.dart';
import 'http_cloud_saves.dart';
import 'save_sync.dart';

/// The two things a game asks before anything of the player's leaves the
/// device: may their run be kept in the cloud, and may the runs they play be
/// sent to see where levels are hard.
///
/// **Both no until answered, and kept apart.** Cloud saves are [SaveSync]'s
/// own document, so clearing a run never turns them off; telemetry is a
/// [TelemetryConsent] in a document of its own, so a reset of the controls
/// never turns it on. A game with no save server has no [sync], and its
/// cloud question says so rather than pretending to be off.
final class Consents {
  Consents({required this.storage, required this.policy, this.sync, this.now});

  /// Where the telemetry answer is kept.
  final Storage storage;

  /// The wording telemetry is asked under now — see
  /// [TelemetryConsent.allows]. A new wording asks again.
  final String policy;

  /// Cloud saves, or null when this build has no save server.
  final SaveSync? sync;

  /// The clock answers are stamped with; the wall's unless a test says.
  final DateTime Function()? now;

  /// The document the telemetry answer is kept in.
  static const String telemetryName = 'telemetry.json';

  /// Whether the run may be kept in the cloud. False with no [sync].
  bool get cloud => sync?.consented ?? false;

  /// Answers the cloud question; whether the answer was kept. Turning it
  /// off forgets what the two copies last agreed on — see [SaveSync].
  bool answerCloud(bool yes) => switch (sync) {
    null => false,
    final SaveSync sync => yes ? sync.consent() : sync.withdraw(),
  };

  /// The telemetry answer as it stands.
  TelemetryConsent get telemetry {
    final text = storage.read(telemetryName);
    if (text == null) return const TelemetryConsent.notAsked();
    try {
      return TelemetryConsent.fromJson(jsonDecode(text));
    } on FormatException {
      return const TelemetryConsent.notAsked();
    }
  }

  /// Whether runs may be sent under today's [policy].
  bool get sendsRuns => telemetry.allows(policy);

  /// Answers the telemetry question under today's [policy]; whether the
  /// answer was kept.
  bool answerTelemetry(bool yes) {
    final at = (now ?? DateTime.now)().toUtc();
    final answer = yes
        ? TelemetryConsent.granted(policy: policy, at: at)
        : TelemetryConsent.declined(policy: policy, at: at);
    return storage.write(telemetryName, jsonEncode(answer.toJson()));
  }
}

/// [JsonPost] over [client]: what `HttpTelemetrySink` sends with, natively
/// and in a browser alike.
JsonPost httpJsonPost(http.Client client) => (Uri url, String json) async {
  final answer = await client.post(
    url,
    headers: const <String, String>{'content-type': 'application/json'},
    body: json,
  );
  return (status: answer.statusCode, body: answer.body);
};

/// Where this build's save and telemetry server is —
/// `--dart-define=FLUTTER3D_CLOUD=https://…` — or empty for none, which is
/// every build that does not say: nothing to send to, and the questions say
/// so.
const String cloudServer = String.fromEnvironment('FLUTTER3D_CLOUD');

/// The wording the telemetry question is asked under. Changed when what is
/// sent changes, which asks every player again — see [Consents.policy].
const String telemetryPolicy = '2026-10';

/// A game's questions and what answering yes turns on, from one server:
/// [Consents], the [SaveSync] its cloud question governs, and the
/// [TelemetryUploader] its other question does.
///
/// With no [server] both are still asked — a player can say no to
/// something a build cannot do yet — and neither sends anything.
final class GameCloud {
  factory GameCloud({
    required String game,
    required Storage storage,
    SaveFile? saves,
    String server = cloudServer,
    http.Client? client,
    String policy = telemetryPolicy,
  }) {
    final base = server.isEmpty ? null : Uri.parse(server);
    final http.Client? network = base == null ? null : client ?? http.Client();
    final sync = base == null || saves == null
        ? null
        : SaveSync(
            saves: saves,
            store: HttpCloudSaves(base: base, game: game, client: network),
            storage: storage,
          );
    final consents = Consents(storage: storage, policy: policy, sync: sync);
    return GameCloud._(
      consents,
      base == null
          ? null
          : TelemetryUploader(
              game: game,
              policy: policy,
              consent: () => consents.telemetry,
              sink: HttpTelemetrySink(
                endpoint: base.resolve('api/telemetry/runs'),
                post: httpJsonPost(network!),
              ),
            ),
    );
  }

  GameCloud._(this.consents, this.uploader);

  final Consents consents;

  /// What sends a finished run, or null with no server.
  final TelemetryUploader? uploader;

  /// Cloud saves, or null with no server or no save to keep.
  SaveSync? get sync => consents.sync;

  /// Sends [demo] if the player said runs may go; null when there is
  /// nowhere to send it. Never throws: a run that could not go is said in
  /// the answer.
  Future<TelemetrySent?> send(Demo demo) async => uploader?.send(demo);
}
