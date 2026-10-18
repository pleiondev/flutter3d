// Writes `api/kernel_language.vocabulary`, the kernel language's words one
// a line with the version each arrived in; `--check` only says whether the
// committed file is current.
//
//     dart run tool/kernel_vocabulary.dart [--check]
//
// The structure rule `a language's vocabulary grows only with its version`
// holds this file to the base recorded at the tag, and
// `test/kernel_vocabulary_test.dart` holds it to `kernel_words.dart`.
import 'dart:io';

import 'package:flutter3d_shaders/kernel.dart' show kernelLanguageVersion;
import 'package:flutter3d_shaders/src/kernel/kernel_words.dart';

/// Where the file lives, from the package's directory.
const String kernelVocabularyPath = 'api/kernel_language.vocabulary';

/// The first lines of every language's vocabulary file.
const String vocabularyHeader =
    '# A language\'s vocabulary, one fact a line, each ending in the version\n'
    '# it arrived in; "<language> version <N>" is the newest this build\n'
    '# reads. Generated; a line new since the base recorded at the tag\n'
    '# carries a version above the base\'s newest (the rule `a language\'s\n'
    '# vocabulary grows only with its version`).';

/// The kernel language's vocabulary: each word with its version, the words
/// taken before their version, and the other language's words the parser
/// names, which arrived with the language.
String kernelVocabularySnapshot() {
  final lines = <String>[
    'kernel version $kernelLanguageVersion',
    for (final MapEntry(key: word, value: since) in kernelWordVersions.entries)
      'kernel word $word $since',
    for (final word in kernelWordsReservedEarly)
      'kernel early $word ${kernelWordVersions[word]}',
    for (final word in kernelOtherLanguageWords) 'kernel other $word 1',
  ]..sort();
  return '$vocabularyHeader\n${lines.join('\n')}\n';
}

void main(List<String> args) {
  final file = File(kernelVocabularyPath);
  final text = kernelVocabularySnapshot();
  if (args.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync() != text) {
      stderr.writeln(
        '${file.path} is not what the language says; run '
        'dart run tool/kernel_vocabulary.dart',
      );
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('wrote ${file.path}');
}
