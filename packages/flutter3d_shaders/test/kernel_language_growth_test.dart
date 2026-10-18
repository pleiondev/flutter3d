/// How the kernel language grows in a minor without refusing a source that
/// parsed before: every word arrives with a version, and a source of an
/// older version keeps every name it had.
///
///     dart test test/kernel_language_growth_test.dart
library;

import 'package:flutter3d_shaders/kernel.dart';
import 'package:flutter3d_shaders/src/kernel/kernel_parser.dart';
import 'package:flutter3d_shaders/src/kernel/kernel_words.dart';
import 'package:test/test.dart';

/// A source of [version] naming a local, a loop counter and a binding
/// [name].
List<String> _naming(int version, String name) => <String>[
  '''
kernel $version
compute Local {
  buffer out: u32[] read_write;
  kernel {
    var $name = 1u;
    $name += 1u;
    out[0] = $name;
  }
}
''',
  '''
kernel $version
compute Counter {
  buffer out: u32[] read_write;
  kernel {
    for $name in 0u .. 2u { out[$name] = $name; }
  }
}
''',
  '''
kernel $version
compute Binding {
  buffer $name: u32[] read_write;
  kernel { $name[0] = 1u; }
}
''',
];

Matcher _refused(String reason) => throwsA(
  isA<ComputeKernelException>().having(
    (e) => e.reason,
    'reason',
    contains(reason),
  ),
);

void main() {
  test('every word says the version it arrived in, one this build reads', () {
    // Mutation: write a word with the version after this build's, and a
    // source of the current version is refused a word it may not yet use.
    for (final MapEntry(key: word, value: since)
        in kernelWordVersions.entries) {
      expect(
        since,
        inInclusiveRange(kernelLanguageFirstVersion, kernelLanguageVersion),
        reason: word,
      );
    }
    expect(
      kernelWordVersions.entries
          .where((MapEntry<String, int> e) => e.value == 2)
          .map((MapEntry<String, int> e) => e.key)
          .toSet(),
      kernelWordsReservedEarly,
      reason: 'version 2 is the atomics',
    );
  });

  test("version 2's words stay taken in a version 1 source, as they were", () {
    // Version 1 read one list of words that already held them, so no
    // version 1 source names anything after them; freeing them would buy
    // nothing and make a name legal in 1 that 2 refuses.
    // Mutation: empty `kernelWordsReservedEarly`.
    for (final word in kernelWordsReservedEarly) {
      for (final source in _naming(1, word)) {
        expect(() => parseKernels(source), _refused('"$word"'), reason: word);
      }
    }
    // Called in a version 1 source, the word names the version it needs.
    expect(
      () => parseKernels('''
compute A {
  buffer out: u32[] read_write;
  kernel { atomicAdd(out, 0, 1u); }
}
'''),
      _refused('"atomicAdd" is kernel language 2'),
    );
    expect(
      () => parseKernels('''
compute A {
  buffer out: u32[] read_write;
  kernel { let x = atomicLoad(out, 0); }
}
'''),
      _refused('"atomicLoad" is kernel language 2'),
    );
  });

  test('a word version 3 is to take is a name in a version 1 or 2 '
      'source', () {
    // Workgroup memory, barriers, uniform blocks and storage-texture
    // formats come with version 3; until then each is a name like any
    // other. Mutation: reserve them now in every version, and a minor that
    // brings version 3 has refused these kernels already.
    for (final word in <String>[
      'barrier',
      'workgroupBarrier',
      'storageBarrier',
      'shared',
      'uniform',
      'local_id',
      'group_id',
      'r32float',
      'rgba32float',
    ]) {
      for (final version in <int>[1, 2]) {
        for (final source in _naming(version, word)) {
          expect(
            parseKernels(source),
            hasLength(1),
            reason: '$word in $version',
          );
        }
      }
    }
  });

  test('a word a later version adds stays free in an older source', () {
    // Version 3 written into the table: `barrier` is its word in a
    // `kernel 3` source and a name in every older one.
    // Mutation: drop the version check from `isKernelReservedName`.
    final words = <String, int>{...kernelWordVersions, 'barrier': 3};
    for (final version in <int>[1, 2]) {
      for (final source in _naming(version, 'barrier')) {
        expect(
          parseKernels(source, words: words, newest: 3),
          hasLength(1),
          reason: 'version $version',
        );
      }
    }
    for (final source in _naming(3, 'barrier')) {
      expect(
        () => parseKernels(source, words: words, newest: 3),
        _refused('"barrier"'),
      );
    }
    // Called in an older source, it names the version it needs.
    expect(
      () => parseKernels(
        'kernel 2\ncompute A { kernel { barrier(); } }',
        words: words,
        newest: 3,
      ),
      _refused('"barrier" is kernel language 3'),
    );
  });
}
