/// The client side of sharing: the bundle a short code stands for, and
/// `RunService`, which sends it through whatever transport the game hands it.
///
///     dart test test/run_service_test.dart
///
/// The end-to-end half — this client against the reference server — is in
/// `cloud/server/test/`, which can depend on both.
///
/// Mutation: drop the level hash check from `ShareBundle` and a run recorded
/// in another version of the level is shared as if it fitted.
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Map<String, Object?> _level() => Level(name: 'yard').toJson();

Demo _run({String? levelHash, String? recordedBy}) => Demo(
  level: 'yard.json',
  levelHash: levelHash ?? contentDigestHex(_level()),
  start: const Snapshot(<String, Object?>{'x': 0}),
  tape: InputTape(seed: 3, frames: <InputFrame>[const InputFrame()]),
  buildStamp: 'test',
  checkpoints: DigestTrace(every: 1)..observe(1, 0),
  recordedBy: recordedBy,
);

/// A transport that writes down what it was asked and answers [status]
/// with [body].
final class _Wire {
  _Wire([this.status = 200, this.body = '{}']);

  final int status;
  final String body;
  final List<RunRequest> sent = <RunRequest>[];

  Future<RunResponse> call(RunRequest request) async {
    sent.add(request);
    return RunResponse(status, body);
  }
}

RunService _service(_Wire wire) =>
    RunService(base: Uri.parse('https://runs.example/'), transport: wire.call);

void main() {
  group('a share bundle', () {
    test('reads back what it wrote, hash and run included', () {
      final bundle = ShareBundle(
        game: 'walk',
        level: _level(),
        run: _run(),
        title: 'the yard',
      );

      final read = ShareBundle.fromJson(
        jsonDecode(jsonEncode(bundle.toJson())) as Map<String, Object?>,
      );

      expect(read.levelHash, bundle.levelHash);
      expect(read.title, 'the yard');
      expect(read.run!.steps, 1);
    });

    test('refuses a run recorded in another version of the level', () {
      expect(
        () => ShareBundle(
          game: 'walk',
          level: _level(),
          run: _run(levelHash: '00000000'),
        ),
        throwsA(
          isA<ShareFormatException>().having(
            (e) => e.message,
            'message',
            contains('00000000'),
          ),
        ),
      );
    });

    test('refuses a document whose level is not the one it names', () {
      final json = ShareBundle(game: 'walk', level: _level()).toJson();
      (json['level']! as Map<String, Object?>)['name'] = 'edited by hand';

      expect(
        () => ShareBundle.fromJson(json),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('refuses a newer format by saying so', () {
      final json = ShareBundle(game: 'walk', level: _level()).toJson()
        ..['version'] = 99;

      expect(
        () => ShareBundle.fromJson(json),
        throwsA(
          isA<ShareFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer build'),
          ),
        ),
      );
    });
  });

  group('the service', () {
    test('a share posts the bundle and answers with its code', () async {
      final wire = _Wire(
        201,
        '{"code":"ABCDEFG","address":"ff","status":"pending"}',
      );

      final answer = await _service(
        wire,
      ).share(ShareBundle(game: 'walk', level: _level(), run: _run()));

      final request = wire.sent.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://runs.example/v1/shares');
      expect(
        answer,
        isA<ServiceDone<SharedBundle>>()
            .having((d) => d.value.code, 'code', 'ABCDEFG')
            .having((d) => d.value.status, 'status', ShareStatus.pending),
      );
    });

    test('a status this build does not know is a refusal', () async {
      final answer = await _service(
        _Wire(201, '{"code":"ABCDEFG","address":"ff","status":"expired"}'),
      ).share(ShareBundle(game: 'walk', level: _level()));

      expect(answer, isA<ServiceRefused<SharedBundle>>());
    });

    test(
      'a code that is not open yet says so in the server\'s words',
      () async {
        final answer = await _service(
          _Wire(200, '{"status":"pending","message":"waiting for review"}'),
        ).open('ABCDEFG');

        expect(
          answer,
          isA<ServiceRefused<ShareBundle>>().having(
            (r) => r.reason,
            'reason',
            'waiting for review',
          ),
        );
      },
    );

    test('a report carries the reason to the code\'s own route', () async {
      final wire = _Wire(200, '{"message":"noted"}');

      await _service(wire).report('ABC DEF', 'not a level');

      final request = wire.sent.single;
      expect(
        request.uri.toString(),
        'https://runs.example/v1/shares/ABC%20DEF/reports',
      );
      expect(jsonDecode(request.body!), <String, Object?>{
        'reason': 'not a level',
      });
    });
  });

  group('the transport failing', () {
    test('an unreachable server is a refusal with a sentence', () async {
      final service = RunService(
        base: Uri.parse('https://runs.example/'),
        transport: (_) async => throw StateError('offline'),
      );

      final answer = await service.open('ABCDEFG');

      expect(
        answer,
        isA<ServiceRefused<ShareBundle>>().having(
          (r) => r.reason,
          'reason',
          contains('could not reach'),
        ),
      );
    });

    test('a reply that is not JSON is a refusal, not a throw', () async {
      final answer = await _service(
        _Wire(502, '<html>'),
      ).share(ShareBundle(game: 'walk', level: _level()));

      expect(
        answer,
        isA<ServiceRefused<SharedBundle>>().having(
          (r) => r.reason,
          'reason',
          contains('not JSON'),
        ),
      );
    });
  });
}
