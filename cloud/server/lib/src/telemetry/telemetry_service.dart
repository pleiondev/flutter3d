/// N7: runs players agreed to send, played again here, and the heatmap of
/// where they went.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'telemetry_store.dart';

/// Every outcome a stored run can have, counted even at zero.
const List<String> kTelemetryOutcomes = <String>['won', 'lost', 'unfinished'];

/// An answer: the status, and a JSON body whose `says` is a sentence.
typedef TelemetryAnswer = ({int status, Map<String, Object?> body});

TelemetryAnswer _say(int status, String says, [Map<String, Object?>? more]) =>
    (status: status, body: <String, Object?>{'says': says, ...?more});

/// What a replay in another isolate hands back: plain data, since a
/// [HeadlessRun] does not cross.
typedef _Replayed = ({
  String? refused,
  String outcome,
  int steps,
  List<(double, double)> trail,
});

/// The levels this server can play runs in, by [Level.digestHex], read from
/// every `*.json` in [directory].
///
/// A file that is not a level is skipped and named in the second half of the
/// answer, so a deploy with one broken file still takes runs for the rest and
/// the log says which one.
(Map<String, Level>, List<String>) readTelemetryLevels(String directory) {
  final folder = Directory(directory);
  if (!folder.existsSync()) {
    return (<String, Level>{}, <String>['no directory at $directory']);
  }
  final files =
      folder
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final read = <(Level?, String)>[for (final file in files) _readLevel(file)];
  return (
    <String, Level>{
      for (final level in read.map((entry) => entry.$1).nonNulls)
        level.digestHex: level,
    },
    <String>[
      for (final (level, problem) in read)
        if (level == null) problem,
    ],
  );
}

(Level?, String) _readLevel(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    return (Level.fromJson((json as Map).cast<String, Object?>()), file.path);
  } catch (error) {
    return (null, '${file.path} is not a level: $error');
  }
}

/// Takes runs, plays them again, keeps what they did, and bins it.
///
/// **The server proves nothing about a game it does not have.** [games] are
/// the [HeadlessGame]s this process can step; a run of any other game is
/// refused by name rather than stored unverified. A genre whose package needs
/// Flutter cannot be one of them under `dart run`, so which games a deploy
/// plays is decided where it is built.
final class TelemetryService {
  TelemetryService({
    required this.games,
    required this.levels,
    required this.store,
    this.maxSteps = 60 * 60 * 60,
    this.maxBodyBytes = 16 * 1024 * 1024,
    this.sampleEvery = 10,
    this.heatmapRuns = 2000,
    this.isolated = true,
    Random? random,
  }) : _random = random ?? Random.secure();

  final Map<String, HeadlessGame> games;
  final Map<String, Level> levels;
  final TelemetryStore store;

  /// The longest run replayed: an hour at sixty steps a second. A replay is
  /// this server's CPU, and a tape is cheap to make long.
  final int maxSteps;
  final int maxBodyBytes;
  final int sampleEvery;

  /// How many of a level's newest runs a heatmap bins.
  final int heatmapRuns;

  /// Whether a replay runs in an isolate of its own, so one long run does not
  /// hold every other request. Off in tests that hand in a game no isolate
  /// can be sent.
  final bool isolated;

  final Random _random;

  /// Whether this server can take any run at all.
  bool get takesRuns => games.isNotEmpty && levels.isNotEmpty;

  /// `POST /api/telemetry/runs`.
  Future<TelemetryAnswer> accept(String body) async {
    if (!takesRuns) {
      return _say(
        503,
        'this server takes no telemetry: it has '
        '${games.isEmpty ? 'no game' : 'no level'} to play runs in',
      );
    }
    if (body.length > maxBodyBytes) {
      return _say(413, 'a run is at most $maxBodyBytes bytes here');
    }
    final TelemetryUpload upload;
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) {
        return _say(400, 'an upload is a JSON object');
      }
      upload = TelemetryUpload.fromJson(json);
    } on FormatException catch (error) {
      return _say(400, 'not JSON: ${error.message}');
    } on TelemetryUploadFormatException catch (error) {
      return _say(400, error.message);
    }

    final demo = upload.demo;
    final game = games[upload.game];
    if (game == null) {
      return _say(
        422,
        'this server plays no ${upload.game}; it plays '
        '${games.keys.join(', ')}',
      );
    }
    final level = levels[demo.levelHash];
    if (level == null) {
      return _say(
        422,
        'this server has no level with hash ${demo.levelHash} '
        '(${demo.level}), so the run cannot be played again here',
      );
    }
    if (demo.steps > maxSteps) {
      return _say(
        413,
        'the run is ${demo.steps} steps and this server replays at most '
        '$maxSteps',
      );
    }

    final args = (game: game, level: level, demo: demo, every: sampleEvery);
    final replayed = isolated
        ? await Isolate.run(() => _replay(args))
        : _replay(args);
    if (replayed.refused case final refused?) {
      return _say(422, '$refused — nothing was kept');
    }

    final key = _eraseKey();
    final id = await store.add(
      TelemetryRunRow(
        game: upload.game,
        levelHash: demo.levelHash,
        level: demo.level,
        outcome: replayed.outcome,
        steps: replayed.steps,
        trail: replayed.trail,
        eraseKeySha256: _sha256(key),
        policy: upload.policy,
        consentedAt: upload.consentedAt,
      ),
    );
    return _say(
      201,
      'played ${replayed.steps} steps again and kept run $id '
      '(${replayed.outcome}); the input itself was not kept',
      <String, Object?>{'run': id, 'eraseKey': key},
    );
  }

  /// `DELETE /api/telemetry/runs/<id>` with the receipt's key.
  Future<TelemetryAnswer> erase(int id, String key) async =>
      await store.erase(id, _sha256(key))
      ? _say(200, 'run $id is deleted')
      : _say(404, 'no run $id with that key');

  /// `GET /api/telemetry/heatmap?level=<hash>&cell=<metres>`.
  Future<TelemetryAnswer> heatmap(String? levelHash, String? cell) async {
    if (levelHash == null || levelHash.isEmpty) {
      return _say(400, 'name the level: ?level=<its digest>');
    }
    final cellSize = double.tryParse(cell ?? '1') ?? 0.0;
    if (cellSize <= 0.0 || cellSize > 1000.0) {
      return _say(400, 'a cell is between 0 and 1000 metres, not "$cell"');
    }
    final trails = await store.trails(levelHash, limit: heatmapRuns);
    final map = Heatmap.bin(
      trails,
      cellSize: cellSize,
      outcomeNames: kTelemetryOutcomes,
    );
    return (
      status: 200,
      body: <String, Object?>{
        ...map.toJson(),
        'level': levelHash,
        'says': '${map.runs} runs of $levelHash',
      },
    );
  }

  String _eraseKey() => <String>[
    for (var i = 0; i < 24; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

String _sha256(String key) => sha256.convert(utf8.encode(key)).toString();

_Replayed _replay(
  ({HeadlessGame game, Level level, Demo demo, int every}) args,
) => switch (resimulate(
  game: args.game,
  level: args.level,
  demo: args.demo,
  sampleEvery: args.every,
)) {
  ResimulationLevelChanged(:final found, :final recorded) => _refused(
    'the level is $found here and the run says $recorded',
  ),
  ResimulationStartDiffers() => _refused(
    'a fresh run of the level does not start where this one started',
  ),
  ResimulationDiverged(:final divergence, :final agreedUntil) => _refused(
    'the replay parts from the run at step ${divergence.step} (agreed until '
    '$agreedUntil), so it is not the run that was played',
  ),
  ResimulationRetraced(:final outcome, :final steps, :final trail) => (
    refused: null,
    outcome: switch (outcome) {
      RunOutcome.won => 'won',
      RunOutcome.lost => 'lost',
      RunOutcome.playing => 'unfinished',
    },
    steps: steps,
    trail: trail,
  ),
};

_Replayed _refused(String why) =>
    (refused: why, outcome: '', steps: 0, trail: const <(double, double)>[]);
