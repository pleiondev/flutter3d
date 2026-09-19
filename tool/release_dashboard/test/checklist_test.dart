import 'package:release_dashboard/release_dashboard.dart';
import 'package:test/test.dart';

Snapshots snapshots({
  Map<String, GateResult> gates = const <String, GateResult>{},
  PackagesSnapshot? packages,
  CiSnapshot ci = const CiSnapshot.unknown(),
}) => Snapshots(
  git: null,
  packages: packages,
  plan: const PlanSnapshot.empty(),
  probes: const <String, ProbeResult>{},
  gates: gates,
  pubdev: const PubDevSnapshot.unknown(),
  sites: const SitesSnapshot.unknown(),
  ci: ci,
);

CheckItem item(List<Stage> stages, String id) =>
    stages.expand((s) => s.items).firstWhere((i) => i.id == id);

void main() {
  const config = ReleaseConfig();

  test('nothing has been measured, so nothing is green', () {
    final stages = buildChecklist(snapshots(), config);
    expect(stages.map((s) => s.id), <String>['a', 'b', 'c', 'd', 'e']);
    expect(item(stages, 'a-format').level, Level.unknown);
    expect(progressOf(stages).passed, 0);
  });

  test('a gate that failed is a red row with its own words', () {
    final stages = buildChecklist(
      snapshots(
        gates: const <String, GateResult>{
          'format': GateResult(level: Level.fail, summary: '7 files'),
        },
      ),
      config,
    );
    final row = item(stages, 'a-format');
    expect(row.level, Level.fail);
    expect(row.detail, '7 files');
  });

  test('structure counts as passed when only the test-count rule is red', () {
    final stages = buildChecklist(
      snapshots(
        gates: const <String, GateResult>{
          'structure': GateResult(
            level: Level.fail,
            summary: '1 rule',
            brokenRules: <String>[testCountRule],
          ),
        },
      ),
      config,
    );
    expect(item(stages, 'a-structure').level, Level.pass);
  });

  test('structure stays red when any other rule is red as well', () {
    final stages = buildChecklist(
      snapshots(
        gates: const <String, GateResult>{
          'structure': GateResult(
            level: Level.fail,
            summary: '2 rules',
            brokenRules: <String>[testCountRule, 'some other rule'],
          ),
        },
      ),
      config,
    );
    expect(item(stages, 'a-structure').level, Level.fail);
  });

  test('an unpushed branch is red and CI waits on it', () {
    final stages = buildChecklist(
      snapshots(
        ci: CiSnapshot(
          pushed: false,
          headSha: null,
          runSha: null,
          state: 'none',
          jobs: const <CiJob>[],
          url: null,
          fetchedAt: DateTime(2026),
        ),
      ),
      config,
    );
    expect(item(stages, 'a-pushed').level, Level.fail);
    expect(item(stages, 'a-ci').level, Level.pending);
  });

  test('a network that did not answer is unknown, not pending', () {
    final stages = buildChecklist(snapshots(), config);
    expect(item(stages, 'a-pushed').level, Level.unknown);
    expect(item(stages, 'e-published').level, isNot(Level.pending));
  });

  test('leftover package directories turn the row red', () {
    final stages = buildChecklist(
      snapshots(
        packages: const PackagesSnapshot(
          rows: <PackageRow>[],
          ghostDirectories: <String>['flutter3d_old'],
          release: '0.7.0',
        ),
      ),
      config,
    );
    expect(item(stages, 'a-ghosts').level, Level.fail);
    expect(item(stages, 'a-ghosts').detail, contains('flutter3d_old'));
  });

  test('progress counts every row once', () {
    final progress = progressOf(buildChecklist(snapshots(), config));
    expect(
      progress.passed +
          progress.failed +
          progress.running +
          progress.pending +
          progress.unknown,
      progress.total,
    );
    expect(progress.percent, inInclusiveRange(0, 100));
  });
}
