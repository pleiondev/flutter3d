import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show DocumentFormatException;

/// A question a lesson step or an experiment step asks: the text, the
/// answers accepted, and how many attempts a student has before an
/// accepted answer is shown.
///
/// **One shape for both documents.** An `edu_step` entity carries it under
/// `check`, and a step of an `f3d.experiment` scenario carries it under the
/// same key, so the viewer that asks it and the wire that reports the
/// answer to a learning platform read one type.
final class CheckQuestion {
  /// A question with at least one accepted answer and at least one
  /// attempt. Throws an [ArgumentError] otherwise.
  CheckQuestion({
    required this.question,
    required List<String> answers,
    this.attempts = 1,
  }) : answers = List<String>.unmodifiable(answers) {
    if (question.isEmpty) {
      throw ArgumentError.value(question, 'question', 'empty');
    }
    if (answers.isEmpty) {
      throw ArgumentError.value(answers, 'answers', 'none accepted');
    }
    if (attempts < 1) {
      throw ArgumentError.value(attempts, 'attempts', 'fewer than one');
    }
  }

  /// The question [properties] carries under `check`, or null when it
  /// carries none or one without a question or an accepted answer.
  ///
  /// The lenient reading, for a lesson authored by hand and read at run
  /// time: a step with a typo in its question is a step without one, not a
  /// lesson that stops. [fromJson] is the strict one a document reader uses.
  static CheckQuestion? fromStepProperties(Map<String, Object?> properties) {
    final raw = properties['check'];
    if (raw is! Map) return null;
    final question = raw['question'];
    final answers = switch (raw['answers']) {
      final List<Object?> list => <String>[
        for (final answer in list)
          if (answer is String && answer.trim().isNotEmpty) answer,
      ],
      _ => const <String>[],
    };
    if (question is! String || question.isEmpty || answers.isEmpty) {
      return null;
    }
    final attempts = raw['attempts'];
    return CheckQuestion(
      question: question,
      answers: answers,
      attempts: attempts is num && attempts >= 1 ? attempts.toInt() : 1,
    );
  }

  /// Reads what [toJson] wrote. Throws a [DocumentFormatException] naming
  /// what is wrong.
  factory CheckQuestion.fromJson(Object? json) {
    Never wrong(String what) =>
        throw DocumentFormatException('a check question $what');
    if (json is! Map) wrong('is not an object');
    final question = json['question'];
    if (question is! String || question.isEmpty) wrong('has no question');
    final answers = json['answers'];
    if (answers is! List ||
        answers.isEmpty ||
        answers.any((a) => a is! String)) {
      wrong('"$question" has no list of accepted answers');
    }
    final attempts = json['attempts'] ?? 1;
    if (attempts is! int || attempts < 1) {
      wrong('"$question" has attempts that are not a whole number above 0');
    }
    return CheckQuestion(
      question: question,
      answers: answers.cast<String>(),
      attempts: attempts,
    );
  }

  /// What the student is asked.
  final String question;

  /// Every answer accepted, as the author wrote it.
  final List<String> answers;

  /// How many answers a student may give before an accepted one is shown.
  /// A count, at least 1.
  final int attempts;

  /// Whether [given] is one of [answers], ignoring case and the white space
  /// around it: ` 80 нм ` is `80 нм`.
  bool accepts(String given) {
    final normalized = given.trim().toLowerCase();
    return answers.any((answer) => answer.trim().toLowerCase() == normalized);
  }

  /// The question as an experiment step's `check` writes it, without
  /// `attempts` when it is one.
  Map<String, Object?> toJson() => <String, Object?>{
    'question': question,
    'answers': answers,
    if (attempts != 1) 'attempts': attempts,
  };
}
