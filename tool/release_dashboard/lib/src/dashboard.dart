/// The state of the release, kept current.
///
/// **One object owns what is known and when it changes.** Sources answer, this
/// keeps the latest answer of each, builds the checklist from them and tells
/// whoever is listening when the picture is different. Nothing else holds a
/// result, so the page cannot show something the checklist was not judged from.
///
/// **Slow checks run one at a time.** The gates are the repository's own
/// scripts, each of which takes the pub lock or the whole CPU; run together they
/// would slow each other and, worse, disagree about a tree that is changing
/// under them. So there is a queue, and a change to the tree schedules the quick
/// gates again after it has stopped changing.
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
  Future<Ran> run(Gate gate) => runCommand(
    gate.command,
    workingDirectory: root.path,
    timeout: gate.timeout,
  );
}

/// One line of what has happened since the page was opened.
final class DashboardEvent {
  const DashboardEvent(this.at, this.text, this.level);

  final DateTime at;
  final String text;
  final Level level;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toIso8601String(),
    'text': text,
    'level': level.name,
  };
}

/// The live state, and the only way to change it.
final class Dashboard {
  Dashboard({
    required this.root,
    required this.config,
    required this.sources,
    required List<Gate> gates,
    this.quietPeriod = const Duration(seconds: 4),
  }) : gates = List<Gate>.unmodifiable(gates);

  final Directory root;
  final ReleaseConfig config;
  final Sources sources;
  final List<Gate> gates;

  /// How long the tree must stay unchanged before the quick gates run again.
  /// An editor saving twenty files should cost one run, not twenty.
  final Duration quietPeriod;

  GitSnapshot? _git;
  PackagesSnapshot? _packages;
  PlanSnapshot _plan = const PlanSnapshot.empty();
  Map<String, ProbeResult> _probes = const <String, ProbeResult>{};
  PubDevSnapshot _pubdev = const PubDevSnapshot.unknown();
  SitesSnapshot _sites = const SitesSnapshot.unknown();
  CiSnapshot _ci = const CiSnapshot.unknown();
  List<AgentWorktree> _agents = const <AgentWorktree>[];

  final Map<String, GateResult> _results = <String, GateResult>{};
  final List<String> _queue = <String>[];
  String? _running;

  final List<DashboardEvent> _events = <DashboardEvent>[];
  Map<String, Level> _lastLevels = const <String, Level>{};
  String? _lastStable;

  String? _autoRanFor;
  String? _changeSeen;
  DateTime? _changeSeenAt;

  final StreamController<String> _out = StreamController<String>.broadcast();
  final List<Timer> _timers = <Timer>[];
  bool _closed = false;

  /// Full state as JSON, whenever it has changed or on the heartbeat.
  Stream<String> get updates => _out.stream;

  // --- Lifecycle --------------------------------------------------------

  /// Reads everything once, then keeps reading on a schedule.
  Future<void> start() async {
    await refreshLocal();
    unawaited(refreshRemote());
    _timers.addAll(<Timer>[
      Timer.periodic(const Duration(seconds: 5), (_) => refreshLocal()),
      Timer.periodic(const Duration(seconds: 60), (_) => _refreshCiAndSites()),
      Timer.periodic(const Duration(minutes: 10), (_) => _refreshPubDev()),
      Timer.periodic(const Duration(seconds: 10), (_) => _publish(force: true)),
    ]);
  }

  Future<void> close() async {
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    await _out.close();
  }

  // --- Reading ----------------------------------------------------------

  /// The sources that are cheap: files and git, no network.
  Future<void> refreshLocal() async {
    if (_closed) return;
    _git = await sources.git();
    _packages = await sources.packages();
    _plan = sources.plan();
    _probes = sources.probes();
    _agents = await sources.agents(_git?.branch ?? '');
    _scheduleAutoGates();
    _publish();
  }

  /// The sources that need the network.
  Future<void> refreshRemote() async {
    await _refreshCiAndSites();
    await _refreshPubDev();
  }

  Future<void> _refreshCiAndSites() async {
    if (_closed) return;
    final branch = _git?.branch;
    if (branch != null && branch.isNotEmpty) _ci = await sources.ci(branch);
    _sites = await sources.sites();
    _publish();
  }

  Future<void> _refreshPubDev() async {
    if (_closed) return;
    final names = <String>[
      for (final row in _packages?.rows ?? const <PackageRow>[]) row.name,
    ];
    _pubdev = await sources.pubdev(names);
    _publish();
  }

  // --- Gates ------------------------------------------------------------

  /// Puts the quick gates in the queue once the tree has stopped changing.
  void _scheduleAutoGates() {
    final fingerprint = _git?.fingerprint;
    if (fingerprint == null || fingerprint == _autoRanFor) return;

    // The very first look at a tree has nothing to wait for. Every later change
    // does: it is run once the fingerprint has held still for [quietPeriod].
    if (_autoRanFor != null) {
      if (fingerprint != _changeSeen) {
        _changeSeen = fingerprint;
        _changeSeenAt = DateTime.now();
        return;
      }
      final since = DateTime.now().difference(_changeSeenAt!);
      if (since < quietPeriod) return;
    }

    _autoRanFor = fingerprint;
    for (final gate in gates.where((Gate g) => g.auto)) {
      _enqueue(gate.id);
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
    _publish();
    unawaited(_drain());
    return true;
  }

  bool _draining = false;

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_closed) {
        final id = _queue.removeAt(0);
        final gate = gates.firstWhere((Gate g) => g.id == id);
        _running = id;
        _publish();

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
        _remember(
          '${gate.title}: ${judged.summary} '
          '(${ran.duration.inSeconds} s)',
          judged.level,
        );
        _publish();
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
  );

  void _remember(String text, Level level) {
    _events.insert(0, DashboardEvent(DateTime.now(), text, level));
    if (_events.length > 80) _events.removeRange(80, _events.length);
  }

  /// The whole state, as it is now.
  Map<String, Object?> state() {
    final snapshots = _snapshots();
    final stages = buildChecklist(snapshots, config);
    final progress = progressOf(stages);

    // What turned since the last look is news; what stayed is not.
    final levels = <String, Level>{
      for (final stage in stages)
        for (final item in stage.items) item.id: item.level,
    };
    if (_lastLevels.isNotEmpty) {
      for (final stage in stages) {
        for (final item in stage.items) {
          final before = _lastLevels[item.id];
          if (before != null && before != item.level) {
            _remember(
              '${item.title}: ${before.name} to ${item.level.name}',
              item.level,
            );
          }
        }
      }
    }
    _lastLevels = levels;

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
      'events': <Object?>[for (final e in _events) e.toJson()],
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

  /// Sends the state to listeners if it differs from what they last had, or
  /// unconditionally on the heartbeat, so a page that missed a change and the
  /// "asked N s ago" beside each remote source are never stale for long.
  void _publish({bool force = false}) {
    if (_closed || _out.isClosed) return;
    final current = state();
    final stable = jsonEncode(_withoutTimes(current));
    if (!force && stable == _lastStable) return;
    _lastStable = stable;
    _out.add(jsonEncode(current));
  }

  static Object? _withoutTimes(Object? node) => switch (node) {
    Map<String, Object?>() => <String, Object?>{
      for (final MapEntry(:key, :value) in node.entries)
        if (key != 'generatedAt' && key != 'fetchedAt')
          key: _withoutTimes(value),
    },
    List<Object?>() => <Object?>[for (final item in node) _withoutTimes(item)],
    _ => node,
  };
}
