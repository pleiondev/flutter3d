/// The material language's vocabulary file is what the language reads, and
/// the words it records are taken where it says: GLSL's in every version,
/// a later version's only from that version.
///
///     dart test test/formats/material_vocabulary_test.dart
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/src/formats/material_language/material_words.dart';
import 'package:test/test.dart';

import '../../tool/material_vocabulary.dart';

/// A surface of [version] whose fragment body binds [name].
String _letting(int version, String name) =>
    '''
f3dmat $version
material Named {
  fragment {
    let $name = 1.0;
    return vec4(albedo * $name, alpha);
  }
}
''';

/// A surface of [version] with a uniform of its own called [name].
String _uniform(int version, String name) =>
    '''
f3dmat $version
material Named {
  uniform float $name = 1.0;
  fragment {
    return vec4(albedo * $name, alpha);
  }
}
''';

void main() {
  test('api/material_language.vocabulary is what the language reads', () {
    // Mutation: add an input to `materialInputs` without running
    // tool/material_vocabulary.dart, and the file is stale.
    expect(
      File(materialVocabularyPath).readAsStringSync(),
      materialVocabularySnapshot(),
      reason: 'run dart run tool/material_vocabulary.dart',
    );
  });

  test('every vocabulary line ends in a version this build reads', () {
    for (final line in materialVocabularySnapshot().split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final since = int.parse(line.split(' ').last);
      expect(since, inInclusiveRange(1, materialLanguageVersion), reason: line);
    }
  });

  group('GLSL\'s words are taken in every version', () {
    // The sixteen a fragment body bound without a word before, each
    // emitted as `float <name>` for glslang to refuse.
    const words = <String>[
      'shared',
      'buffer',
      'patch',
      'precise',
      'double',
      'noperspective',
      'sampler3D',
      'atomic_uint',
      'subroutine',
      'coherent',
      'readonly',
      'common',
      'input',
      'output',
      'filter',
      'half',
    ];
    for (var version = 1; version <= materialLanguageVersion; version++) {
      test('in version $version', () {
        // Mutation: take `materialGlslWords` out of the names a `let` and a
        // uniform cannot take, and `let filter` reads again.
        for (final word in words) {
          for (final source in <String>[
            _letting(version, word),
            _uniform(version, word),
          ]) {
            expect(
              () => parseMaterial(source),
              throwsA(
                isA<MaterialSyntaxException>().having(
                  (e) => e.message,
                  'message',
                  contains('a name the generated shader already uses'),
                ),
              ),
              reason: '$word in version $version',
            );
          }
        }
        // And a name next to them is still a name.
        expect(parseMaterial(_letting(version, 'filtered')).name, 'Named');
      });
    }
  });

  test('a word of a later version is refused with the version it needs', () {
    // Mutation: write a word into materialWordVersions with a version the
    // parser does not gate it by, and its source of the version before is
    // refused some other way, or read.
    final sources = <String, (int, String)>{
      'state': (2, 'state { blend alpha; }'),
      'vertex': (2, 'vertex { out world = world; }'),
      'ambient': (2, 'ambient { return albedo; }'),
      'composite': (2, 'composite { return direct; }'),
      'updates': (3, 'updates { 2: remove gone; }'),
      'lighttype': (3, 'lighttype tube = acme.tube;'),
    };
    for (final MapEntry(key: word, value: (since, declaration))
        in sources.entries) {
      expect(materialWordVersions[word], since, reason: word);
      expect(
        () => parseMaterial('''
f3dmat ${since - 1}
material Early {
  $declaration
  light { return albedo; }
  fragment { return vec4(lit, alpha); }
}
'''),
        throwsA(
          isA<MaterialSyntaxException>().having(
            (e) => e.message,
            'message',
            contains('version $since'),
          ),
        ),
        reason: word,
      );
    }
    for (final kind in <String>['fullscreen', 'compute']) {
      expect(materialWordVersions[kind], 2, reason: kind);
      expect(
        () => parseMaterial('$kind Early { }'),
        throwsA(
          isA<MaterialSyntaxException>().having(
            (e) => e.message,
            'message',
            contains('version 2'),
          ),
        ),
      );
    }
  });
}
