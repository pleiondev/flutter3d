/// The state of the release, taken in one look.
///
/// **One object owns what is known.** Sources answer, this keeps the latest
/// answer of each and builds the checklist from them, so nothing shows
/// something the checklist was not judged from.
///
/// **Checks run one at a time.** The gates are the repository's own scripts,
/// each of which takes the pub lock or the whole CPU; run together they would
/// slow each other and, worse, disagree about a tree that is changing under
/// them. A quick gate runs again only when the tree is different from the one
/// it last judged, and every result is kept in a file, so a look that finds
/// nothing changed costs no scripts at all.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'checklist.dart';
import 'gates.dart';
import 'git.dart';
import 'model.dart';
import 'packages.dart';
import 'plan.dart';
import 'probes.dart';
import 'remote.dart';
import 'shell.dart';
import 'showcase.dart';

/// Where the dashboard's facts come from. Real ones read the repository and the
/// network; a test supplies its own.
abstract interface class Sources {
  Future<GitSnapshot> git();
  Future<List<AgentWorktree>> agents(String branch);
  Future<PackagesSnapshot> packages();
  PlanSnapshot plan();
  Map<String, ProbeResult> probes();
  Future<PubDevSnapshot> pubdev(List<String> names);
  Future<SitesSnapshot> sites();
  Future<CiSnapshot> ci(String branch);
  ShowcaseSnapshot showcase();
  Future<bool?> showcaseLive();
  Future<Ran> run(Gate gate);
}

/// The [Sources] that look at the real tree and the real network.
final class LocalSources implements Sources {
  LocalSources(this.root, this.config, {Fetch? fetch})
    : _fetch = fetch ?? httpFetch,
      _probes = releaseProbes();

  final Directory root;
  final ReleaseConfig config;
  final Fetch _fetch;
  final Map<String, Probe> _probes;

  @override
  Future<GitSnapshot> git() =>
      readGit(root, mustHave: config.integrationBranches);

  @override
  Future<List<AgentWorktree>> agents(String branch) => readAgents(root, branch);

  @override
  Future<PackagesSnapshot> packages() =>
      scanPackages(root, release: config.release, ownLine: config.ownLine);

  @override
  PlanSnapshot plan() => readPlan(root);

  @override
  Map<String, ProbeResult> probes() => <String, ProbeResult>{
    for (final MapEntry(:key, :value) in _probes.entries) key: value(root),
  };

  @override
  Future<PubDevSnapshot> pubdev(List<String> names) =>
      readPubDev(_fetch, names: names, discontinuedNames: config.endedNames);

  @override
  Future<SitesSnapshot> sites() =>
      readSites(_fetch, origin: 'https://models.pleion.dev');

  @override
  Future<CiSnapshot> ci(String branch) => readCi(root, branch);

  @override
  ShowcaseSnapshot showcase() => readShowcase(root);

  @override
  Future<bool?> showcaseLive() =>
      readShowcaseLive(_fetch, origin: 'https://flutter3d.pleion.dev');

  @override
  Future<Ran> run(Gate gate) => runCommand(
    gate.command,
    workingDirectory: root.path,
    timeout: gate.timeout,
  );
}

/// The state of the release, and the only way to change it.
final class Dashboard {
  Dashboard({
    required this.root,
    required this.config,
    required this.sources,
    required List<Gate> gates,
    this.memory,
  }) : gates = List<Gate>.unmodifiable(gates) {
    _remember();
  }

  final Directory root;
  final ReleaseConfig config;
  final Sources sources;
  final List<Gate> gates;

  /// Where results are kept between looks; null keeps them in memory only.
  final File? memory;

  GitSnapshot? _git;
  PackagesSnapshot? _packages;
  PlanSnapshot _plan = const PlanSnapshot.empty();
  Map<String, ProbeResult> _probes = const <String, ProbeResult>{};
  PubDevSnapshot _pubdev = const PubDevSnapshot.unknown();
  SitesSnapshot _sites = const SitesSnapshot.unknown();
  CiSnapshot _ci = const CiSnapshot.unknown();
  List<AgentWorktree> _agents = const <AgentWorktree>[];
  ShowcaseSnapshot _showcase = const ShowcaseSnapshot.absent();
  bool? _showcaseLive;

  final Map<String, GateResult> _results = <String, GateResult>{};
  final List<String> _queue = <String>[];
  String? _running;

  // --- Looking ----------------------------------------------------------

  /// One look at everything: reads every source, runs the quick gates that
  /// have not judged this tree, runs the gates in [run] whatever they judged,
  /// waits for the queue to empty and returns the state.
  Future<Map<String, Object?>> look({
    Set<String> run = const <String>{},
  }) async {
    await refreshLocal();
    await refreshRemote();
    run.forEach(runGate);
    await idle();
    return state();
  }

  /// Completes once no gate is running or waiting.
  Future<void> idle() async {
    while (_draining || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  // --- Reading ----------------------------------------------------------

  /// The sources that are cheap: files and git, no network.
  Future<void> refreshLocal() async {
    _git = await sources.git();
    _packages = await sources.packages();
    _plan = sources.plan();
    _probes = sources.probes();
    _showcase = sources.showcase();
    _agents = await sources.agents(_git?.branch ?? '');
    _scheduleAutoGates();
  }

  /// The sources that need the network.
  Future<void> refreshRemote() async {
    await _refreshCiAndSites();
    await _refreshPubDev();
  }

  Future<void> _refreshCiAndSites() async {
    final branch = _git?.branch;
    if (branch != null && branch.isNotEmpty) _ci = await sources.ci(branch);
    _sites = await sources.sites();
    _showcaseLive = await sources.showcaseLive();
  }

  Future<void> _refreshPubDev() async {
    final names = <String>[
      for (final row in _packages?.rows ?? const <PackageRow>[]) row.name,
    ];
    _pubdev = await sources.pubdev(names);
  }

  // --- Gates ------------------------------------------------------------

  /// Queues the quick gates that have not judged this tree: never run, or run
  /// against a tree that has since changed.
  void _scheduleAutoGates() {
    final fingerprint = _git?.fingerprint;
    if (fingerprint == null) return;
    for (final gate in gates.where((Gate g) => g.auto)) {
      if (_results[gate.id]?.fingerprint != fingerprint) _enqueue(gate.id);
    }
  }

  /// Queues [id] to run. False when there is no such gate, or it is already
  /// waiting or running: a second click on the same button changes nothing.
  bool runGate(String id) {
    if (!gates.any((Gate g) => g.id == id)) return false;
    return _enqueue(id);
  }

  bool _enqueue(String id) {
    if (_running == id || _queue.contains(id)) return false;
    _queue.add(id);
    unawaited(_drain());
    return true;
  }

  bool _draining = false;

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final id = _queue.removeAt(0);
        final gate = gates.firstWhere((Gate g) => g.id == id);
        _running = id;

        final fingerprint = _git?.fingerprint;
        final ran = await sources.run(gate);
        final judged = gate.judge(ran);
        _results[id] = GateResult(
          level: judged.level,
          summary: judged.summary,
          brokenRules: judged.brokenRules,
          tail: judged.tail,
          ranAt: DateTime.now(),
          duration: ran.duration,
          fingerprint: fingerprint,
        );
        _running = null;
        _keep();
      }
    } finally {
      _draining = false;
    }
  }

  // --- The picture ------------------------------------------------------

  Snapshots _snapshots() => Snapshots(
    git: _git,
    packages: _packages,
    plan: _plan,
    probes: _probes,
    gates: <String, GateResult>{
      for (final gate in gates)
        gate.id: gate.id == _running
            ? (_results[gate.id] ?? const GateResult.unrun()).copyWith(
                level: Level.running,
                summary: 'running',
              )
            : (_results[gate.id] ?? const GateResult.unrun()),
    },
    pubdev: _pubdev,
    sites: _sites,
    ci: _ci,
    showcase: _showcase.withLive(_showcaseLive),
  );

  /// The whole state, as it is now.
  Map<String, Object?> state() {
    final snapshots = _snapshots();
    final stages = buildChecklist(snapshots, config);
    final progress = progressOf(stages);

    return <String, Object?>{
      'generatedAt': DateTime.now().toIso8601String(),
      'release': config.release,
      'root': root.path,
      'progress': progress.toJson(),
      'stages': <Object?>[for (final stage in stages) stage.toJson()],
      'git': _git == null
          ? null
          : <String, Object?>{
              'branch': _git!.branch,
              'head': _git!.head,
              'subject': _git!.subject,
              'dirty': _git!.dirtyCount,
              'aheadOfMain': _git!.aheadOfMain,
              'tags': _git!.tags,
            },
      'agents': <Object?>[for (final a in _agents) a.toJson()],
      'gates': <Object?>[
        for (final gate in gates) _gateJson(gate, snapshots.gate(gate.id)),
      ],
      'packages': <Object?>[
        for (final row in _packages?.rows ?? const <PackageRow>[])
          <String, Object?>{
            'name': row.name,
            'version': row.version,
            'changelog': row.changelogTop,
            'ownLine': row.ownLine,
            'problems': row.problems,
            'pubdev': _pubdev.known ? _pubdev.latest[row.name] : null,
          },
      ],
      'plan': <String, Object?>{
        'total': _plan.total,
        'done': _plan.done,
        'partial': _plan.partial,
        'todo': _plan.todo,
        'release': <String, String>{
          for (final MapEntry(:key, :value) in _plan.rows.entries)
            if (key.startsWith('rel-')) key: value,
        },
      },
      'ci': <String, Object?>{
        'pushed': _ci.pushed,
        'state': _ci.state,
        'url': _ci.url,
        'jobs': <Object?>[for (final job in _ci.jobs) job.toJson()],
        'error': _ci.error,
        'fetchedAt': _ci.fetchedAt?.toIso8601String(),
      },
      'sites': <String, Object?>{
        'healthy': _sites.healthy,
        'learnCases': _sites.learnCases,
        'error': _sites.error,
        'fetchedAt': _sites.fetchedAt?.toIso8601String(),
      },
      'pubdev': <String, Object?>{
        'known': _pubdev.known,
        'error': _pubdev.error,
        'fetchedAt': _pubdev.fetchedAt?.toIso8601String(),
      },
    };
  }

  Map<String, Object?> _gateJson(Gate gate, GateResult result) =>
      <String, Object?>{
        'id': gate.id,
        'title': gate.title,
        'command': gate.command.join(' '),
        'auto': gate.auto,
        'level': result.level.name,
        'summary': result.summary,
        'brokenRules': result.brokenRules,
        'tail': result.tail,
        'ranAt': result.ranAt?.toIso8601String(),
        'seconds': result.duration?.inSeconds,
        'queued': _queue.contains(gate.id),
        'stale':
            result.fingerprint != null &&
            _git != null &&
            result.fingerprint != _git!.fingerprint,
      };

  // --- Memory -----------------------------------------------------------

  /// Reads the results kept by an earlier look. Anything unreadable is
  /// dropped: a gate with no result simply runs.
  void _remember() {
    final file = memory;
    if (file == null || !file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return;
      for (final gate in gates) {
        final result = GateResult.fromJson(json[gate.id]);
        if (result != null && result.level != Level.running) {
          _results[gate.id] = result;
        }
      }
    } on Object {
      // A damaged file is the same as no file.
    }
  }

  void _keep() {
    final file = memory;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode(<String, Object?>{
          for (final MapEntry(:key, :value) in _results.entries)
            key: value.toJson(),
        }),
      );
    } on FileSystemException {
      // Losing the memory costs a rerun, not the look.
    }
  }
}
