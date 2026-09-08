/// The README and the list agree about how many gaps there are, and about which.
///
/// **The same rule `tool/structure.dart` applies to the repository's own
/// numbers, applied to a document too small to deserve a rule of its own.** The
/// count in this package's README is the deliverable of the whole spike, and a
/// count nobody recounts is a count that goes stale the first time somebody adds
/// an entry to the list and edits the prose around it instead of the number.
///
/// On the VM alone, because it reads a file: `flutter test --platform chrome`
/// runs every other test in this package and has no `dart:io` to open the
/// document with.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webgpu_spike/webgpu_spike.dart';

/// The README as a reader reads it: paragraphs joined back into sentences and
/// the code fencing taken off.
///
/// **The same shape `tool/structure.dart` reads prose in, and for the same
/// reason.** A sentence wrapped across two lines is one sentence to a reader,
/// and a check that matched the raw file would fail on the line break and pass
/// only where a claim happened to fit — which would make this test about the
/// column the paragraph wraps at rather than about what the document says.
/// Backticks come off because the list writes `ShaderBundle.webgpuSection` as
/// code and names it as prose.
String _asRead(String markdown) => markdown
    .replaceAll(RegExp(r'[ \t]*\n[ \t]*(?=\S)'), ' ')
    .replaceAll('`', '');

/// Numbers as the README spells them, which is in words.
const List<String> _words = <String>[
  'Zero',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
];

void main() {
  late String readme;

  setUpAll(() {
    // `flutter test` runs with the package root as the working directory.
    final file = File('README.md');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'the README is where the answer is written down',
    );
    readme = _asRead(file.readAsStringSync());
  });

  test('the README says how many points there are, and is right', () {
    final claim = RegExp(
      r'\*\*(\w+) points of the contract\*\*',
    ).firstMatch(readme);
    expect(
      claim,
      isNotNull,
      reason:
          'the README no longer states a count, so nothing here can tell '
          'whether it is right',
    );
    expect(
      claim!.group(1),
      _words[webgpuContractGaps.length],
      reason:
          'the README says ${claim.group(1)} and the list has '
          '${webgpuContractGaps.length}',
    );
  });

  test('every point in the list is named in the README', () {
    for (final gap in webgpuContractGaps) {
      expect(
        readme,
        contains(gap.point),
        reason:
            '`${gap.point}` is in the list and not in the README, so a reader '
            'of the document is one gap short',
      );
    }
  });

  test('exactly one of them is a rewrite, and the README says so', () {
    final rewrites = webgpuContractGaps
        .where((ContractGap gap) => gap.cost == GapCost.byRewriting)
        .toList();
    expect(rewrites.length, 1);
    expect(
      rewrites.single.point,
      'BlendFactor.blendAlpha, BlendFactor.oneMinusBlendAlpha',
    );
    expect(
      readme,
      contains('three of the four are closed by adding to it'),
      reason:
          'the README states the split between additions and rewrites, and it '
          'has to agree with the list',
    );
  });

  test('every gap says what goes wrong without it', () {
    for (final gap in webgpuContractGaps) {
      expect(gap.point, isNotEmpty);
      // A sentence, not a label. A gap explained in four words is a gap the
      // next reader has to re-derive.
      expect(
        gap.why.length,
        greaterThan(80),
        reason: '${gap.point} is not explained',
      );
      expect(gap.toString(), contains(gap.point));
    }
  });
}
