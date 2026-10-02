/// The two ways a save leaves the device: a server over HTTP, and Play Games
/// or iCloud through the platform's side. Both answer; neither throws for a
/// reason the network gave.
///
///     flutter test test/cloud_save_stores_test.dart
library;

import 'package:flutter/services.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpCloudSaves', () {
    test('a slot is a resource under saves/<game>/', () async {
      final asked = <http.Request>[];
      final store = HttpCloudSaves(
        base: Uri.parse('https://example.test/api/'),
        game: 'platformer',
        headers: () async => <String, String>{'Authorization': 'Bearer t'},
        client: MockClient((request) async {
          asked.add(request);
          return http.Response('{}', 200, headers: {'etag': '"v1"'});
        }),
      );

      final fetched = await store.fetch('save.json');

      expect(
        asked.single.url.toString(),
        'https://example.test/api/saves/platformer/save.json',
      );
      expect(asked.single.headers['Authorization'], 'Bearer t');
      expect(fetched, isA<CloudDocument>());
      expect((fetched as CloudDocument).version, '"v1"');
    });

    test('nothing there is 404, and empty', () async {
      final store = HttpCloudSaves(
        base: Uri.parse('https://example.test'),
        game: 'g',
        client: MockClient((_) async => http.Response('', 404)),
      );

      expect(await store.fetch('save.json'), isA<CloudEmpty>());
    });

    test('a write is conditional on the version it replaces', () async {
      // Mutation: send no precondition. Two devices syncing at once both
      // write, and whichever lands second erases the other's run unseen.
      final asked = <http.Request>[];
      final store = HttpCloudSaves(
        base: Uri.parse('https://example.test'),
        game: 'g',
        client: MockClient((request) async {
          asked.add(request);
          return request.headers['If-Match'] == '"v1"' ||
                  request.headers['If-None-Match'] == '*'
              ? http.Response('', 204, headers: {'etag': '"v2"'})
              : http.Response('', 412);
        }),
      );

      final replaced = await store.put('s', '{}', replacing: '"v1"');
      final created = await store.put('s', '{}');
      final stale = await store.put('s', '{}', replacing: '"v0"');

      expect((replaced as CloudStored).version, '"v2"');
      expect(created, isA<CloudStored>());
      expect(asked[1].headers['If-None-Match'], '*');
      expect(asked[1].headers.containsKey('If-Match'), isFalse);
      expect(stale, isA<CloudMoved>());
    });

    test('a server that sends no ETag is refused, saying why', () async {
      // Mutation: accept the document with an empty version. The next write
      // then replaces whatever is there, which is the race the versions stop.
      final store = HttpCloudSaves(
        base: Uri.parse('https://example.test'),
        game: 'g',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final fetched = await store.fetch('s');

      expect(fetched, isA<CloudUnavailable>());
      expect((fetched as CloudUnavailable).reason, contains('ETag'));
    });

    test('a network that is down is an answer', () async {
      // Mutation: let the client's exception out. A launch with no network
      // then fails at the title card instead of saying the cloud is away.
      final store = HttpCloudSaves(
        base: Uri.parse('https://example.test'),
        game: 'g',
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(await store.fetch('s'), isA<CloudUnavailable>());
      expect(await store.put('s', '{}'), isA<CloudUnavailable>());
    });
  });

  group('PlatformCloudSaves', () {
    const channel = MethodChannel('flutter3d/cloud_saves');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'asks the platform with the provider, and reads its answers',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'fetch' => <String, Object?>{'document': '{}', 'version': 'r7'},
            _ => <String, Object?>{'version': 'r8'},
          };
        });
        final store = PlatformCloudSaves(CloudProvider.playGames);

        final fetched = await store.fetch('save.json');
        final put = await store.put('save.json', '{}', replacing: 'r7');

        expect((fetched as CloudDocument).version, 'r7');
        expect((put as CloudStored).version, 'r8');
        expect(calls.first.arguments, <String, Object?>{
          'provider': 'playGames',
          'slot': 'save.json',
        });
        expect((calls.last.arguments as Map)['replacing'], 'r7');
        expect(store.name, 'Play Games');
      },
    );

    test('nothing kept, and a lost race, are their own answers', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'fetch' => null,
          _ => <String, Object?>{'moved': true},
        },
      );
      final store = PlatformCloudSaves(CloudProvider.iCloud);

      expect(await store.fetch('s'), isA<CloudEmpty>());
      expect(await store.put('s', '{}'), isA<CloudMoved>());
    });

    test('a build without the platform side says so', () async {
      // Mutation: let `MissingPluginException` out. A build that offers
      // iCloud where it cannot reach it then crashes on the settings screen.
      final store = PlatformCloudSaves(CloudProvider.iCloud);

      final fetched = await store.fetch('s');

      expect(fetched, isA<CloudUnavailable>());
      expect(
        (fetched as CloudUnavailable).reason,
        'iCloud is not available in this build',
      );
    });

    test('a refusal from the service names it', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'SIGN_IN_REQUIRED',
          message: 'not signed in to Play Games',
        ),
      );
      final store = PlatformCloudSaves(CloudProvider.playGames);

      final put = await store.put('s', '{}');

      expect((put as CloudUnavailable).reason, contains('not signed in'));
    });
  });
}
