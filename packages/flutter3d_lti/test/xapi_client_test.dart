import 'dart:convert';

import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final lrs = XapiLrsConfig(
    statementsEndpoint: Uri.parse('https://lrs.example.test/xapi/statements'),
    authorizationHeader: 'Basic dGVzdDp0ZXN0',
  );

  XapiStatement checkStatement() => XapiStatement(
    actor: XapiActor.fromLtiSubject(
      name: 'Test Student',
      platformIssuer: 'https://platform.example.test',
      subject: 'student-42',
    ),
    verb: XapiVerb.answered,
    object: const XapiActivity(
      id: 'https://tool.example.test/lessons/engine-tour/quiz-steps',
      name: 'Torque spec check',
    ),
    result: const XapiResult(success: true, response: '80 Nm', scoreScaled: 1),
    timestamp: DateTime.utc(2026, 9, 15),
  );

  test('PUTs the statement to <endpoint>?statementId=<id>', () async {
    Uri? putUri;
    Map<String, String>? putHeaders;
    Map<String, dynamic>? putBody;

    final client = XapiClient(
      lrs: lrs,
      httpClient: MockClient((request) async {
        putUri = request.url;
        putHeaders = request.headers;
        putBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 204);
      }),
    );

    final statement = checkStatement();
    await client.send(statement);

    expect(putUri!.origin, lrs.statementsEndpoint.origin);
    expect(putUri!.path, lrs.statementsEndpoint.path);
    expect(putUri!.queryParameters['statementId'], statement.id);
    expect(putHeaders!['authorization'], 'Basic dGVzdDp0ZXN0');
    expect(putHeaders!['x-experience-api-version'], '1.0.3');
    expect(putBody, {
      'id': statement.id,
      'actor': {
        'objectType': 'Agent',
        'name': 'Test Student',
        'account': {
          'homePage': 'https://platform.example.test',
          'name': 'student-42',
        },
      },
      'verb': {
        'id': 'http://adlnet.gov/expapi/verbs/answered',
        'display': {'en': 'answered'},
      },
      'object': {
        'id': 'https://tool.example.test/lessons/engine-tour/quiz-steps',
        'objectType': 'Activity',
        'definition': {
          'name': {'en': 'Torque spec check'},
        },
      },
      'result': {
        'success': true,
        'response': '80 Nm',
        'score': {'scaled': 1},
      },
      'timestamp': '2026-09-15T00:00:00.000Z',
    });
  });

  test(
    'generates a fresh, spec-shaped UUID per statement when none is given',
    () {
      final a = checkStatement();
      final b = checkStatement();

      final uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(a.id, matches(uuidV4));
      expect(b.id, matches(uuidV4));
      expect(a.id, isNot(equals(b.id)));
    },
  );

  test('omits absent result fields rather than sending them as null', () {
    final statement = XapiStatement(
      actor: XapiActor.fromLtiSubject(
        name: 'Test Student',
        platformIssuer: 'https://platform.example.test',
        subject: 'student-42',
      ),
      verb: XapiVerb.completed,
      object: const XapiActivity(
        id: 'https://tool.example.test/lessons/engine-tour',
        name: 'Engine teardown',
      ),
    );

    expect(statement.toJson().containsKey('result'), isFalse);
  });

  test('throws XapiException when the LRS refuses the statement', () async {
    final client = XapiClient(
      lrs: lrs,
      httpClient: MockClient((request) async {
        return http.Response('bad request', 400);
      }),
    );

    await expectLater(
      client.send(checkStatement()),
      throwsA(isA<XapiException>()),
    );
  });
}
