import 'package:flutter3d_education/experiment.dart'
    show CheckQuestion, ExperimentDocument;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef;

import 'ags_client.dart';
import 'ags_exception.dart';
import 'ags_score.dart';
import 'lti_launch_claims.dart';
import 'xapi_client.dart';
import 'xapi_exception.dart';
import 'xapi_statement.dart';

/// One answer a student gave to a [CheckQuestion].
final class CheckAnswer {
  /// The answer [response] to [question], asked as [id], on the student's
  /// [attempt]th try (from 1). Throws an [ArgumentError] for an attempt
  /// below 1 or past the question's own count.
  CheckAnswer({
    required this.id,
    required this.question,
    required this.response,
    required this.attempt,
  }) : correct = question.accepts(response) {
    if (attempt < 1 || attempt > question.attempts) {
      throw ArgumentError.value(
        attempt,
        'attempt',
        'outside the ${question.attempts} the question allows',
      );
    }
  }

  /// The question's name in its lesson or experiment: the step that asks
  /// it. What a gradebook counts it under and what the xAPI activity is
  /// named after.
  final String id;

  final CheckQuestion question;

  /// What the student wrote.
  final String response;

  /// Which try this is, from 1.
  final int attempt;

  /// Whether [question] accepts [response].
  final bool correct;

  /// Whether the question is settled by this answer: answered right, or
  /// out of attempts.
  bool get settles => correct || attempt == question.attempts;
}

/// What [CheckReporter.record] got to the learning platform.
final class CheckDelivery {
  const CheckDelivery({
    required this.graded,
    required this.stated,
    this.skipped = const <String>[],
    this.failures = const <ResourceException>[],
  });

  /// Whether a score reached the gradebook through AGS.
  final bool graded;

  /// Whether an xAPI statement reached the record store.
  final bool stated;

  /// Why a destination was not tried, one sentence each: no grading was
  /// granted to this launch, an answer that does not settle its question
  /// yet, no record store configured.
  final List<String> skipped;

  /// What a destination refused: an [AgsException] or an [XapiException]
  /// with the platform's own text. A refusal is reported here and not
  /// thrown, so a student's lesson goes on when a gradebook is down.
  final List<ResourceException> failures;
}

/// The wire from a lesson's `check` questions to a learning platform: each
/// answer becomes an xAPI `answered` statement, and each question an answer
/// settles updates the student's score in the platform's gradebook
/// through LTI Assignment and Grade Services.
///
/// **One score for the lesson, not one per question.** A launch carries one
/// line item, so the score posted is the questions answered right out of
/// all the lesson asks ([questions]), `InProgress` until every question is
/// settled and `Completed` then; the gradebook shows the latest, which is
/// always the whole lesson so far.
///
/// **Either destination may be absent.** A launch without an AGS claim, or
/// without the score scope, is a lesson nobody grades: [record] skips the
/// gradebook and says so. No [statements] client is a lesson nobody
/// records. Neither stops the lesson.
final class CheckReporter {
  /// A reporter for the student [launch] names, on the platform whose
  /// issuer is [platformIssuer], for a lesson asking [questions] (their
  /// ids, each once), with [activityId] the URI the lesson's xAPI
  /// activities are named under. Throws an [ArgumentError] for no
  /// questions or a repeated id.
  CheckReporter({
    required this.launch,
    required this.platformIssuer,
    required this.activityId,
    required List<String> questions,
    this.grades,
    this.statements,
  }) : questions = List<String>.unmodifiable(questions) {
    if (questions.isEmpty) {
      throw ArgumentError.value(questions, 'questions', 'none');
    }
    if (questions.toSet().length != questions.length) {
      throw ArgumentError.value(questions, 'questions', 'an id repeats');
    }
  }

  /// A reporter for [experiment]'s questions: every step that asks one, by
  /// the step's name.
  factory CheckReporter.forExperiment(
    ExperimentDocument experiment, {
    required LtiLaunchClaims launch,
    required String platformIssuer,
    required String activityId,
    AgsClient? grades,
    XapiClient? statements,
  }) => CheckReporter(
    launch: launch,
    platformIssuer: platformIssuer,
    activityId: activityId,
    questions: <String>[
      for (final step in experiment.steps)
        if (step.check != null) step.name,
    ],
    grades: grades,
    statements: statements,
  );

  /// A reporter for a lesson level's questions: every `edu_step` in
  /// [steps] (as `orderedSteps` gives them) whose `check` reads as a
  /// question, by the step's name. A step without a name cannot be
  /// answered for, and is left out.
  factory CheckReporter.forLesson(
    List<EntityDef> steps, {
    required LtiLaunchClaims launch,
    required String platformIssuer,
    required String activityId,
    AgsClient? grades,
    XapiClient? statements,
  }) => CheckReporter(
    launch: launch,
    platformIssuer: platformIssuer,
    activityId: activityId,
    questions: <String>[
      for (final step in steps)
        if (step.name case final String name
            when CheckQuestion.fromStepProperties(step.properties) != null)
          name,
    ],
    grades: grades,
    statements: statements,
  );

  /// The AGS scope a launch must grant for a score to be posted.
  static const String scoreScope =
      'https://purl.imsglobal.org/spec/lti-ags/scope/score';

  /// The verified launch: who the student is and where the score goes.
  final LtiLaunchClaims launch;

  /// The platform's issuer, which the xAPI actor's account is scoped to.
  final String platformIssuer;

  /// The lesson's activity URI; a question is `<activityId>/<id>`.
  final String activityId;

  /// Every question the lesson asks, by id.
  final List<String> questions;

  /// The gradebook's client, or null for none.
  final AgsClient? grades;

  /// The record store's client, or null for none.
  final XapiClient? statements;

  final Map<String, bool> _settled = <String, bool>{};

  /// How many questions are settled, right or not.
  int get settled => _settled.length;

  /// How many questions were answered right.
  int get correct => _settled.values.where((right) => right).length;

  /// Sends [answer]: a statement for every answer, and the lesson's score
  /// when [answer] settles its question. Throws an [ArgumentError] for a
  /// question this lesson does not ask, or one already settled.
  Future<CheckDelivery> record(CheckAnswer answer) async {
    if (!questions.contains(answer.id)) {
      throw ArgumentError.value(answer.id, 'answer', 'not a question here');
    }
    if (_settled.containsKey(answer.id)) {
      throw ArgumentError.value(answer.id, 'answer', 'already settled');
    }
    if (answer.settles) _settled[answer.id] = answer.correct;

    final skipped = <String>[];
    final failures = <ResourceException>[];

    var stated = false;
    if (statements case final XapiClient client) {
      try {
        await client.send(_statement(answer));
        stated = true;
      } on ResourceException catch (refusal) {
        failures.add(refusal);
      }
    } else {
      skipped.add('no record store is configured');
    }

    var graded = false;
    final lineItem = launch.agsLineItemUrl;
    if (!answer.settles) {
      skipped.add(
        'the answer to "${answer.id}" does not settle it, so the score '
        'stands',
      );
    } else if (grades == null) {
      skipped.add('no gradebook client is configured');
    } else if (lineItem == null) {
      skipped.add('the launch carries no line item to grade');
    } else if (!launch.agsScopes.contains(scoreScope)) {
      skipped.add('the launch was not granted the score scope');
    } else {
      try {
        await grades!.submitScore(_score(), lineItemUrl: lineItem);
        graded = true;
      } on ResourceException catch (refusal) {
        failures.add(refusal);
      }
    }

    return CheckDelivery(
      graded: graded,
      stated: stated,
      skipped: List<String>.unmodifiable(skipped),
      failures: List<ResourceException>.unmodifiable(failures),
    );
  }

  AgsScore _score() {
    final complete = settled == questions.length;
    return AgsScore(
      userId: launch.subject,
      scoreGiven: correct,
      scoreMaximum: questions.length,
      activityProgress: complete
          ? AgsActivityProgress.completed
          : AgsActivityProgress.inProgress,
      gradingProgress: complete
          ? AgsGradingProgress.fullyGraded
          : AgsGradingProgress.pending,
    );
  }

  XapiStatement _statement(CheckAnswer answer) => XapiStatement(
    actor: XapiActor.fromLtiSubject(
      name: switch (launch.raw['name']) {
        final String name when name.isNotEmpty => name,
        _ => launch.subject,
      },
      platformIssuer: platformIssuer,
      subject: launch.subject,
    ),
    verb: XapiVerb.answered,
    object: XapiActivity(
      id: '$activityId/${Uri.encodeComponent(answer.id)}',
      name: answer.question.question,
    ),
    result: XapiResult(
      success: answer.correct,
      response: answer.response,
      scoreScaled: answer.correct ? 1.0 : 0.0,
    ),
  );
}
