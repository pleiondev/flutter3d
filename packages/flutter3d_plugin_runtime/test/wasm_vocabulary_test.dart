/// The Wasm plugin ABI's vocabulary file is what the host reads.
///
///     dart test test/wasm_vocabulary_test.dart
library;

import 'dart:io';

import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart'
    show wasmPluginAbiMax;
import 'package:test/test.dart';

import '../tool/wasm_vocabulary.dart';

void main() {
  test('api/wasm_abi.vocabulary is what the host reads', () {
    // Mutation: add an import to `wasmImportSince` without running
    // tool/wasm_vocabulary.dart, and the file is stale.
    expect(
      File(wasmVocabularyPath).readAsStringSync(),
      wasmVocabularySnapshot(),
      reason: 'run dart run tool/wasm_vocabulary.dart',
    );
  });

  test('every import and export arrived in an ABI this host runs', () {
    final lines = wasmVocabularySnapshot()
        .split('\n')
        .where((String line) => line.isNotEmpty && !line.startsWith('#'));
    expect(lines, contains('wasm import f3d field_frac 2'));
    expect(lines, contains('wasm minimum 1'));
    for (final line in lines) {
      expect(
        int.parse(line.split(' ').last),
        inInclusiveRange(1, wasmPluginAbiMax),
        reason: line,
      );
    }
  });
}
