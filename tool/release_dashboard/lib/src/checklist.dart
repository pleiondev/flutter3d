/// The release, as a list of questions with one answer each.
///
/// **A pure function of [Snapshots].** Everything the page says about the
/// release is decided here and nowhere else, from values that were measured
/// before this ran, so the whole judgement can be tested with a hand-made
/// snapshot and no repository.
///
/// The five stages follow the order the work goes in, and the last one is
/// meant to be mostly `pending` until the cohort has walked the tutorial: a
/// row that cannot be green yet says so in words instead of showing red.
library;

import 'gates.dart';
import 'model.dart';

/// What this particular release is called and made of.
final class ReleaseConfig {
  const ReleaseConfig({
    this.release = '0.7.0',
    this.tag = 'v0.7.0',
    this.tutorialCases = 7,
    this.cohortRow = 'rel-16',
    this.integrationBranches = const <String>['modeler'],
    this.ownLine = const <String>{
      'pad_input',
      'pointer_lock',
      'flutter3d_samples',
    },
    this.endedNames = const <String>[
      'flutter3d_backend',
      'flutter3d_bridge',
      'flutter3d_screens',
      'flutter3d_session',
    ],
  });

  final String release;
  final String tag;

  /// How many cases the modeller's tutorial has, so an index that lists fewer
  /// is a deploy that left some behind.
  final int tutorialCases;

  /// The plan row that holds publication back until people have walked the
  /// tutorial.
  final String cohortRow;

  /// Branches whose commits belong in the current one.
  final List<String> integrationBranches;

  /// Packages that keep a version of their own.
  final Set<String> ownLine;

  /// Published names with no code behind them, to be marked discontinued.
  final List<String> endedNames;
}

/// How far the checklist has got.
final class Progress {
  const Progress({
    required this.passed,
    required this.failed,
    required this.running,
    required this.pending,
    required this.unknown,
  });

  final int passed;
  final int failed;
  final int running;
  final int pending;
  final int unknown;

  int get total => passed + failed + running + pending + unknown;

  /// Whole per cent of the rows that are green, rounded down: a page that says
  /// 100 must mean it.
  int get percent => total == 0 ? 0 : passed * 100 ~/ total;

  Map<String, Object?> toJson() => <String, Object?>{
    'passed': passed,
    'failed': failed,
    'running': running,
    'pending': pending,
    'unknown': unknown,
    'total': total,
    'percent': percent,
  };
}

/// Adds up [stages].
Progress progressOf(List<Stage> stages) {
  int of(Level level) =>
      stages.fold(0, (sum, stage) => sum + stage.count(level));
  return Progress(
    passed: of(Level.pass),
    failed: of(Level.fail),
    running: of(Level.running),
    pending: of(Level.pending),
    unknown: of(Level.unknown),
  );
}

CheckItem _item(String id, String title, Level level, [String detail = '']) =>
    CheckItem(id: id, title: title, level: level, detail: detail);

/// A row whose answer is a gate's, with a note when the gate ran against an
/// earlier state of the tree than the one on disk now.
CheckItem _gateItem(String id, String title, Snapshots s, String gateId) {
  final result = s.gate(gateId);
  final current = s.git?.fingerprint;
  final stale =
      result.fingerprint != null &&
      current != null &&
      result.fingerprint != current &&
      result.level != Level.running;
  return _item(
    id,
    title,
    result.level,
    stale ? '${result.summary} (before the latest change)' : result.summary,
  );
}

CheckItem _probeItem(
  String id,
  String title,
  Snapshots s,
  List<String> probeIds,
) {
  final results = <String, ProbeResult?>{
    for (final probe in probeIds) probe: s.probes[probe],
  };
  if (results.values.any((ProbeResult? r) => r == null)) {
    return _item(id, title, Level.unknown, 'not looked at yet');
  }
  final missing = <String>[
    for (final entry in results.entries)
      if (!entry.value!.ok) entry.value!.detail,
  ];
  return missing.isEmpty
      ? _item(id, title, Level.pass, results.values.first!.detail)
      : _item(id, title, Level.fail, missing.join('; '));
}

CheckItem _planItem(String id, String title, Snapshots s, String row) {
  if (s.plan.total == 0) return _item(id, title, Level.unknown, 'no plan read');
  return switch (s.plan.statusOf(row)) {
    'done' => _item(id, title, Level.pass, '$row is done'),
    'partial' => _item(id, title, Level.fail, '$row is partial'),
    _ => _item(id, title, Level.fail, '$row is not done'),
  };
}

/// Builds the five stages of the release from [s].
List<Stage> buildChecklist(Snapshots s, ReleaseConfig c) {
  final git = s.git;
  final packages = s.packages;
  final ci = s.ci;

  // --- A. The branch is in a state anybody could take over ----------------
  final structure = s.gate('structure');
  final onlyTestCounts =
      structure.level == Level.fail &&
      structure.brokenRules.isNotEmpty &&
      structure.brokenRules.every((String rule) => rule == testCountRule);

  final structureItem = onlyTestCounts
      ? _item(
          'a-structure',
          'Structure rules hold',
          Level.pass,
          'all but the test-count rule, which stage C owns',
        )
      : _gateItem('a-structure', 'Structure rules hold', s, 'structure');

  final CheckItem integrated = git == null
      ? _item('a-integrated', 'Branches merged in', Level.unknown)
      : () {
          final missing = <String>[
            for (final entry in git.integrated.entries)
              if (!entry.value) entry.key,
          ];
          return missing.isEmpty
              ? _item(
                  'a-integrated',
                  'Branches merged in',
                  Level.pass,
                  git.integrated.isEmpty
                      ? 'nothing to merge'
                      : c.integrationBranches.join(', '),
                )
              : _item(
                  'a-integrated',
                  'Branches merged in',
                  Level.fail,
                  '${missing.join(', ')} has commits this branch lacks',
                );
        }();

  final CheckItem pushed = switch (ci.pushed) {
    true => _item(
      'a-pushed',
      'Branch is on the remote',
      Level.pass,
      'origin has ${git?.branch ?? 'it'}',
    ),
    false => _item(
      'a-pushed',
      'Branch is on the remote',
      Level.fail,
      'only on this machine; CI has never seen it',
    ),
    null => _item(
      'a-pushed',
      'Branch is on the remote',
      Level.unknown,
      ci.error ?? 'not asked yet',
    ),
  };

  final CheckItem ciItem = () {
    const title = 'CI is green on the pushed commit';
    if (ci.pushed != true) {
      return _item(
        'a-ci',
        title,
        ci.pushed == false ? Level.pending : Level.unknown,
        ci.pushed == false ? 'needs the push first' : (ci.error ?? ''),
      );
    }
    final behind =
        ci.runSha != null && ci.headSha != null && ci.runSha != ci.headSha;
    final jobs = ci.jobs.isEmpty
        ? ''
        : ' (${ci.jobs.where((CiJob j) => j.state == 'success').length}'
              ' of ${ci.jobs.length} jobs)';
    return switch (ci.state) {
      'success' when !behind => _item('a-ci', title, Level.pass, 'green$jobs'),
      'success' => _item(
        'a-ci',
        title,
        Level.running,
        'green for an older commit; the newest has not run',
      ),
      'in_progress' ||
      'queued' ||
      'waiting' => _item('a-ci', title, Level.running, '${ci.state}$jobs'),
      'none' => _item('a-ci', title, Level.pending, 'no run yet'),
      'unknown' => _item('a-ci', title, Level.unknown, ci.error ?? ''),
      final other => _item(
        'a-ci',
        title,
        Level.fail,
        '$other$jobs${ci.jobs.where((CiJob j) => j.state == 'failure').map((j) => ', ${j.name}').join()}',
      ),
    };
  }();

  final a = Stage(
    id: 'a',
    title: 'A. Stabilise the branch',
    items: <CheckItem>[
      _gateItem('a-format', 'Code is formatted', s, 'format'),
      _gateItem('a-analyze', 'Analysis is clean', s, 'analyze'),
      structureItem,
      _item(
        'a-ghosts',
        'No leftover package directories',
        packages == null
            ? Level.unknown
            : packages.ghostDirectories.isEmpty
            ? Level.pass
            : Level.fail,
        packages == null || packages.ghostDirectories.isEmpty
            ? ''
            : '${packages.ghostDirectories.length} without a pubspec: '
                  '${packages.ghostDirectories.take(3).join(', ')}',
      ),
      integrated,
      pushed,
      ciItem,
    ],
  );

  // --- B. The open work is finished --------------------------------------
  final missingFixes = <String>[
    for (final probe in const <String>[
      'burst-source',
      'ground-collision',
      'texture-transform',
    ])
      if (s.probes[probe] == null || !s.probes[probe]!.ok) probe,
  ];
  final fixesKnown = <String>[
    'burst-source',
    'ground-collision',
    'texture-transform',
  ].every(s.probes.containsKey);

  final b = Stage(
    id: 'b',
    title: 'B. Finish the open work',
    items: <CheckItem>[
      _probeItem('b-uv', 'The UV mode can be switched into', s, <String>[
        'uv-mode',
      ]),
      _probeItem(
        'b-screens',
        'Built screens are reachable from the modeller',
        s,
        <String>['modeler-screens'],
      ),
      _probeItem(
        'b-lod',
        'A modeller\'s levels of detail reach the exported file',
        s,
        <String>['lod-export'],
      ),
      _probeItem(
        'b-project',
        'A project file keeps modifiers and lights',
        s,
        <String>['project-format'],
      ),
      _probeItem('b-edu', 'The edu-track work is carried over', s, <String>[
        'edu-carried',
      ]),
      _item(
        'b-fixes',
        'Three small engine bugs fixed',
        !fixesKnown
            ? Level.unknown
            : missingFixes.isEmpty
            ? Level.pass
            : Level.fail,
        !fixesKnown || missingFixes.isEmpty
            ? 'a burst lights, ground collides, atlases sample'
            : 'not yet: ${missingFixes.join(', ')}',
      ),
      _planItem('b-draco', 'Draco edgebreaker decodes', s, 'gfx-82n'),
      _planItem('b-uastc', 'UASTC unpacks', s, 'gfx-78n'),
    ],
  );

  // --- C. The shelf is ready to publish ----------------------------------
  final shelf = packages?.shelf ?? const <PackageRow>[];
  final atRelease = shelf
      .where((PackageRow r) => r.version == c.release)
      .length;
  final changelogged = shelf
      .where(
        (PackageRow r) => r.changelogTop == r.version && r.version.isNotEmpty,
      )
      .length;
  final constraintProblems = <String>[
    for (final row in packages?.rows ?? const <PackageRow>[])
      for (final problem in row.problems)
        if (problem.contains('does not admit')) '${row.name} $problem',
  ];

  final testRuleRed = structure.brokenRules.contains(testCountRule);
  final CheckItem testCounts = switch (structure.level) {
    Level.unknown => _item(
      'c-tests',
      'Test counts in the documents match',
      Level.unknown,
    ),
    Level.running => _item(
      'c-tests',
      'Test counts in the documents match',
      Level.running,
    ),
    _ when testRuleRed => _item(
      'c-tests',
      'Test counts in the documents match',
      Level.fail,
      'the documents are behind the tests; run tool/structure.dart',
    ),
    _ => _item('c-tests', 'Test counts in the documents match', Level.pass),
  };

  final ready = packages != null;
  final cStage = Stage(
    id: 'c',
    title: 'C. Prepare the shelf',
    items: <CheckItem>[
      _item(
        'c-versions',
        'Every shelf package is ${c.release}',
        !ready
            ? Level.unknown
            : atRelease == shelf.length && shelf.isNotEmpty
            ? Level.pass
            : Level.fail,
        !ready ? '' : '$atRelease of ${shelf.length}',
      ),
      _item(
        'c-constraints',
        'Constraints between packages admit each other',
        !ready
            ? Level.unknown
            : constraintProblems.isEmpty
            ? Level.pass
            : Level.fail,
        constraintProblems.isEmpty ? '' : constraintProblems.first,
      ),
      _item(
        'c-changelogs',
        'Every CHANGELOG starts at its version',
        !ready
            ? Level.unknown
            : changelogged == shelf.length && shelf.isNotEmpty
            ? Level.pass
            : Level.fail,
        !ready ? '' : '$changelogged of ${shelf.length}',
      ),
      _gateItem(
        'c-publish',
        'Publish dry run passes for every package',
        s,
        'publish',
      ),
      _probeItem(
        'c-docs',
        'The boundary document and section 16 describe ${c.release}',
        s,
        <String>['boundary-doc', 'architecture-doc'],
      ),
      testCounts,
      _gateItem('c-ci', 'The whole local pipeline passes', s, 'ci'),
    ],
  );

  // --- D. The modeller is published --------------------------------------
  final sites = s.sites;
  final d = Stage(
    id: 'd',
    title: 'D. Publish the modeller',
    items: <CheckItem>[
      _probeItem('d-version', 'The modeller carries ${c.release}', s, <String>[
        'modeler-version',
      ]),
      _probeItem(
        'd-deploy',
        'The tutorial is deployed beside the server',
        s,
        <String>['tutorial-deploy'],
      ),
      _gateItem('d-web', 'The web build compiles', s, 'web'),
      _item(
        'd-health',
        'models.pleion.dev answers',
        sites.healthy == null
            ? Level.unknown
            : sites.healthy!
            ? Level.pass
            : Level.fail,
        sites.error ??
            (sites.healthy == true ? 'health ok' : 'health did not say ok'),
      ),
      _item(
        'd-learn',
        'The tutorial index lists ${c.tutorialCases} cases',
        sites.learnCases == null
            ? Level.unknown
            : sites.learnCases == c.tutorialCases
            ? Level.pass
            : Level.fail,
        sites.learnCases == null
            ? (sites.error ?? '')
            : '${sites.learnCases} listed',
      ),
    ],
  );

  // --- E. After the cohort: publication ----------------------------------
  final pubdev = s.pubdev;
  final onPubDev = shelf
      .where((PackageRow r) => pubdev.latest[r.name] == c.release)
      .length;
  final discontinued = c.endedNames
      .where((String name) => pubdev.discontinued[name] == true)
      .length;

  final cohortDone = s.plan.statusOf(c.cohortRow) == 'done';
  final e = Stage(
    id: 'e',
    title: 'E. Publish ${c.release} (after the cohort)',
    items: <CheckItem>[
      _item(
        'e-cohort',
        'People have walked the tutorial',
        s.plan.total == 0
            ? Level.unknown
            : cohortDone
            ? Level.pass
            : Level.pending,
        cohortDone ? '${c.cohortRow} is done' : 'waiting on ${c.cohortRow}',
      ),
      _item(
        'e-published',
        'The shelf is on pub.dev',
        !pubdev.known
            ? Level.unknown
            : shelf.isNotEmpty && onPubDev == shelf.length
            ? Level.pass
            : Level.pending,
        !pubdev.known
            ? (pubdev.error ?? '')
            : '$onPubDev of ${shelf.length} at ${c.release}',
      ),
      _item(
        'e-tag',
        'The commit that shipped is tagged ${c.tag}',
        git == null
            ? Level.unknown
            : git.tags.contains(c.tag)
            ? Level.pass
            : Level.pending,
      ),
      _item(
        'e-discontinued',
        'The ${c.endedNames.length} ended names are marked discontinued',
        !pubdev.known
            ? Level.unknown
            : discontinued == c.endedNames.length
            ? Level.pass
            : Level.pending,
        !pubdev.known
            ? (pubdev.error ?? '')
            : '$discontinued of ${c.endedNames.length}',
      ),
    ],
  );

  // --- F. The showcase ---------------------------------------------------
  final show = s.showcase;

  CheckItem setItem(ShowcaseSet set) {
    final id = 'f-set-${set.id}';
    final title = 'Set ${set.id.toUpperCase()}: ${set.title}';
    if (set.expected == 0) {
      return _item(
        id,
        title,
        Level.unknown,
        'the coverage list names no pages',
      );
    }
    final counts = '${set.pages} of ${set.expected} pages';
    final rows = set.catalogRows == set.pages
        ? ''
        : '; ${set.catalogRows} catalog rows for ${set.pages} pages';
    if (set.pages == 0) {
      return _item(id, title, Level.pending, 'not started: $counts');
    }
    if (set.pages < set.expected) {
      return _item(id, title, Level.running, '$counts$rows');
    }
    return rows.isEmpty
        ? _item(id, title, Level.pass, counts)
        : _item(id, title, Level.fail, '$counts$rows');
  }

  final f = Stage(
    id: 'f',
    title: 'F. The showcase',
    items: <CheckItem>[
      _probeItem(
        'f-lod',
        'A model with levels of detail draws in the game',
        s,
        const <String>['showcase-lod'],
      ),
      _probeItem(
        'f-platform',
        'The app and its platform exist',
        s,
        const <String>['showcase-platform'],
      ),
      if (show.sets.isEmpty)
        _item(
          'f-sets',
          'The pages of each set',
          Level.pending,
          'no coverage list yet',
        )
      else
        for (final set in show.sets) setItem(set),
      _item(
        'f-coverage',
        'Every 0.7.0 entry has a page or a reason',
        show.coverageFilled ? Level.pass : Level.pending,
        show.coverageFilled ? '' : 'the audit in coverage.md is not written',
      ),
      _probeItem(
        'f-site',
        'The site builds the guides and the source',
        s,
        const <String>['showcase-site'],
      ),
      _gateItem('f-tests', 'The showcase tests pass', s, 'showcase-tests'),
      _gateItem('f-web', 'The showcase web build compiles', s, 'showcase-web'),
      _item(
        'f-deployed',
        'The showcase is published',
        switch (show.live) {
          true => Level.pass,
          false => Level.fail,
          null => Level.unknown,
        },
        switch (show.live) {
          true => 'flutter3d.pleion.dev/showcase/ answers',
          false => 'flutter3d.pleion.dev/showcase/ answers with something else',
          null => 'not measured: not published, or the host is behind a login',
        },
      ),
    ],
  );

  return <Stage>[a, b, cStage, d, e, f];
}
