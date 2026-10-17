import 'package:flutter3d_hub/flutter3d_hub.dart';
import 'package:test/test.dart';

const _uuid = '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90';
const _hash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// A server that answers from what it is given and remembers what it was
/// asked.
final class _FakeServer extends HubServer {
  _FakeServer({required this.hello_, this.model});

  final Map<String, Object?> hello_;
  final Map<String, Object?>? model;
  final List<Map<String, Object?>> asked = <Map<String, Object?>>[];

  @override
  Future<HubHello> hello(HubHelloRequest request) async {
    asked.add(request.toJson());
    return HubHello.fromJson(hello_);
  }

  @override
  Future<HubModel> resolve(HubResolveRequest request) async {
    asked.add(request.toJson());
    return HubModel.fromJson(model!);
  }
}

Map<String, Object?> _model({
  String protocol = '1.0',
  String uuid = _uuid,
  int version = 3,
  String sha256 = _hash,
}) => <String, Object?>{
  'protocol': protocol,
  'uuid': uuid,
  'version': version,
  'sha256': sha256,
  'bytes': 4096,
  'format': 'glb',
  'url': 'https://models.pleion.dev/files/$sha256',
  'license': 'CC-BY-4.0',
  'author': 'A. Modeller',
  'name': 'Chair',
};

HubEndpoint _endpoint(String name) =>
    HubProtocol.endpoints.firstWhere((HubEndpoint e) => e.name == name);

/// [json] holds every field [schema] requires and no field it does not name.
void _agrees(Map<String, Object?> json, Map<String, Object?> schema) {
  final properties = (schema['properties'] as Map?) ?? const {};
  for (final key in json.keys) {
    expect(properties.containsKey(key), isTrue, reason: '"$key" undeclared');
  }
  for (final key in (schema['required'] as List?) ?? const []) {
    expect(json.containsKey(key), isTrue, reason: '"$key" is required');
  }
}

void main() {
  group('the protocol version', () {
    test('this client speaks 1.0', () {
      expect(HubProtocol.version.toString(), '1.0');
    });

    test('reads every minor of its major and no other major', () {
      expect(HubProtocol.version.reads(const HubProtocolVersion(1, 7)), isTrue);
      expect(
        HubProtocol.version.reads(const HubProtocolVersion(2, 0)),
        isFalse,
      );
    });

    test('parses only <major>.<minor>', () {
      expect(
        HubProtocolVersion.tryParse('1.12'),
        const HubProtocolVersion(1, 12),
      );
      for (final bad in <String>['1', '1.0.0', '01.0', '1.01', 'v1.0', '']) {
        expect(HubProtocolVersion.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('every request carries the protocol version', () {
    test('hello', () {
      expect(const HubHelloRequest().toJson()['protocol'], '1.0');
    });

    test('resolve', () {
      final request = HubResolveRequest(HubReference.parse('$_uuid@3'));
      expect(request.toJson(), <String, Object?>{
        'protocol': '1.0',
        'reference': '$_uuid@3',
      });
    });
  });

  group('greet', () {
    test('takes a server of the same major and a newer minor', () async {
      final server = _FakeServer(
        hello_: <String, Object?>{
          'protocol': '1.4',
          'server': 'models.pleion.dev',
          'mirrors': <Object?>['https://mirror.example/models'],
          'motd': 'a field a later minor added',
        },
      );
      final hello = await HubProtocol.greet(server);
      expect(hello.protocol, const HubProtocolVersion(1, 4));
      expect(hello.mirrors, <Uri>[Uri.parse('https://mirror.example/models')]);
      expect(server.asked.single['protocol'], '1.0');
    });

    test('refuses another major with a sentence naming both', () async {
      final server = _FakeServer(
        hello_: <String, Object?>{'protocol': '2.0', 'server': 'next'},
      );
      await expectLater(
        HubProtocol.greet(server),
        throwsA(
          isA<HubRefusedException>()
              .having((e) => e.reason, 'reason', HubRefusal.protocol)
              .having((e) => e.message, 'message', contains('2.0'))
              .having((e) => e.message, 'message', contains('1.0'))
              .having((e) => e.message, 'message', endsWith('.')),
        ),
      );
    });

    test('refuses an answer with no protocol', () async {
      final server = _FakeServer(
        hello_: <String, Object?>{'server': 'models.pleion.dev'},
      );
      await expectLater(
        HubProtocol.greet(server),
        throwsA(
          isA<HubRefusedException>()
              .having((e) => e.reason, 'reason', HubRefusal.protocol)
              .having((e) => e.message, 'message', contains('"protocol"')),
        ),
      );
    });
  });

  group('resolve', () {
    test('reads the licence and the author', () async {
      final model = await HubProtocol.resolve(
        _FakeServer(hello_: const {}, model: _model()),
        HubReference.parse('$_uuid@3'),
      );
      expect(model.license, 'CC-BY-4.0');
      expect(model.author, 'A. Modeller');
      expect(model.pinned.toString(), '$_uuid@3#sha256=$_hash');
    });

    test('refuses an answer for another version', () async {
      await expectLater(
        HubProtocol.resolve(
          _FakeServer(hello_: const {}, model: _model(version: 4)),
          HubReference.parse('$_uuid@3'),
        ),
        throwsA(
          isA<HubRefusedException>().having(
            (e) => e.reason,
            'reason',
            HubRefusal.protocol,
          ),
        ),
      );
    });

    test('refuses a hash other than the reference says', () async {
      final other = 'a' * 64;
      await expectLater(
        HubProtocol.resolve(
          _FakeServer(
            hello_: const {},
            model: _model(sha256: other),
          ),
          HubReference.parse('$_uuid@3#sha256=$_hash'),
        ),
        throwsA(
          isA<HubRefusedException>().having(
            (e) => e.reason,
            'reason',
            HubRefusal.hashMismatch,
          ),
        ),
      );
    });

    test('refuses an answer without a licence', () {
      expect(
        () => HubModel.fromJson(_model()..remove('license')),
        throwsA(
          isA<HubRefusedException>().having(
            (e) => e.message,
            'message',
            contains('"license"'),
          ),
        ),
      );
    });
  });

  group('refusals on the wire', () {
    test('a known reason reads back as itself', () {
      final refused = hubRefusalFromJson(<String, Object?>{
        'protocol': '1.0',
        'reason': 'withdrawn',
        'message': 'The author withdrew this version.',
      });
      expect(refused.reason, HubRefusal.withdrawn);
      expect(refused.message, contains('The author withdrew this version.'));
    });

    test('a reason a later minor adds is still a refusal, in words', () {
      final refused = hubRefusalFromJson(<String, Object?>{
        'protocol': '1.3',
        'reason': 'quarantined',
        'message': 'Held for review.',
      });
      expect(refused.reason, HubRefusal.protocol);
      expect(refused.message, contains('quarantined'));
      expect(refused.message, contains('Held for review.'));
    });

    test('round-trips through hubRefusalToJson', () {
      const refused = HubRefusedException(
        HubRefusal.notFound,
        detail: 'No such model.',
      );
      final back = hubRefusalFromJson(hubRefusalToJson(refused));
      expect(back.reason, HubRefusal.notFound);
    });
  });

  group('the schema and the messages agree', () {
    test('there are the three exchanges', () {
      expect(
        <String>[for (final e in HubProtocol.endpoints) e.name],
        <String>['hello', 'resolve', 'refusal'],
      );
    });

    test('hello', () {
      _agrees(const HubHelloRequest().toJson(), _endpoint('hello').request);
      _agrees(
        HubHello(
          protocol: HubProtocol.version,
          server: 's',
          mirrors: <Uri>[Uri.parse('https://m.example')],
        ).toJson(),
        _endpoint('hello').response,
      );
    });

    test('resolve', () {
      _agrees(
        HubResolveRequest(HubReference.parse('$_uuid@3')).toJson(),
        _endpoint('resolve').request,
      );
      final model = HubModel.fromJson(_model());
      _agrees(model.toJson(), _endpoint('resolve').response);
      expect(HubModel.fromJson(model.toJson()).toJson(), model.toJson());
    });

    test('refusal', () {
      _agrees(
        hubRefusalToJson(const HubRefusedException(HubRefusal.offline)),
        _endpoint('refusal').response,
      );
    });

    test('the reference pattern accepts what the parser accepts', () {
      final pattern = RegExp(
        ((_endpoint('resolve').request['properties']! as Map)['reference']!
                as Map)['pattern']!
            as String,
      );
      expect(pattern.hasMatch('$_uuid@3'), isTrue);
      expect(pattern.hasMatch('$_uuid@3#sha256=$_hash'), isTrue);
      expect(pattern.hasMatch('$_uuid@03'), isFalse);
    });
  });
}
