/// What `git` says about the tree the release is being prepared in.
library;

import 'dart:io';

import 'model.dart';
import 'shell.dart';

Future<String> _git(Directory root, List<String> args) async {
  final ran = await runCommand(
    <String>['git', ...args],
    workingDirectory: root.path,
    timeout: const Duration(seconds: 20),
  );
  return ran.ok ? ran.lines.join('\n').trim() : '';
}

/// The current branch, its commit, how dirty it is and how far it has run
/// ahead of `main`.
///
/// [mustHave] names the branches whose work belongs in this one, each answered
/// with whether it is an ancestor of `HEAD`: a merge is the only thing that
/// makes it true, and a cherry-pick of the same work does not.
///
/// **The fingerprint covers what is modified and when**, not only the commit.
/// The gates run against the working tree, and an edit that is not committed
/// yet changes their answer as much as one that is.
Future<GitSnapshot> readGit(
  Directory root, {
  List<String> mustHave = const <String>[],
}) async {
  final branch = await _git(root, <String>[
    'rev-parse',
    '--abbrev-ref',
    'HEAD',
  ]);
  final head = await _git(root, <String>['rev-parse', '--short', 'HEAD']);
  final subject = await _git(root, <String>['log', '-1', '--format=%s']);
  final status = await _git(root, <String>['status', '--porcelain']);
  final ahead = await _git(root, <String>['rev-list', '--count', 'main..HEAD']);
  final tags = await _git(root, <String>['tag', '--list', 'v*']);

  final changed = status.isEmpty ? const <String>[] : status.split('\n');
  final stamps = StringBuffer();
  for (final line in changed) {
    // "XY path", or "XY old -> new" for a rename: the last word is where the
    // file is now.
    final path = line.length > 3 ? line.substring(3).split(' -> ').last : '';
    final file = File('${root.path}/$path');
    if (file.existsSync()) {
      stamps.write('$path:${file.lastModifiedSync().millisecondsSinceEpoch};');
    }
  }

  final integrated = <String, bool>{};
  for (final other in mustHave) {
    final exists = await _git(root, <String>['rev-parse', '--verify', other]);
    if (exists.isEmpty) {
      integrated[other] = false;
      continue;
    }
    final ran = await runCommand(
      <String>['git', 'merge-base', '--is-ancestor', other, 'HEAD'],
      workingDirectory: root.path,
      timeout: const Duration(seconds: 20),
    );
    integrated[other] = ran.exitCode == 0;
  }

  return GitSnapshot(
    branch: branch,
    head: head,
    subject: subject,
    dirtyCount: changed.length,
    aheadOfMain: int.tryParse(ahead) ?? 0,
    tags: tags.isEmpty ? const <String>[] : tags.split('\n'),
    integrated: integrated,
    fingerprint: '$head|$status|${stamps.toString().hashCode}',
  );
}

/// The worktrees other agents are working in, with how far each has got.
///
/// Only those under `.claude/worktrees/agent-`, and never the current one. A
/// branch is worth a row when it has commits the current one lacks or files it
/// has not committed; a worktree with neither has nothing to report.
Future<List<AgentWorktree>> readAgents(Directory root, String current) async {
  final listing = await _git(root, <String>['worktree', 'list', '--porcelain']);
  if (listing.isEmpty) return const <AgentWorktree>[];

  final agents = <AgentWorktree>[];
  for (final block in listing.split('\n\n')) {
    String? path;
    String? branch;
    var locked = false;
    for (final line in block.split('\n')) {
      if (line.startsWith('worktree ')) path = line.substring(9);
      if (line.startsWith('branch refs/heads/')) {
        branch = line.substring('branch refs/heads/'.length);
      }
      if (line.startsWith('locked')) locked = true;
    }
    if (path == null || branch == null) continue;
    if (!path.contains('/.claude/worktrees/agent-')) continue;
    if (branch == current) continue;

    final ahead =
        int.tryParse(
          await _git(root, <String>[
            'rev-list',
            '--count',
            '$current..$branch',
          ]),
        ) ??
        0;
    final dirty = (await _git(Directory(path), <String>[
      'status',
      '--porcelain',
    ])).split('\n').where((String l) => l.isNotEmpty).length;
    if (ahead == 0 && dirty == 0) continue;

    agents.add(
      AgentWorktree(
        name: path.split('/').last,
        branch: branch,
        ahead: ahead,
        dirty: dirty,
        subject: await _git(root, <String>['log', '-1', '--format=%s', branch]),
        locked: locked,
      ),
    );
  }
  return agents;
}
