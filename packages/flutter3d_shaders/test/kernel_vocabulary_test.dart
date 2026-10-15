/// The kernel language's vocabulary file is what `kernel_words.dart` says.
///
///     dart test test/kernel_vocabulary_test.dart
library;

import 'dart:io';

import 'package:flutter3d_shaders/kernel.dart' show kernelLanguageVersion;
import 'package:test/test.dart';

import '../tool/kernel_vocabulary.dart';

void main() {
  test('api/kernel_language.vocabulary is what the language reads', () {
    // Mutation: add a word to `kernelWordVersions` without running
    // tool/kernel_vocabulary.dart, and the file is stale.
    expect(
      File(kernelVocabularyPath).readAsStringSync(),
      kernelVocabularySnapshot(),
      reason: 'run dart run tool/kernel_vocabulary.dart',
    );
  });

  test('every line ends in a version this build reads', () {
    final lines = kernelVocabularySnapshot()
        .split('\n')
        .where((String line) => line.isNotEmpty && !line.startsWith('#'));
    expect(lines, contains('kernel word atomicAdd 2'));
    for (final line in lines) {
      expect(
        int.parse(line.split(' ').last),
        inInclusiveRange(1, kernelLanguageVersion),
        reason: line,
      );
    }
  });
}
