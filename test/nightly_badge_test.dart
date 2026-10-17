/// `tool/nightly_badge.sh`: the nightly's runs, as `gh run list` prints
/// them, turned into the badge README shows; "stale" after 48 hours with no
/// run, because a badge that stays green when nothing ran is a green nobody
/// earned.
///
///     dart test test/nightly_badge_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// 2026-10-12T06:00:00Z, the clock the script reads as `NIGHTLY_NOW`.
const int _now = 1791784800;

String _at(int hoursAgo) => DateTime.fromMillisecondsSinceEpoch(
  (_now - hoursAgo * 3600) * 1000,
  isUtc: true,
).toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

Map<String, Object?> _run(int hoursAgo, String conclusion) => {
  'status': 'completed',
  'conclusion': conclusion,
  'createdAt': _at(hoursAgo),
  'updatedAt': _at(hoursAgo),
};

Future<Map<String, Object?>> _badge(List<Map<String, Object?>> runs) async {
  final process = await Process.start(
    'bash',
    <String>['tool/nightly_badge.sh'],
    environment: <String, String>{'NIGHTLY_NOW': '$_now'},
  );
  process.stdin.write(jsonEncode(runs));
  await process.stdin.close();
  final out = await process.stdout.transform(utf8.decoder).join();
  final err = await process.stderr.transform(utf8.decoder).join();
  expect(await process.exitCode, 0, reason: err);
  return jsonDecode(out) as Map<String, Object?>;
}

void main() {
  test('a green night last night is green, with the nights in a row', () async {
    final badge = await _badge([
      _run(6, 'success'),
      _run(30, 'success'),
      _run(54, 'success'),
      _run(78, 'failure'),
      _run(102, 'success'),
    ]);
    expect(badge['schemaVersion'], 1);
    expect(badge['label'], 'nightly');
    expect(badge['color'], 'brightgreen');
    // The tag waits for seven of these; the badge says how many there are.
    expect(badge['message'], 'passing, 3 nights in a row');
  });

  test('a red night is red whatever came before it', () async {
    final badge = await _badge([_run(6, 'failure'), _run(30, 'success')]);
    expect(badge['color'], 'red');
    expect(badge['message'], 'failing');
  });

  test('48 hours without a run is stale, whatever the last run said', () async {
    // Mutation: read the age from the last *successful* run rather than the
    // last run, or compare with 48 days, and this stays green.
    final badge = await _badge([_run(49, 'success'), _run(73, 'success')]);
    expect(badge['color'], 'orange');
    expect(badge['message'], 'stale, 49 h since the last run');
    final fresh = await _badge([_run(47, 'success')]);
    expect(fresh['color'], 'brightgreen');
  });

  test('a run still going says so, and is not counted as a night', () async {
    final badge = await _badge([
      {
        'status': 'in_progress',
        'conclusion': '',
        'createdAt': _at(1),
        'updatedAt': _at(1),
      },
      _run(25, 'success'),
    ]);
    expect(badge['color'], 'brightgreen');
    expect(badge['message'], 'passing, 1 night in a row');
  });

  test('no run at all is said plainly', () async {
    final badge = await _badge(const []);
    expect(badge['message'], 'never run');
    expect(badge['color'], 'lightgrey');
  });
}
