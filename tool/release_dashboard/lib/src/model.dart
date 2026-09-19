/// What the dashboard knows, as plain values.
///
/// Everything here is a snapshot of something that was measured at a time and
/// can be wrong a second later, so none of it is mutable and all of it turns
/// into JSON without a codec: the browser is handed exactly what the checklist
/// was judged from.
library;

/// What a check says.
///
/// **`pending` and `unknown` are different, and the difference is the point of
/// having both.** Pending is a fact: the thing has not happened, and cannot
/// yet, such as a tag for a release that has not been published. Unknown is the
/// dashboard's own ignorance: the check has not run, or its source did not
/// answer. A page that showed both as grey would say "nothing to worry about"
/// about a network that was down.
enum Level { pass, fail, running, pending, unknown }

/// One row of the release checklist.
final class CheckItem {
  const CheckItem({
    required this.id,
    required this.title,
    required this.level,
    this.detail = '',
  });

  final String id;
  final String title;
  final Level level;

  /// One line, in words, of what was found. Never empty for a red row.
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'level': level.name,
    'detail': detail,
  };
}

/// A group of [CheckItem]s that belong to one part of the work.
final class Stage {
  const Stage({required this.id, required this.title, required this.items});

  final String id;
  final String title;
  final List<CheckItem> items;

  int count(Level level) =>
      items.where((CheckItem item) => item.level == level).length;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'items': <Object?>[for (final CheckItem item in items) item.toJson()],
  };
}

/// The outcome of one run of a script the repository already has.
final class GateResult {
  const GateResult({
    required this.level,
    required this.summary,
    this.brokenRules = const <String>[],
    this.tail = const <String>[],
    this.ranAt,
    this.duration,
    this.fingerprint,
  });

  /// A gate nobody has run yet.
  const GateResult.unrun()
    : level = Level.unknown,
      summary = 'not run yet',
      brokenRules = const <String>[],
      tail = const <String>[],
      ranAt = null,
      duration = null,
      fingerprint = null;

  final Level level;
  final String summary;

  /// For `tool/structure.dart` only: the rules that were red, by name.
  final List<String> brokenRules;

  /// The last lines the script printed, for somebody who has to see why.
  final List<String> tail;
  final DateTime? ranAt;
  final Duration? duration;

  /// The state of the tree this ran against, so the page can say a result is
  /// from before the last edit rather than showing it as current.
  final String? fingerprint;

  GateResult copyWith({Level? level, String? summary}) => GateResult(
    level: level ?? this.level,
    summary: summary ?? this.summary,
    brokenRules: brokenRules,
    tail: tail,
    ranAt: ranAt,
    duration: duration,
    fingerprint: fingerprint,
  );
}

/// One package of the workspace, read from its own files.
final class PackageRow {
  const PackageRow({
    required this.name,
    required this.version,
    required this.changelogTop,
    required this.ownLine,
    required this.problems,
  });

  final String name;
  final String version;

  /// The first `## ` heading of `CHANGELOG.md`, or empty when there is none.
  final String changelogTop;

  /// Whether this package keeps a number of its own instead of the shelf's.
  final bool ownLine;

  /// Sentences, each one a reason this package will not publish as it stands.
  final List<String> problems;
}

/// What the `packages/` directory holds.
final class PackagesSnapshot {
  const PackagesSnapshot({
    required this.rows,
    required this.ghostDirectories,
    required this.release,
  });

  final List<PackageRow> rows;

  /// Directories under `packages/` with no `pubspec.yaml`: what is left after a
  /// package is folded into another and its build output stays behind. They
  /// are not in git, and `tool/publish_check.sh` walks `packages/*/`.
  final List<String> ghostDirectories;

  /// The version the shelf is meant to carry.
  final String release;

  List<PackageRow> get shelf =>
      rows.where((PackageRow row) => !row.ownLine).toList();
}

/// The repository, as `git` sees it.
final class GitSnapshot {
  const GitSnapshot({
    required this.branch,
    required this.head,
    required this.subject,
    required this.dirtyCount,
    required this.aheadOfMain,
    required this.tags,
    required this.integrated,
    required this.fingerprint,
  });

  final String branch;
  final String head;
  final String subject;
  final int dirtyCount;
  final int aheadOfMain;
  final List<String> tags;

  /// Branches whose work the release needs, and whether each is an ancestor of
  /// the current one.
  final Map<String, bool> integrated;

  /// Changes whenever the tree does: the commit, what is modified, and when.
  final String fingerprint;
}

/// A branch somebody else is working on in a worktree of its own.
final class AgentWorktree {
  const AgentWorktree({
    required this.name,
    required this.branch,
    required this.ahead,
    required this.dirty,
    required this.subject,
    required this.locked,
  });

  final String name;
  final String branch;
  final int ahead;
  final int dirty;
  final String subject;
  final bool locked;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'branch': branch,
    'ahead': ahead,
    'dirty': dirty,
    'subject': subject,
    'locked': locked,
  };
}

/// The plan's own account of itself.
final class PlanSnapshot {
  const PlanSnapshot({
    required this.total,
    required this.done,
    required this.partial,
    required this.rows,
  });

  const PlanSnapshot.empty()
    : total = 0,
      done = 0,
      partial = 0,
      rows = const <String, String>{};

  final int total;
  final int done;
  final int partial;

  /// Every row id the plan names, mapped to `done`, `partial` or `todo`.
  final Map<String, String> rows;

  int get todo => total - done - partial;

  String statusOf(String id) => rows[id] ?? 'todo';
}

/// What pub.dev says about the packages, or that it could not be asked.
final class PubDevSnapshot {
  const PubDevSnapshot({
    required this.latest,
    required this.discontinued,
    required this.fetchedAt,
    this.error,
  });

  const PubDevSnapshot.unknown()
    : latest = const <String, String?>{},
      discontinued = const <String, bool>{},
      fetchedAt = null,
      error = 'not asked yet';

  /// The newest version of each name, or null where pub.dev has no such
  /// package.
  final Map<String, String?> latest;
  final Map<String, bool> discontinued;
  final DateTime? fetchedAt;
  final String? error;

  bool get known => fetchedAt != null && error == null;
}

/// The two sites the modeller is published to.
final class SitesSnapshot {
  const SitesSnapshot({
    required this.healthy,
    required this.learnCases,
    required this.fetchedAt,
    this.error,
  });

  const SitesSnapshot.unknown()
    : healthy = null,
      learnCases = null,
      fetchedAt = null,
      error = 'not asked yet';

  final bool? healthy;
  final int? learnCases;
  final DateTime? fetchedAt;
  final String? error;
}

/// One job of a CI run.
final class CiJob {
  const CiJob({required this.name, required this.state});

  final String name;

  /// `success`, `failure`, `in_progress`, `queued` or `skipped`.
  final String state;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'state': state,
  };
}

/// The latest CI run for the branch, or the reason there is none.
final class CiSnapshot {
  const CiSnapshot({
    required this.pushed,
    required this.headSha,
    required this.runSha,
    required this.state,
    required this.jobs,
    required this.url,
    required this.fetchedAt,
    this.error,
  });

  const CiSnapshot.unknown()
    : pushed = null,
      headSha = null,
      runSha = null,
      state = 'unknown',
      jobs = const <CiJob>[],
      url = null,
      fetchedAt = null,
      error = 'not asked yet';

  /// Whether the remote has this branch at all. Null when it was not asked.
  final bool? pushed;

  /// The commit the remote has for the branch.
  final String? headSha;

  /// The commit the latest run was for.
  final String? runSha;

  /// `success`, `failure`, `in_progress`, `queued`, `none` or `unknown`.
  final String state;
  final List<CiJob> jobs;
  final String? url;
  final DateTime? fetchedAt;
  final String? error;
}

/// The result of one look at a file, kept so the checklist stays a function of
/// its inputs.
final class ProbeResult {
  const ProbeResult({required this.ok, this.detail = ''});

  final bool ok;
  final String detail;
}

/// Everything the checklist is judged from, taken at one moment.
final class Snapshots {
  const Snapshots({
    required this.git,
    required this.packages,
    required this.plan,
    required this.probes,
    required this.gates,
    required this.pubdev,
    required this.sites,
    required this.ci,
  });

  final GitSnapshot? git;
  final PackagesSnapshot? packages;
  final PlanSnapshot plan;
  final Map<String, ProbeResult> probes;
  final Map<String, GateResult> gates;
  final PubDevSnapshot pubdev;
  final SitesSnapshot sites;
  final CiSnapshot ci;

  GateResult gate(String id) => gates[id] ?? const GateResult.unrun();
}
