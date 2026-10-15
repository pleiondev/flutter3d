// Writes `api/wasm_abi.vocabulary`, what a Wasm module and the engine agree
// on by name, one a line with the ABI each arrived in; `--check` only says
// whether the committed file is current.
//
//     dart run tool/wasm_vocabulary.dart [--check]
//
// The structure rule `a language's vocabulary grows only with its version`
// holds this file to the base recorded at the tag: an import added under
// the newest ABI a 1.0 host runs would be one a 1.0 module could import and
// a 1.0 host refuse by name. `test/wasm_vocabulary_test.dart` holds it to
// `wasmImportSince`.
import 'dart:io';

import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart'
    show wasmImportSince, wasmPluginAbiMax, wasmPluginAbiMin;

/// Where the file lives, from the package's directory.
const String wasmVocabularyPath = 'api/wasm_abi.vocabulary';

/// The exports a host calls, by the ABI each arrived in. `f3d_abi` says
/// which ABI a module was written for, `f3d_step` steps it.
const Map<String, int> wasmExportSince = <String, int>{
  'f3d_abi': 1,
  'f3d_step': 1,
};

/// The first lines of every language's vocabulary file.
const String vocabularyHeader =
    '# A language\'s vocabulary, one fact a line, each ending in the version\n'
    '# it arrived in; "<language> version <N>" is the newest this build\n'
    '# reads. Generated; a line new since the base recorded at the tag\n'
    '# carries a version above the base\'s newest (the rule `a language\'s\n'
    '# vocabulary grows only with its version`).';

/// The Wasm plugin ABI's vocabulary: the module every import comes from,
/// each import and export with its ABI, and the oldest ABI a host runs,
/// which stays 1 through 1.x.
String wasmVocabularySnapshot() {
  final lines = <String>[
    'wasm version $wasmPluginAbiMax',
    'wasm minimum $wasmPluginAbiMin',
    for (final MapEntry(key: name, value: since) in wasmImportSince.entries)
      'wasm import f3d $name $since',
    for (final MapEntry(key: name, value: since) in wasmExportSince.entries)
      'wasm export $name $since',
  ]..sort();
  return '$vocabularyHeader\n${lines.join('\n')}\n';
}

void main(List<String> args) {
  final file = File(wasmVocabularyPath);
  final text = wasmVocabularySnapshot();
  if (args.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync() != text) {
      stderr.writeln(
        '${file.path} is not what the ABI says; run '
        'dart run tool/wasm_vocabulary.dart',
      );
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('wrote ${file.path}');
}
