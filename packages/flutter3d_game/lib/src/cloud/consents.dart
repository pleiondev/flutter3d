import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart'
    show Storage, StorageException;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Demo,
        HttpTelemetrySink,
        JsonPost,
        RunRequest,
        RunResponse,
        RunService,
        RunTransport,
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
  /// The answers kept in [storage], read straight away — see [ready]. Until
  /// they are read, both questions read as not answered, which is no.
  Consents({required this.storage, required this.policy, this.sync, this.now}) {
    _ready = _load();
  }

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

  /// The version of the telemetry answer's document.
  static const int telemetryVersion = 1;

  /// The telemetry answer's document: `f3d.telemetryConsent`, then the
  /// keys of [TelemetryConsent.toJson]. A document from before the envelope
  /// reads as version 1; one from a newer build, or one that does not read,
  /// is not asked — never a grant.
  static const FormatSpec telemetryFormat = FormatSpec(
    id: 'f3d.telemetryConsent',
    version: telemetryVersion,
    fixture: 'test/fixtures/v<N>/telemetry.json',
  );

  late final Future<void> _ready;

  /// Completes once both answers have been read from [storage]. A screen
  /// that shows them rebuilds when it does; a game that sends a run before
  /// asking waits for it.
  Future<void> get ready => _ready;

  TelemetryConsent _telemetry = const TelemetryConsent.notAsked();

  Future<void> _load() async {
    final text = await storage.read(telemetryName);
    if (text != null) {
      try {
        _telemetry = switch (jsonDecode(text)) {
          final Map<String, Object?> json => TelemetryConsent.fromJson(
            telemetryFormat.open(json, refuse: DocumentFormatException.new),
          ),
          _ => const TelemetryConsent.notAsked(),
        };
      } on FormatException {
        _telemetry = const TelemetryConsent.notAsked();
      } on DocumentFormatException {
        _telemetry = const TelemetryConsent.notAsked();
      }
    }
    await sync?.ready;
  }

  /// Whether the run may be kept in the cloud. False with no [sync].
  bool get hasCloudConsent => sync?.hasConsent ?? false;

  /// Answers the cloud question; whether the answer was kept. Turning it
  /// off forgets what the two copies last agreed on — see [SaveSync].
  Future<bool> answerCloud({required bool granted}) async => switch (sync) {
    null => false,
    final SaveSync sync =>
      granted ? await sync.consent() : await sync.withdraw(),
  };

  /// The telemetry answer as it stands.
  TelemetryConsent get telemetry => _telemetry;

  /// Whether runs may be sent under today's [policy].
  bool get sendsRuns => telemetry.allows(policy);

  /// Answers the telemetry question under today's [policy]; whether the
  /// answer was kept. The answer holds for this session either way.
  Future<bool> answerTelemetry({required bool granted}) async {
    final at = (now ?? DateTime.now)().toUtc();
    final answer = granted
        ? TelemetryConsent.granted(policy: policy, at: at)
        : TelemetryConsent.declined(policy: policy, at: at);
    _telemetry = answer;
    try {
      await storage.write(
        telemetryName,
        jsonEncode(<String, Object?>{
          ...telemetryFormat.envelope(),
          ...answer.toJson(),
        }),
      );
      return true;
    } on StorageException {
      return false;
    }
  }
}

/// [RunTransport] over [client]: what [RunService] speaks to a share server
/// with.
RunTransport httpRunTransport(http.Client client) =>
    (RunRequest request) async {
      final answer = await client.send(
        http.Request(request.method, request.uri)
          ..headers['content-type'] = 'application/json'
          ..body = request.body ?? '',
      );
      return RunResponse(
        answer.statusCode,
        await answer.stream.bytesToString(),
      );
    };

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

/// A game's questions and what answering yes turns on, from one server:
/// [Consents], the [SaveSync] its cloud question governs, and the
/// [TelemetryUploader] its other question does.
///
/// With no [server] both are still asked — a player can say no to
/// something a build cannot do yet — and neither sends anything.
///
/// **The server and the wording are the game's to say.** They were
/// constants of this package, the server read from a `--dart-define` and
/// the wording a date — so every game on the engine shared one environment
/// variable and one policy date, and a game whose privacy text changed had
/// to wait for an engine release to ask its players again. A game that
/// wants a define reads it itself:
///
/// ```dart
/// GameCloud(
///   game: 'crypt',
///   storage: storage,
///   server: const String.fromEnvironment('MY_GAME_CLOUD'),
///   policy: '2026-10',
/// );
/// ```
final class GameCloud {
  /// [server] is the base URL, or null or empty for none. [policy] names the
  /// wording the telemetry question is asked under; change it when what is
  /// sent changes, which asks every player again — see [Consents.policy].
  factory GameCloud({
    required String game,
    required Storage storage,
    required String policy,
    SaveFile? saves,
    String? server,
    http.Client? client,
  }) {
    final base = (server == null || server.isEmpty) ? null : Uri.parse(server);
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
          : RunService(
              base: base.resolve('api/'),
              transport: httpRunTransport(network!),
            ),
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

  GameCloud._(this.consents, this.shares, this.uploader);

  final Consents consents;

  /// Where a run is shared and a shared one opened by its code, or null
  /// with no server. No question guards it: pressing Share is the yes.
  final RunService? shares;

  /// What sends a finished run, or null with no server.
  final TelemetryUploader? uploader;

  /// Cloud saves, or null with no server or no save to keep.
  SaveSync? get sync => consents.sync;

  /// Sends [demo] if the player said runs may go; null when there is
  /// nowhere to send it. Never throws: a run that could not go is said in
  /// the answer.
  Future<TelemetrySent?> send(Demo demo) async => uploader?.send(demo);
}
