import 'dart:convert';
import 'dart:io';

import 'playtest_report.dart';

/// One GET: a status and a body. Handed in so a test needs no server.
typedef TextGet = Future<({int status, String body})> Function(Uri url);

/// N7: the heatmap a telemetry server binned from players' runs of one level,
/// as the same [PlaytestReport] `ai-01`'s playtests are read into.
///
/// **The level goes by its digest, not its path.** Runs are kept against the
/// document they were played in, so a level edited since has a heatmap of its
/// own — empty until somebody plays it — rather than one drawn from geometry
/// that is no longer there.
Future<({PlaytestReport? report, String says})> fetchTelemetryHeatmap({
  required Uri server,
  required String levelHash,
  double cellSize = 1.0,
  TextGet get = getText,
}) async {
  final url = server.resolve(
    '/api/telemetry/heatmap?level=${Uri.encodeQueryComponent(levelHash)}'
    '&cell=$cellSize',
  );
  final ({int status, String body}) answer;
  try {
    answer = await get(url);
  } catch (error) {
    return (report: null, says: 'could not reach $server: $error');
  }
  final Object? json;
  try {
    json = jsonDecode(answer.body);
  } on FormatException {
    return (report: null, says: '$url answered ${answer.status}, not JSON');
  }
  if (json is! Map<String, Object?>) {
    return (report: null, says: '$url answered ${answer.status}, not a map');
  }
  final says = json['says'] is String
      ? json['says']! as String
      : 'answered ${answer.status}';
  if (answer.status != 200) return (report: null, says: says);
  try {
    final report = PlaytestReport.fromJson(json);
    return (
      report: report,
      says: report.totalRuns == 0
          ? 'nobody has sent a run of this level yet'
          : says,
    );
  } catch (error) {
    return (report: null, says: '$url sent a heatmap this cannot read: $error');
  }
}

/// [TextGet] over `dart:io`.
Future<({int status, String body})> getText(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await response.transform(utf8.decoder).join(),
    );
  } finally {
    client.close();
  }
}
