import 'dart:async';
import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';

/// [Sources] that answer from memory, so a test sees the dashboard and nothing
/// else. [run] waits on [release] when one is set, to hold a gate "running".
final class FakeSources implements Sources {
  FakeSources({this.fingerprint = 'one'});

  String fingerprint;
  final List<String> ran = <String>[];
  Completer<void>? release;
  Ran result = const Ran(
    exitCode: 0,
    lines: <String>['done'],
    duration: Duration(seconds: 1),
  );

  @override
  Future<GitSnapshot> git() async => GitSnapshot(
    branch: 'topic',
    head: 'abc1234',
    subject: 'A commit',
    dirtyCount: 0,
    aheadOfMain: 3,
    tags: const <String>[],
    integrated: const <String, bool>{},
    fingerprint: fingerprint,
  );

  @override
  Future<List<AgentWorktree>> agents(String branch) async =>
      const <AgentWorktree>[];

  @override
  Future<PackagesSnapshot> packages() async => const PackagesSnapshot(
    rows: <PackageRow>[],
    ghostDirectories: <String>[],
    release: '0.7.0',
  );

  @override
  PlanSnapshot plan() => const PlanSnapshot.empty();

  @override
  Map<String, ProbeResult> probes() => const <String, ProbeResult>{};

  @override
  Future<PubDevSnapshot> pubdev(List<String> names) async =>
      const PubDevSnapshot.unknown();

  @override
  Future<SitesSnapshot> sites() async => const SitesSnapshot.unknown();

  @override
  Future<CiSnapshot> ci(String branch) async => const CiSnapshot.unknown();

  @override
  ShowcaseSnapshot showcase() => const ShowcaseSnapshot.absent();

  @override
  Future<bool?> showcaseLive() async => null;

  @override
  Future<Ran> run(Gate gate) async {
    ran.add(gate.id);
    await release?.future;
    return result;
  }
}

/// One quick and one slow gate, both judged by exit code.
List<Gate> fakeGates() => <Gate>[
  Gate(
    id: 'quick',
    title: 'quick',
    command: const <String>['true'],
    judge: (Ran r) => GateResult(
      level: r.ok ? Level.pass : Level.fail,
      summary: r.ok ? 'fine' : 'broken',
    ),
    auto: true,
  ),
  Gate(
    id: 'slow',
    title: 'slow',
    command: const <String>['true'],
    judge: (Ran r) => GateResult(
      level: r.ok ? Level.pass : Level.fail,
      summary: r.ok ? 'fine' : 'broken',
    ),
  ),
];

Dashboard dashboardOver(FakeSources sources, {File? memory}) => Dashboard(
  root: Directory.systemTemp,
  config: const ReleaseConfig(),
  sources: sources,
  gates: fakeGates(),
  memory: memory,
);
