/// The things that are not on this machine: pub.dev, the two hosted sites and
/// CI. Every request here is a read.
///
/// **Each of these can fail, and each failure is an answer.** The page must not
/// go quiet when the network does, so every function returns a snapshot with an
/// `error` rather than throwing, and the checklist shows that as unknown, not
/// as passed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'shell.dart';

/// Fetches a URL's body, or null when it answered with anything but 200.
typedef Fetch = Future<String?> Function(Uri uri);

/// The real [Fetch], with a timeout short enough that a dead network shows up as
/// a page that says so within a poll or two.
Future<String?> httpFetch(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'release-dashboard';
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 10));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// What pub.dev has for [names], and whether each of [discontinuedNames] has
/// been marked discontinued.
///
/// A name pub.dev does not have is null in `latest`, which is a fact about the
/// name, and different from the request failing, which is `error`.
Future<PubDevSnapshot> readPubDev(
  Fetch fetch, {
  required List<String> names,
  required List<String> discontinuedNames,
}) async {
  final latest = <String, String?>{};
  final discontinued = <String, bool>{};
  Object? failure;

  Future<void> one(String name, {required bool wantsDiscontinued}) async {
    try {
      final body = await fetch(Uri.parse('https://pub.dev/api/packages/$name'));
      if (body == null) {
        latest[name] = null;
        if (wantsDiscontinued) discontinued[name] = false;
        return;
      }
      final json = jsonDecode(body) as Map<String, Object?>;
      latest[name] =
          (json['latest'] as Map<String, Object?>?)?['version'] as String?;
      if (wantsDiscontinued) {
        discontinued[name] = json['isDiscontinued'] == true;
      }
    } on Object catch (error) {
      failure ??= error;
    }
  }

  // Six at a time: 40 requests, and pub.dev is somebody else's server.
  final queue = <(String, bool)>[
    for (final name in names) (name, false),
    for (final name in discontinuedNames) (name, true),
  ];
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final (name, wants) = queue.removeLast();
      await one(name, wantsDiscontinued: wants);
    }
  }

  await Future.wait(<Future<void>>[for (var i = 0; i < 6; i++) worker()]);

  return PubDevSnapshot(
    latest: latest,
    discontinued: discontinued,
    fetchedAt: DateTime.now(),
    error: failure == null ? null : 'pub.dev did not answer: $failure',
  );
}

/// Whether the modeller's server is up, and how many tutorial cases it lists.
Future<SitesSnapshot> readSites(Fetch fetch, {required String origin}) async {
  try {
    final health = await fetch(Uri.parse('$origin/health'));
    final learn = await fetch(Uri.parse('$origin/learn/modeler/'));
    final cases = learn == null
        ? null
        : RegExp(r'href="/learn/modeler/\d\d-').allMatches(learn).length;
    return SitesSnapshot(
      healthy: health?.trim() == 'ok',
      learnCases: cases,
      fetchedAt: DateTime.now(),
    );
  } on Object catch (error) {
    return SitesSnapshot(
      healthy: null,
      learnCases: null,
      fetchedAt: DateTime.now(),
      error: '$origin did not answer: $error',
    );
  }
}

/// Whether the remote has [branch], and what CI made of its newest commit.
///
/// `git ls-remote` answers the first and `gh` the second, so a machine with git
/// and no `gh` still learns whether the branch has been pushed.
Future<CiSnapshot> readCi(Directory root, String branch) async {
  final listed = await runCommand(
    <String>['git', 'ls-remote', '--heads', 'origin', branch],
    workingDirectory: root.path,
    timeout: const Duration(seconds: 25),
  );
  if (!listed.ok) {
    return CiSnapshot(
      pushed: null,
      headSha: null,
      runSha: null,
      state: 'unknown',
      jobs: const <CiJob>[],
      url: null,
      fetchedAt: DateTime.now(),
      error: 'git ls-remote failed: ${listed.tail(1).firstOrNull ?? ''}',
    );
  }
  final line = listed.lines
      .where((String l) => l.trim().isNotEmpty)
      .firstOrNull;
  if (line == null) {
    return CiSnapshot(
      pushed: false,
      headSha: null,
      runSha: null,
      state: 'none',
      jobs: const <CiJob>[],
      url: null,
      fetchedAt: DateTime.now(),
    );
  }
  final remoteSha = line.split(RegExp(r'\s')).first;

  final runs = await runCommand(
    <String>[
      'gh',
      'run',
      'list',
      '--branch',
      branch,
      '--limit',
      '1',
      '--json',
      'databaseId,status,conclusion,headSha,url',
    ],
    workingDirectory: root.path,
    timeout: const Duration(seconds: 25),
  );
  if (!runs.ok) {
    return CiSnapshot(
      pushed: true,
      headSha: remoteSha,
      runSha: null,
      state: 'unknown',
      jobs: const <CiJob>[],
      url: null,
      fetchedAt: DateTime.now(),
      error: 'gh could not list runs: ${runs.tail(1).firstOrNull ?? ''}',
    );
  }

  final decoded = jsonDecode(runs.text);
  if (decoded is! List || decoded.isEmpty) {
    return CiSnapshot(
      pushed: true,
      headSha: remoteSha,
      runSha: null,
      state: 'none',
      jobs: const <CiJob>[],
      url: null,
      fetchedAt: DateTime.now(),
    );
  }
  final run = decoded.first as Map<String, Object?>;
  final status = run['status'] as String? ?? '';
  final conclusion = run['conclusion'] as String? ?? '';

  final jobs = <CiJob>[];
  final viewed = await runCommand(
    <String>['gh', 'run', 'view', '${run['databaseId']}', '--json', 'jobs'],
    workingDirectory: root.path,
    timeout: const Duration(seconds: 25),
  );
  if (viewed.ok) {
    final view = jsonDecode(viewed.text) as Map<String, Object?>;
    for (final job in (view['jobs'] as List? ?? const <Object?>[])) {
      if (job is! Map<String, Object?>) continue;
      final map = job;
      final jobStatus = map['status'] as String? ?? '';
      jobs.add(
        CiJob(
          name: map['name'] as String? ?? '?',
          state: jobStatus == 'completed'
              ? (map['conclusion'] as String? ?? 'unknown')
              : jobStatus,
        ),
      );
    }
  }

  return CiSnapshot(
    pushed: true,
    headSha: remoteSha,
    runSha: run['headSha'] as String?,
    state: status == 'completed' ? conclusion : status,
    jobs: jobs,
    url: run['url'] as String?,
    fetchedAt: DateTime.now(),
  );
}
