// Writes `api/material_language.vocabulary`, the material language's words
// one a line with the version each arrived in; `--check` only says whether
// the committed file is current.
//
//     dart run tool/material_vocabulary.dart [--check]
//
// The API snapshot writes `materialInputs = …` for a list too long to show,
// and the names a source cannot bind are private to the parser, so a word
// added in a minor under the current version passed every check. The
// structure rule `a language's vocabulary grows only with its version`
// holds this file to the base recorded at the tag:
// `test/formats/material_vocabulary_test.dart` holds it to the language.
import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/src/formats/material_language/material_words.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ExpressionType;

/// Where the file lives, from the package's directory.
const String materialVocabularyPath = 'api/material_language.vocabulary';

/// The material language's vocabulary, one fact a line, each ending in the
/// version it arrived in, sorted; `f3dmat version <N>` is the newest this
/// build reads.
String materialVocabularySnapshot() {
  // A name taken in two lists keeps the version it was first taken in.
  final reserved = <(String, String), int>{};
  void reserve(String scope, Iterable<String> names, int since) {
    for (final name in names) {
      reserved.update(
        (scope, name),
        (int had) => had < since ? had : since,
        ifAbsent: () => since,
      );
    }
  }

  reserve('every', materialEmitterNames, 1);
  reserve('every', materialTextureBindings, 1);
  reserve('every', materialGlslWords, 1);
  reserve('every', materialVersion2ReservedNames, 2);
  reserve('every', materialVersion3ReservedNames, 3);
  reserve('vertex', materialVertexReservedNames, 2);
  reserve('vertex', materialVariantReservedNames, 3);

  final inputLists = <String, List<MaterialInput>>{
    'surface': materialInputs,
    'light': <MaterialInput>[
      ...materialLightInputs,
      materialStandardLightInput,
    ],
    'lit': const <MaterialInput>[materialLitInput],
    'scene': materialSceneInputs,
    'vertex': materialVertexInputs,
    'ambient': materialAmbientInputs,
    'composite': materialCompositeInputs,
    'fullscreen': materialFullscreenInputs,
    'compute': materialComputeInputs,
  };
  final lines = <String>[
    'f3dmat version $materialLanguageVersion',
    for (final MapEntry(key: word, value: since)
        in materialWordVersions.entries)
      'f3dmat word $word $since',
    for (final blend in MaterialBlend.all)
      'f3dmat blend ${blend.name} ${materialWordVersions['blend']}',
    for (final compare in materialDepthCompares)
      'f3dmat depthCompare $compare ${materialWordVersions['depthCompare']}',
    for (final MapEntry(key: list, value: inputs) in inputLists.entries)
      for (final input in inputs)
        'f3dmat input $list ${input.name} ${input.type} ${input.since}',
    for (final output in materialVertexOutputs)
      'f3dmat output vertex ${output.name} ${output.type} ${output.since}',
    for (final output in materialSurfaceOutputs)
      'f3dmat output surface ${output.name} ${output.type} ${output.since}',
    [
      'f3dmat lighting',
      materialStandardLighting,
      materialWordVersions['lighting'],
    ].join(' '),
    for (final builtin in materialBuiltins)
      'f3dmat builtin ${builtin.name} ${materialBuiltinVersions[builtin.name]}',
    for (final type in ExpressionType.numeric.values) 'f3dmat type $type 1',
    for (final binding in materialTextureBindings) 'f3dmat binding $binding 1',
    for (final block in materialReservedBlockNames) 'f3dmat block $block 1',
    for (final MapEntry(key: (scope, name), value: since) in reserved.entries)
      'f3dmat reserved $scope $name $since',
    for (final MapEntry(key: prefix, value: since)
        in materialReservedPrefixes.entries)
      'f3dmat prefix $prefix $since',
  ]..sort();
  return '$vocabularyHeader\n${lines.join('\n')}\n';
}

/// The first lines of every language's vocabulary file.
const String vocabularyHeader =
    '# A language\'s vocabulary, one fact a line, each ending in the version\n'
    '# it arrived in; "<language> version <N>" is the newest this build\n'
    '# reads. Generated; a line new since the base recorded at the tag\n'
    '# carries a version above the base\'s newest (the rule `a language\'s\n'
    '# vocabulary grows only with its version`).';

void main(List<String> args) {
  final file = File(materialVocabularyPath);
  final text = materialVocabularySnapshot();
  if (args.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync() != text) {
      stderr.writeln(
        '${file.path} is not what the language says; run '
        'dart run tool/material_vocabulary.dart',
      );
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('wrote ${file.path}');
}
