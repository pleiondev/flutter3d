import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';
import 'package:test/test.dart';

import 'fakes.dart';

Map<String, Object?> gateOf(Map<String, Object?> state, String id) =>
    (state['gates']! as List<Object?>).cast<Map<String, Object?>>().firstWhere(
      (g) => g['id'] == id,
    );

void main() {
  late FakeSources sources;
  late Dashboard dashboard;

  setUp(() {
    sources = FakeSources();
    dashboard = dashboardOver(sources);
  });

  test('a first look runs the quick gates and only those', () async {
    final state = await dashboard.look();
    expect(sources.ran, <String>['quick']);
    expect(gateOf(state, 'quick')['level'], 'pass');
    expect(gateOf(state, 'slow')['level'], 'unknown');
  });

  test('a second look at the same tree runs nothing', () async {
    await dashboard.look();
    await dashboard.look();
    expect(sources.ran, <String>['quick']);
  });

  test('a changed tree runs the quick gates again', () async {
    await dashboard.look();
    sources.fingerprint = 'two';
    await dashboard.look();
    expect(sources.ran, <String>['quick', 'quick']);
  });

  test('a gate asked for by name runs whatever it last said', () async {
    await dashboard.look(run: <String>{'slow'});
    await dashboard.look(run: <String>{'slow'});
    expect(sources.ran.where((id) => id == 'slow'), hasLength(2));
  });

  test(
    'a running gate is shown as running, and a repeat request waits',
    () async {
      final hold = sources.release = Completer<void>();
      expect(dashboard.runGate('slow'), isTrue);
      expect(dashboard.runGate('slow'), isFalse);
      expect(dashboard.runGate('missing'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(gateOf(dashboard.state(), 'slow')['level'], 'running');
      hold.complete();
      await dashboard.idle();
      expect(gateOf(dashboard.state(), 'slow')['level'], 'pass');
    },
  );

  test('gates never overlap', () async {
    final hold = sources.release = Completer<void>();
    dashboard
      ..runGate('slow')
      ..runGate('quick');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sources.ran, <String>['slow']);
    expect(gateOf(dashboard.state(), 'quick')['queued'], isTrue);
    hold.complete();
    await dashboard.idle();
    expect(sources.ran, <String>['slow', 'quick']);
  });

  test('a failing script is a red gate', () async {
    sources.result = const Ran(
      exitCode: 1,
      lines: <String>['boom'],
      duration: Duration(seconds: 1),
    );
    final state = await dashboard.look(run: <String>{'slow'});
    expect(gateOf(state, 'slow')['level'], 'fail');
  });

  test('a result from before an edit is marked stale', () async {
    await dashboard.look();
    sources.fingerprint = 'two';
    await dashboard.refreshLocal();
    await dashboard.idle();
    // The rerun on the new tree is current again.
    expect(gateOf(dashboard.state(), 'quick')['stale'], isFalse);

    final slow = await dashboard.look(run: <String>{'slow'});
    expect(gateOf(slow, 'slow')['stale'], isFalse);
    sources.fingerprint = 'three';
    await dashboard.refreshLocal();
    expect(gateOf(dashboard.state(), 'slow')['stale'], isTrue);
  });

  group('memory', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('memory_');
      file = File('${dir.path}/nested/results.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('results outlive the process that judged them', () async {
      await dashboardOver(sources, memory: file).look(run: <String>{'slow'});
      sources.ran.clear();

      final later = dashboardOver(sources, memory: file);
      final state = await later.look();
      expect(sources.ran, isEmpty, reason: 'the tree has not changed');
      expect(gateOf(state, 'slow')['level'], 'pass');
      expect(gateOf(state, 'quick')['level'], 'pass');
    });

    test('a changed tree makes a remembered quick gate run again', () async {
      await dashboardOver(sources, memory: file).look();
      sources.fingerprint = 'two';
      sources.ran.clear();
      await dashboardOver(sources, memory: file).look();
      expect(sources.ran, <String>['quick']);
    });

    test('a damaged file is the same as no file', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{not json');
      final state = await dashboardOver(sources, memory: file).look();
      expect(gateOf(state, 'quick')['level'], 'pass');
    });
  });

  test('the state is plain JSON', () async {
    final state = await dashboard.look();
    expect(jsonDecode(jsonEncode(state)), containsPair('release', '0.7.0'));
  });
}
