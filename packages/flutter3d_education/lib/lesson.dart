/// Reading a lesson out of a level: the `edu_sequence` and `edu_step`
/// entities a lesson is written as, in the order a viewer plays them
/// ([orderedSteps], [firstLessonSteps]). The question a step asks is
/// [CheckQuestion], in `experiment.dart`.
///
/// What a lesson viewer needs and an editor also uses, so neither depends
/// on the other for it. Plain Dart.
library;

import 'experiment.dart' show CheckQuestion;

export 'src/lesson/lesson_steps.dart';
