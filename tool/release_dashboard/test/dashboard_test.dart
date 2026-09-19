import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';
import 'package:test/test.dart';

import 'fakes.dart';

Map<String, Object?> gateOf(Dashboard d, String id) =>
    (d.state()['gates']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((g) => g['id'] == id);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('Dashboard', () {
    late FakeSources sources;
    late Dashboard dashboard;

    setUp(() {
      sources = FakeSources();
      dashboard = dashboardOver(sources);
    });
    tearDown(() => dashboard.close());

    test('the first look runs the quick gates and only those', () async {
      await dashboard.refreshLocal();
      await settle();
      expect(sources.ran, <String>['quick']);
      expect(gateOf(dashboard, 'quick')['level'], 'pass');
      expect(gateOf(dashboard, 'slow')['level'], 'unknown');
    });

    test('a click runs a slow gate, and a second click changes nothing', () {
      final hold = sources.release = Completer<void>();
      expect(dashboard.runGate('slow'), isTrue);
      expect(dashboard.runGate('slow'), isFalse);
      expect(dashboard.runGate('missing'), isFalse);
      hold.complete();
    });

    test('a running gate is shown as running, then as its verdict', () async {
      final hold = sources.release = Completer<void>();
      dashboard.runGate('slow');
      await settle();
      expect(gateOf(dashboard, 'slow')['level'], 'running');
      hold.complete();
      await settle();
      expect(gateOf(dashboard, 'slow')['level'], 'pass');
    });

    test('gates never overlap', () async {
      final hold = sources.release = Completer<void>();
      dashboard
        ..runGate('slow')
        ..runGate('quick');
      await settle();
      expect(sources.ran, <String>['slow']);
      expect(gateOf(dashboard, 'quick')['queued'], isTrue);
      hold.complete();
      await settle();
      expect(sources.ran, <String>['slow', 'quick']);
    });

    test('a failing script is a red gate', () async {
      sources.result = const Ran(
        exitCode: 1,
        lines: <String>['boom'],
        duration: Duration(seconds: 1),
      );
      dashboard.runGate('slow');
      await settle();
      expect(gateOf(dashboard, 'slow')['level'], 'fail');
    });

    test(
      'an edit reruns the quick gates only after the tree is quiet',
      () async {
        await dashboard.refreshLocal();
        await settle();
        expect(sources.ran, <String>['quick']);

        sources.fingerprint = 'two';
        await dashboard.refreshLocal();
        await settle();
        expect(sources.ran, hasLength(1), reason: 'the change was just seen');

        await Future<void>.delayed(const Duration(milliseconds: 80));
        await dashboard.refreshLocal();
        await settle();
        expect(sources.ran, <String>['quick', 'quick']);
      },
    );

    test('a result from before an edit is marked stale', () async {
      await dashboard.refreshLocal();
      await settle();
      expect(gateOf(dashboard, 'quick')['stale'], isFalse);
      sources.fingerprint = 'two';
      await dashboard.refreshLocal();
      expect(gateOf(dashboard, 'quick')['stale'], isTrue);
    });

    test('listeners get the state as JSON when something changes', () async {
      final frames = <String>[];
      final sub = dashboard.updates.listen(frames.add);
      await dashboard.refreshLocal();
      await settle();
      await sub.cancel();
      expect(frames, isNotEmpty);
      expect(jsonDecode(frames.last), containsPair('release', '0.7.0'));
    });
  });

  group('server', () {
    late FakeSources sources;
    late Dashboard dashboard;
    late HttpServer server;
    late File page;
    final client = HttpClient();

    setUp(() async {
      sources = FakeSources();
      dashboard = dashboardOver(sources);
      page = File('${Directory.systemTemp.path}/dashboard_test_page.html')
        ..writeAsStringSync('<p>page</p>');
      server = await serveDashboard(dashboard, page: page, port: 0);
      await dashboard.refreshLocal();
    });
    tearDown(() async {
      await dashboard.close();
      await server.close(force: true);
      page.deleteSync();
    });
    tearDownAll(() => client.close(force: true));

    Future<HttpClientResponse> send(
      String method,
      String path, {
      Map<String, String> headers = const <String, String>{},
    }) async {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      headers.forEach(request.headers.set);
      return request.close();
    }

    test('listens on the loopback address only', () {
      expect(server.address.isLoopback, isTrue);
    });

    test('serves the page and the state', () async {
      final index = await send('GET', '/');
      expect(await utf8.decodeStream(index), contains('page'));
      final state = await send('GET', '/api/state');
      final body = jsonDecode(await utf8.decodeStream(state));
      expect(body, containsPair('release', '0.7.0'));
    });

    test('a POST without the header is refused and runs nothing', () async {
      final response = await send('POST', '/api/run/slow');
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.forbidden);
      await settle();
      expect(sources.ran, isNot(contains('slow')));
    });

    test('a request for another host is refused', () async {
      final response = await send(
        'POST',
        '/api/run/slow',
        headers: <String, String>{'host': 'evil.example', 'x-dashboard': '1'},
      );
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.forbidden);
    });

    test(
      'a POST with the header queues the gate; a repeat is a conflict',
      () async {
        sources.release = Completer<void>();
        final headers = <String, String>{'x-dashboard': '1'};
        final first = await send('POST', '/api/run/slow', headers: headers);
        await first.drain<void>();
        expect(first.statusCode, HttpStatus.accepted);
        final again = await send('POST', '/api/run/slow', headers: headers);
        await again.drain<void>();
        expect(again.statusCode, HttpStatus.conflict);
        final unknown = await send('POST', '/api/run/nope', headers: headers);
        await unknown.drain<void>();
        expect(unknown.statusCode, HttpStatus.notFound);
        sources.release!.complete();
      },
    );

    test('the event stream opens with the current state', () async {
      final response = await send('GET', '/events');
      final first = await response
          .transform(utf8.decoder)
          .firstWhere((chunk) => chunk.contains('event: state'));
      expect(first, contains('"release":"0.7.0"'));
    });
  });
}
