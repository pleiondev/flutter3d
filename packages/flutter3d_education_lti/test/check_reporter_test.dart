import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_education/flutter3d_education.dart';
import 'package:flutter3d_education_lti/flutter3d_education_lti.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/test_platform.dart';
import 'support/test_rsa_key_pair.dart';

const _lineItem = 'https://platform.example.test/lineitems/7';

LtiLaunchClaims _launch({
  String? lineItem = _lineItem,
  List<String> scopes = const <String>[CheckReporter.scoreScope],
}) => LtiLaunchClaims(
  subject: 'student-42',
  deploymentId: 'deployment-1',
  messageType: LtiMessageType.resourceLinkRequest,
  targetLinkUri: 'https://tool.example.test/lessons/pendulum',
  roles: const <String>[],
  resourceLinkId: 'link-1',
  contextId: 'course-1',
  agsLineItemUrl: lineItem,
  agsScopes: scopes,
  raw: const <String, dynamic>{'name': 'Test Student'},
);

/// A platform and a record store in one: what each was sent.
final class _Platform {
  _Platform({this.scoresStatus = 204, this.statementsStatus = 204});

  final int scoresStatus;
  final int statementsStatus;
  final List<Map<String, dynamic>> scores = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> statements = <Map<String, dynamic>>[];

  late final TestPlatform platform = TestPlatform();

  late final http.Client http_ = MockClient((request) async {
    if (request.url == platform.config.authTokenUrl) {
      return http.Response(
        jsonEncode(<String, Object?>{'access_token': 't', 'expires_in': 3600}),
        200,
      );
    }
    if (request.url.toString() == '$_lineItem/scores') {
      scores.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('', scoresStatus);
    }
    if (request.url.path == '/xapi/statements') {
      statements.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('', statementsStatus);
    }
    return http.Response('not found', 404);
  });

  AgsClient grades() {
    final pair = generateTestRsaKeyPair();
    return AgsClient(
      platform: platform.config,
      credentials: LtiToolCredentials(
        clientId: platform.config.clientId,
        kid: 'tool-key-1',
        privateKey: pair.privateKey,
        publicKey: pair.publicKey,
      ),
      httpClient: http_,
    );
  }

  XapiClient records() => XapiClient(
    lrs: XapiLrsSettings(
      statementsEndpoint: Uri.parse('https://lrs.example.test/xapi/statements'),
      authorizationHeader: 'Basic dGVzdDp0ZXN0',
    ),
    httpClient: http_,
  );
}

void main() {
  final pendulum = ExperimentDocument.parse(
    File(
      '../flutter3d_education/test/fixtures/v1/pendulum.f3d.experiment',
    ).readAsStringSync(),
  );
  final question = pendulum.step('shorten')!.check!;

  test('an answer to the pendulum is stated, and settling it grades the '
      'lesson', () async {
    final platform = _Platform();
    final reporter = CheckReporter.forExperiment(
      pendulum,
      launch: _launch(),
      platformIssuer: 'https://platform.example.test',
      activityId: 'https://tool.example.test/lessons/pendulum',
      grades: platform.grades(),
      statements: platform.records(),
    );
    expect(reporter.questions, <String>['shorten']);

    final wrong = await reporter.record(
      CheckAnswer(
        id: 'shorten',
        question: question,
        response: 'doubled',
        attempt: 1,
      ),
    );
    expect(wrong.stated, isTrue);
    expect(wrong.graded, isFalse, reason: 'a second attempt is left');
    expect(platform.scores, isEmpty);
    expect(platform.statements.single['result'], <String, Object?>{
      'success': false,
      'response': 'doubled',
      'score': <String, Object?>{'scaled': 0.0},
    });

    final right = await reporter.record(
      CheckAnswer(
        id: 'shorten',
        question: question,
        response: ' Halved',
        attempt: 2,
      ),
    );
    expect(right.graded, isTrue);
    expect(right.stated, isTrue);
    expect(right.failures, isEmpty);
    expect(platform.statements, hasLength(2));
    expect(
      platform.statements.last,
      containsPair(
        'object',
        containsPair(
          'id',
          'https://tool.example.test/lessons/pendulum/shorten',
        ),
      ),
    );
    expect(
      platform.statements.last,
      containsPair('actor', containsPair('name', 'Test Student')),
    );
    final score = platform.scores.single;
    expect(score['userId'], 'student-42');
    expect(score['scoreGiven'], 1);
    expect(score['scoreMaximum'], 1);
    expect(score['activityProgress'], 'Completed');
    expect(score['gradingProgress'], 'FullyGraded');
  });

  test('the score counts the whole lesson and stays in progress until '
      'every question is settled', () async {
    final platform = _Platform();
    final reporter = CheckReporter(
      launch: _launch(),
      platformIssuer: 'https://platform.example.test',
      activityId: 'https://tool.example.test/lessons/tour',
      questions: const <String>['a', 'b'],
      grades: platform.grades(),
    );
    await reporter.record(
      CheckAnswer(id: 'a', question: question, response: 'half', attempt: 1),
    );
    expect(platform.scores.last['scoreGiven'], 1);
    expect(platform.scores.last['scoreMaximum'], 2);
    expect(platform.scores.last['activityProgress'], 'InProgress');
    expect(platform.scores.last['gradingProgress'], 'Pending');
    await reporter.record(
      CheckAnswer(id: 'b', question: question, response: 'no', attempt: 2),
    );
    expect(platform.scores.last['scoreGiven'], 1);
    expect(platform.scores.last['activityProgress'], 'Completed');
    expect(reporter.settled, 2);
    expect(reporter.correct, 1);
  });

  test('a launch with no line item or no score scope is not graded, and '
      'says why', () async {
    for (final launch in <LtiLaunchClaims>[
      _launch(lineItem: null),
      _launch(scopes: const <String>[]),
    ]) {
      final platform = _Platform();
      final delivery =
          await CheckReporter(
            launch: launch,
            platformIssuer: 'https://platform.example.test',
            activityId: 'https://tool.example.test/lessons/tour',
            questions: const <String>['a'],
            grades: platform.grades(),
          ).record(
            CheckAnswer(
              id: 'a',
              question: question,
              response: 'half',
              attempt: 1,
            ),
          );
      expect(delivery.graded, isFalse);
      expect(platform.scores, isEmpty);
      expect(delivery.skipped, hasLength(2));
    }
  });

  test('a refusing gradebook is reported, not thrown', () async {
    final platform = _Platform(scoresStatus: 403, statementsStatus: 500);
    final delivery =
        await CheckReporter(
          launch: _launch(),
          platformIssuer: 'https://platform.example.test',
          activityId: 'https://tool.example.test/lessons/tour',
          questions: const <String>['a'],
          grades: platform.grades(),
          statements: platform.records(),
        ).record(
          CheckAnswer(
            id: 'a',
            question: question,
            response: 'half',
            attempt: 1,
          ),
        );
    expect(delivery.graded, isFalse);
    expect(delivery.stated, isFalse);
    expect(delivery.failures, hasLength(2));
    expect(delivery.failures.first, isA<XapiException>());
    expect(delivery.failures.last, isA<AgsException>());
  });

  test('refuses a question the lesson does not ask, and one settled', () async {
    final reporter = CheckReporter(
      launch: _launch(),
      platformIssuer: 'https://platform.example.test',
      activityId: 'https://tool.example.test/lessons/tour',
      questions: const <String>['a'],
    );
    expect(
      () => reporter.record(
        CheckAnswer(id: 'z', question: question, response: 'half', attempt: 1),
      ),
      throwsArgumentError,
    );
    await reporter.record(
      CheckAnswer(id: 'a', question: question, response: 'half', attempt: 1),
    );
    expect(
      () => reporter.record(
        CheckAnswer(id: 'a', question: question, response: 'half', attempt: 2),
      ),
      throwsArgumentError,
    );
    expect(
      () => CheckAnswer(id: 'a', question: question, response: 'x', attempt: 3),
      throwsArgumentError,
    );
  });

  test('a lesson level asks the questions its steps carry', () {
    EntityDef step(String? name, Object? check) => EntityDef(
      type: 'edu_step',
      name: name,
      properties: <String, Object?>{'check': ?check},
    );
    final reporter = CheckReporter.forLesson(
      <EntityDef>[
        step('intro', null),
        step('torque', <String, Object?>{
          'question': 'What torque?',
          'answers': <Object?>['80 Nm'],
        }),
        step('typo', <String, Object?>{'question': 'No answers'}),
        step(null, <String, Object?>{
          'question': 'Nameless',
          'answers': <Object?>['x'],
        }),
      ],
      launch: _launch(),
      platformIssuer: 'https://platform.example.test',
      activityId: 'https://tool.example.test/lessons/tour',
    );
    expect(reporter.questions, <String>['torque']);
  });

  test('a lesson step carries the same question, read leniently', () {
    expect(
      CheckQuestion.fromStepProperties(<String, Object?>{
        'check': <String, Object?>{
          'question': 'Which way?',
          'answers': <Object?>['left', 3, ''],
          'attempts': 0,
        },
      })!.toJson(),
      <String, Object?>{
        'question': 'Which way?',
        'answers': <String>['left'],
      },
    );
    expect(
      CheckQuestion.fromStepProperties(<String, Object?>{
        'check': <String, Object?>{'question': 'Which way?'},
      }),
      isNull,
    );
  });
}
