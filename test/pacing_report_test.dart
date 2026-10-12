/// `tool/pacing.sh --fail-on`: the thresholds a pacing run is held to, read
/// the way the nightly job hands them over.
///
///     dart test test/pacing_report_test.dart
library;

import 'package:test/test.dart';

import '../tool/pacing_report.dart';

/// What `replayPacing` reports, trimmed to the fields a threshold reads.
Map<String, Object?> _pacing({
  double p50 = 8,
  double p99 = 20,
  double max = 40,
  int frames = 1000,
  List<int> overLimit = const <int>[],
}) => <String, Object?>{
  'frames': frames,
  'limitMillis': 50.0,
  'p50': p50,
  'p99': p99,
  'max': max,
  'overLimit': overLimit,
};

void main() {
  test('a p99 under the line passes, one over it fails by name', () {
    final line = parseFailOn('p99=33.3');
    expect(thresholdFailures(_pacing(p99: 33.3), line), isEmpty);
    // Mutation: compare with `<` rather than `<=` in [thresholdFailures], and
    // the frame exactly on the line fails.
    final failures = thresholdFailures(_pacing(p99: 33.4), line);
    expect(failures, hasLength(1));
    expect(failures.single, contains('p99 33.40 ms'));
    expect(failures.single, contains('33.30 ms'));
  });

  test('every threshold of P1 is read, and each is checked', () {
    final line = parseFailOn('p50=16.7,p99=33.3,over50=0.1,max=100');
    expect(line.keys, unorderedEquals(<String>['p50', 'p99', 'over50', 'max']));
    expect(
      thresholdFailures(
        _pacing(p50: 17, p99: 40, max: 120, overLimit: <int>[3, 9]),
        line,
      ),
      hasLength(4),
    );
  });

  test('the share over the limit is a share of the frames', () {
    final line = parseFailOn('over50=0.1');
    // One frame in a thousand is 0.1 %, which is on the line.
    expect(thresholdFailures(_pacing(overLimit: <int>[5]), line), isEmpty);
    expect(
      thresholdFailures(_pacing(overLimit: <int>[5, 6]), line),
      hasLength(1),
    );
  });

  test('a threshold it does not know is refused, not ignored', () {
    // Mutation: skip unknown keys in [parseFailOn], and `p95=20` is a
    // nightly that checks nothing and reports green.
    expect(() => parseFailOn('p95=20'), throwsFormatException);
    expect(() => parseFailOn('p99'), throwsFormatException);
    expect(() => parseFailOn('p99=fast'), throwsFormatException);
    expect(() => parseFailOn(''), throwsFormatException);
  });
}
