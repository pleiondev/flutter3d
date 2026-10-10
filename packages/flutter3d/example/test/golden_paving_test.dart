/// The `high-contrast` paving, texel for texel, on whichever platform this
/// runs.
///
///     flutter test test/golden_paving_test.dart
///     flutter test --platform chrome test/golden_paving_test.dart
///
/// **A golden's input has to be the same picture on every backend**, and the
/// browser backends are built by dart2js, where an `int` is a double and a
/// shift truncates to thirty-two bits first. The paving's first hash did not
/// survive that: the browser sets baked a different floor and disagreed with
/// Impeller on half their pixels, which looked like the look failing to
/// flatten. So the sum below is the one the VM computes, and the same file
/// run in a browser has to reach it too. Mutation: put back the hash that
/// multiplied by 2654435761 and shifted by twenty-eight — the VM sum moves,
/// and under `--platform chrome` the two platforms stop agreeing.
library;

import 'package:flutter3d_example/src/spike/golden_stages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the paving is the same texels under both integer models', () {
    var sum = 0;
    var weighted = 0;
    for (var y = 0; y < 512; y++) {
      for (var x = 0; x < 512; x++) {
        final grey = GoldenStages.pavingGrey(x, y);
        sum += grey;
        weighted = (weighted * 31 + grey) % 1000003;
      }
    }
    expect((sum: sum, weighted: weighted), (sum: _sum, weighted: _weighted));
  });
}

/// What the VM computes, written down so a browser has something to meet.
const int _sum = 17260184;
const int _weighted = 484861;
