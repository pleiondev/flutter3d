/// `edu-00` §10's `check` — a question and a short list of accepted answers
/// on an `edu_step` — read here for the first time anywhere in this tree.
/// `edu-01`'s own status note already flagged the gap: the panel can place a
/// `check` object as data, and nothing renders it or grades an answer. This
/// file is the renderer and the grader, not a second way to author one.
///
/// **Local only, on purpose.** `edu-00` §10 is explicit that the format does
/// not say where a result goes — "a local visible-to-the-teacher result" or
/// "an LTI/xAPI statement" both read the same `check` field. This file is
/// the first of those: enough to prove the question/attempts/reveal
/// mechanic against a real step, before `edu-03` gives a second host
/// anything to send.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef;

import 'lesson_theme.dart';

/// A `check` object, read once from a step's own properties.
final class CheckSpec {
  /// A check asking [question], accepting any of [answers], over
  /// [attempts] tries; [fromStep] is how a lesson builds one.
  const CheckSpec({
    required this.question,
    required this.answers,
    required this.attempts,
  });

  /// Null when [step] carries no `check` — most steps do not, and a step
  /// that names one incompletely (no question, or an empty answer list) is
  /// read as not carrying one either, rather than crashing a lesson over a
  /// typo in its own content.
  static CheckSpec? fromStep(EntityDef step) {
    final raw = step.properties['check'];
    if (raw is! Map) return null;
    final question = raw['question'];
    final rawAnswers = raw['answers'];
    if (question is! String || question.isEmpty) return null;
    if (rawAnswers is! List || rawAnswers.isEmpty) return null;
    final answers = <String>[
      for (final answer in rawAnswers)
        if (answer is String) answer,
    ];
    if (answers.isEmpty) return null;
    final attempts = raw['attempts'];
    return CheckSpec(
      question: question,
      answers: answers,
      attempts: attempts is num && attempts >= 1 ? attempts.toInt() : 1,
    );
  }

  /// What the student is asked, as the lesson wrote it.
  final String question;

  /// Every spelling the check takes as right; never empty. The first is the
  /// one shown when the attempts run out.
  final List<String> answers;

  /// How many tries the student gets; the answer is revealed once this many
  /// have been wrong. At least one, which is also what a check that names
  /// none gets.
  final int attempts;

  /// Case- and surrounding-whitespace-insensitive, the comparison `edu-00`
  /// §10 itself recommends ("снимает основную часть проблемы на уровне
  /// контента") rather than mandates — a lesson author who lists several
  /// spellings still gets exact matches on each of them, this just also
  /// forgives ` 80 нм ` for `80 нм`.
  bool accepts(String given) {
    final normalized = given.trim().toLowerCase();
    return answers.any((answer) => answer.trim().toLowerCase() == normalized);
  }
}

/// Where a [CheckPrompt] stands: asking, answered correctly, or out of
/// attempts and shown the answer.
enum CheckOutcome {
  /// Still waiting for a right answer, with attempts left.
  asking,

  /// Answered with one of [CheckSpec.answers].
  correct,

  /// Every attempt answered wrong; the text field is gone and the first of
  /// [CheckSpec.answers] is shown in its place.
  revealed,
}

/// A `check` widget: the question, a text field, and the attempts
/// `edu-00` §10 allows before revealing an accepted answer.
///
/// **Keyed by the caller to reset between steps.** This widget holds no
/// notion of *which* step it is answering — a fresh [CheckSpec] each build
/// is a fresh question as far as this widget is concerned, and a caller that
/// wants a new attempt counter on the next step supplies a `ValueKey` built
/// from the step's own name, the ordinary Flutter answer to "reset this
/// state when something outside it changes" rather than a second field here
/// to keep in step with the step index.
class CheckPrompt extends StatefulWidget {
  /// A prompt for [spec], starting with all of its attempts.
  const CheckPrompt({super.key, required this.spec});

  /// The question, its answers and how many tries it allows.
  final CheckSpec spec;

  @override
  State<CheckPrompt> createState() => _CheckPromptState();
}

class _CheckPromptState extends State<CheckPrompt> {
  final _controller = TextEditingController();
  CheckOutcome _outcome = CheckOutcome.asking;
  late int _remaining = widget.spec.attempts;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_outcome != CheckOutcome.asking) return;
    if (widget.spec.accepts(_controller.text)) {
      setState(() => _outcome = CheckOutcome.correct);
      return;
    }
    setState(() {
      _remaining -= 1;
      if (_remaining <= 0) _outcome = CheckOutcome.revealed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LessonTheme.scrim,
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.spec.question,
              style: const TextStyle(
                color: LessonTheme.text,
                fontSize: 16.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8.0),
            switch (_outcome) {
              CheckOutcome.asking => Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: LessonTheme.text),
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText:
                            'Ответ ($_remaining ${_attemptsWord(_remaining)})',
                        hintStyle: const TextStyle(color: LessonTheme.hint),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: LessonTheme.hint),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.check, color: LessonTheme.text),
                    tooltip: 'Submit answer',
                    onPressed: _submit,
                  ),
                ],
              ),
              // Live regions: the field a screen reader was in has gone, and
              // what took its place is the answer to what was just typed.
              CheckOutcome.correct => Semantics(
                liveRegion: true,
                child: const Text(
                  'Верно.',
                  style: TextStyle(
                    color: LessonTheme.correct,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CheckOutcome.revealed => Semantics(
                liveRegion: true,
                child: Text(
                  'Попытки кончились. Ответ: ${widget.spec.answers.first}',
                  style: const TextStyle(color: LessonTheme.revealed),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }

  static String _attemptsWord(int n) {
    // Only the shipped tour's own language needs a plural rule, and Russian
    // has three — few (2-4), many (0, 5+), and one — matched by the same
    // remainder test the language actually uses.
    if (n % 10 == 1 && n % 100 != 11) return 'попытка';
    if (<int>[2, 3, 4].contains(n % 10) &&
        !<int>[12, 13, 14].contains(n % 100)) {
      return 'попытки';
    }
    return 'попыток';
  }
}
