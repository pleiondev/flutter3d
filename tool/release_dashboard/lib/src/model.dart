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
enum Level {
  /// The check holds.
  pass,

  /// The check found something wrong; the row's detail says what.
  fail,

  /// The check is running now.
  running,

  /// The thing checked has not happened yet and cannot yet.
  pending,

  /// The dashboard does not know: the check has not run, or its source did
  /// not answer.
  unknown,
}

/// One row of the release checklist.
final class CheckItem {
  /// A row [id] titled [title] at [level], with [detail] empty unless given.
  const CheckItem({
    required this.id,
    required this.title,
    required this.level,
    this.detail = '',
  });

  /// The row's stable id, which the plan's status and the page refer to.
  final String id;

  /// What the row checks, in words, as the page shows it.
  final String title;

  /// What the check says.
  final Level level;

  /// One line, in words, of what was found. Never empty for a red row.
  final String detail;

  /// The row as the page reads it, with [level] by name.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'level': level.name,
    'detail': detail,
  };
}

/// A group of [CheckItem]s that belong to one part of the work.
final class Stage {
  /// A stage [id] titled [title] holding [items].
  const Stage({required this.id, required this.title, required this.items});

  /// The stage's stable id.
  final String id;

  /// The stage's heading on the page.
  final String title;

  /// The stage's rows, in the order the page lists them.
  final List<CheckItem> items;

  /// How many of [items] are at [level].
  int count(Level level) =>
      items.where((CheckItem item) => item.level == level).length;

  /// The stage and its rows as the page reads them.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'items': <Object?>[for (final CheckItem item in items) item.toJson()],
  };
}

/// The outcome of one run of a script the repository already has.
final class GateResult {
  /// A result at [level] saying [summary]; the rest are empty unless given.
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

  /// Reads what [toJson] wrote. A file that says something else is not an
  /// error: the gate is simply reported as not run, and runs again.
  static GateResult? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final level = Level.values.asNameMap()[json['level']];
    final summary = json['summary'];
    if (level == null || summary is! String) return null;
    final ranAt = json['ranAt'];
    final seconds = json['seconds'];
    return GateResult(
      level: level,
      summary: summary,
      brokenRules: <String>[
        for (final rule in json['brokenRules'] as List<Object?>? ?? const [])
          '$rule',
      ],
      tail: <String>[
        for (final line in json['tail'] as List<Object?>? ?? const []) '$line',
      ],
      ranAt: ranAt is String ? DateTime.tryParse(ranAt) : null,
      duration: seconds is int ? Duration(seconds: seconds) : null,
      fingerprint: json['fingerprint'] as String?,
    );
  }

  /// The result as [fromJson] reads it back, with [duration] in whole seconds.
  Map<String, Object?> toJson() => <String, Object?>{
    'level': level.name,
    'summary': summary,
    'brokenRules': brokenRules,
    'tail': tail,
    'ranAt': ranAt?.toIso8601String(),
    'seconds': duration?.inSeconds,
    'fingerprint': fingerprint,
  };

  /// What the gate's run says.
  final Level level;

  /// One line, in words, of how the run went.
  final String summary;

  /// For `tool/structure.dart` only: the rules that were red, by name.
  final List<String> brokenRules;

  /// The last lines the script printed, for somebody who has to see why.
  final List<String> tail;

  /// When the run finished; null for a gate never run.
  final DateTime? ranAt;

  /// How long the run took, to the second; null for a gate never run.
  final Duration? duration;

  /// The state of the tree this ran against, so the page can say a result is
  /// from before the last edit rather than showing it as current.
  final String? fingerprint;

  /// This result with [level] or [summary] replaced and everything else kept:
  /// the rules, the tail, the time and the fingerprint of the run it reports.
  // ignore: avoid-incomplete-copy-with, the rest describe the run and are never edited
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
  /// A row for the package [name] at [version].
  const PackageRow({
    required this.name,
    required this.version,
    required this.changelogTop,
    required this.ownLine,
    required this.problems,
  });

  /// The package's name, from its pubspec.
  final String name;

  /// The version its pubspec says.
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
  /// What `packages/` held when it was read.
  const PackagesSnapshot({
    required this.rows,
    required this.ghostDirectories,
    required this.release,
  });

  /// One row per package with a pubspec.
  final List<PackageRow> rows;

  /// Directories under `packages/` with no `pubspec.yaml`: what is left after a
  /// package is folded into another and its build output stays behind. They
  /// are not in git, and `tool/publish_check.sh` walks `packages/*/`.
  final List<String> ghostDirectories;

  /// The version the shelf is meant to carry.
  final String release;

  /// The packages that carry the shelf's number rather than one of their own.
  List<PackageRow> get shelf =>
      rows.where((PackageRow row) => !row.ownLine).toList();
}

/// The repository, as `git` sees it.
final class GitSnapshot {
  /// The repository as `git` answered at one moment.
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

  /// The checked-out branch, from `git rev-parse --abbrev-ref HEAD`.
  final String branch;

  /// The short hash of `HEAD`.
  final String head;

  /// The subject line of `HEAD`'s commit.
  final String subject;

  /// How many paths `git status --porcelain` lists as changed.
  final int dirtyCount;

  /// How many commits `HEAD` has that `main` does not.
  final int aheadOfMain;

  /// Every tag starting with `v`, in `git tag`'s order.
  final List<String> tags;

  /// Branches whose work the release needs, and whether each is an ancestor of
  /// the current one.
  final Map<String, bool> integrated;

  /// Changes whenever the tree does: the commit, what is modified, and when.
  final String fingerprint;
}

/// A branch somebody else is working on in a worktree of its own.
final class AgentWorktree {
  /// An agent's worktree [name] on [branch].
  const AgentWorktree({
    required this.name,
    required this.branch,
    required this.ahead,
    required this.dirty,
    required this.subject,
    required this.locked,
  });

  /// The worktree's directory name under `.claude/worktrees/`.
  final String name;

  /// The branch the worktree has checked out.
  final String branch;

  /// How many commits [branch] has that the current branch does not.
  final int ahead;

  /// How many paths in the worktree are changed and not committed.
  final int dirty;

  /// The subject line of [branch]'s last commit.
  final String subject;

  /// Whether `git worktree list` reports the worktree locked.
  final bool locked;

  /// The worktree as the page reads it.
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
  /// The plan's counts and its rows' statuses.
  const PlanSnapshot({
    required this.total,
    required this.done,
    required this.partial,
    required this.rows,
  });

  /// A plan with no rows, for a tree without one.
  const PlanSnapshot.empty()
    : total = 0,
      done = 0,
      partial = 0,
      rows = const <String, String>{};

  /// How many rows the plan has.
  final int total;

  /// How many rows are done.
  final int done;

  /// How many rows are partly done.
  final int partial;

  /// Every row id the plan names, mapped to `done`, `partial` or `todo`.
  final Map<String, String> rows;

  /// How many rows are neither done nor partly done.
  int get todo => total - done - partial;

  /// Row [id]'s status: `done`, `partial` or `todo`, which is also the answer
  /// for an id the plan does not name.
  String statusOf(String id) => rows[id] ?? 'todo';
}

/// What pub.dev says about the packages, or that it could not be asked.
final class PubDevSnapshot {
  /// What pub.dev answered at [fetchedAt]; [error] is null when it answered.
  const PubDevSnapshot({
    required this.latest,
    required this.discontinued,
    required this.fetchedAt,
    this.error,
  });

  /// Before pub.dev has been asked.
  const PubDevSnapshot.unknown()
    : latest = const <String, String?>{},
      discontinued = const <String, bool>{},
      fetchedAt = null,
      error = 'not asked yet';

  /// The newest version of each name, or null where pub.dev has no such
  /// package.
  final Map<String, String?> latest;

  /// For each name asked about, whether pub.dev marks it discontinued.
  final Map<String, bool> discontinued;

  /// When pub.dev was asked; null before it has been.
  final DateTime? fetchedAt;

  /// Why pub.dev's answer is missing, or null when it answered.
  final String? error;

  /// Whether pub.dev was asked and answered.
  bool get known => fetchedAt != null && error == null;
}

/// The two sites the modeller is published to.
final class SitesSnapshot {
  /// What the modeller's server answered at [fetchedAt].
  const SitesSnapshot({
    required this.healthy,
    required this.learnCases,
    required this.fetchedAt,
    this.error,
  });

  /// Before the server has been asked.
  const SitesSnapshot.unknown()
    : healthy = null,
      learnCases = null,
      fetchedAt = null,
      error = 'not asked yet';

  /// Whether `/health` answered `ok`; null when the server did not answer.
  final bool? healthy;

  /// How many tutorial cases `/learn/modeler/` links to; null when the page
  /// did not answer.
  final int? learnCases;

  /// When the server was asked; null before it has been.
  final DateTime? fetchedAt;

  /// Why the server's answer is missing, or null when it answered.
  final String? error;
}

/// One job of a CI run.
final class CiJob {
  /// A job [name] in [state].
  const CiJob({required this.name, required this.state});

  /// The job's name in the workflow.
  final String name;

  /// `success`, `failure`, `in_progress`, `queued` or `skipped`.
  final String state;

  /// The job as the page reads it.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'state': state,
  };
}

/// The latest CI run for the branch, or the reason there is none.
final class CiSnapshot {
  /// The latest run as the CI host answered at [fetchedAt].
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

  /// Before the CI host has been asked.
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

  /// The run's jobs, in the order the host lists them.
  final List<CiJob> jobs;

  /// The run's page on the CI host; null with no run.
  final String? url;

  /// When the CI host was asked; null before it has been.
  final DateTime? fetchedAt;

  /// Why the CI answer is missing, or null when the host answered.
  final String? error;
}

/// The result of one look at a file, kept so the checklist stays a function of
/// its inputs.
final class ProbeResult {
  /// A probe that found [ok], saying [detail].
  const ProbeResult({required this.ok, this.detail = ''});

  /// Whether the file held what the probe looks for.
  final bool ok;

  /// What was found, in words; the path that is missing when one is.
  final String detail;
}

/// One set of showcase pages: a group of categories one worker writes at once.
final class ShowcaseSet {
  /// A set [id] with its counts.
  const ShowcaseSet({
    required this.id,
    required this.title,
    required this.categories,
    required this.expected,
    required this.pages,
    required this.catalogRows,
  });

  /// `a` to `i`, as `apps/flutter3d_showcase/coverage.md` names them.
  final String id;

  /// The set's name, as the coverage list gives it.
  final String title;

  /// The showcase categories the set's pages belong to.
  final List<String> categories;

  /// How many pages the coverage list says the set has.
  final int expected;

  /// Pages that have both their file and their guide.
  final int pages;

  /// Rows the set's catalog files hold. A page with no row would not be in the
  /// app, and a row with no page would not open, so the two are counted apart.
  final int catalogRows;
}

/// How far the showcase app has got, read from its files.
final class ShowcaseSnapshot {
  /// The showcase's sets and whether it is live.
  const ShowcaseSnapshot({
    required this.sets,
    required this.live,
    this.coverageFilled = false,
  });

  /// Nothing yet: the app does not exist in this tree.
  const ShowcaseSnapshot.absent()
    : sets = const <ShowcaseSet>[],
      live = null,
      coverageFilled = false;

  /// One entry per set the coverage list names.
  final List<ShowcaseSet> sets;

  /// Whether the 0.7.0 audit in `coverage.md` has been written out.
  final bool coverageFilled;

  /// Whether the published showcase answers; null when it was not asked or the
  /// host would not say (it is behind a login).
  final bool? live;

  /// This snapshot with [live] set to [answer].
  ShowcaseSnapshot withLive(bool? answer) => ShowcaseSnapshot(
    sets: sets,
    live: answer,
    coverageFilled: coverageFilled,
  );
}

/// Everything the checklist is judged from, taken at one moment.
final class Snapshots {
  /// Everything read for one judgement of the checklist.
  const Snapshots({
    required this.git,
    required this.packages,
    required this.plan,
    required this.probes,
    required this.gates,
    required this.pubdev,
    required this.sites,
    required this.ci,
    this.showcase = const ShowcaseSnapshot.absent(),
  });

  /// How far the showcase app has got.
  final ShowcaseSnapshot showcase;

  /// The repository; null when `git` could not be read.
  final GitSnapshot? git;

  /// The packages; null when `packages/` could not be read.
  final PackagesSnapshot? packages;

  /// The plan's account of itself.
  final PlanSnapshot plan;

  /// Each probe's result, by the probe's id.
  final Map<String, ProbeResult> probes;

  /// Each gate's last result, by the gate's id.
  final Map<String, GateResult> gates;

  /// What pub.dev says.
  final PubDevSnapshot pubdev;

  /// What the modeller's server says.
  final SitesSnapshot sites;

  /// What CI says about the branch.
  final CiSnapshot ci;

  /// Gate [id]'s last result, or [GateResult.unrun] when it has none.
  GateResult gate(String id) => gates[id] ?? const GateResult.unrun();
}
