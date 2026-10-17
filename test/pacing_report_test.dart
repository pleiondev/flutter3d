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

  test('resident memory reads the 30 s sample, the last and the peak', () {
    // Samples as `pacing.sh` writes them: seconds since the app was first
    // seen, and kilobytes.
    final rss = rssSummary(<List<num>>[
      <num>[0, 100 * 1024],
      <num>[29, 180 * 1024],
      <num>[31, 200 * 1024],
      <num>[60, 260 * 1024],
      <num>[90, 210 * 1024],
    ])!;
    // Mutation: take the sample before 30 s, and the growth is measured from
    // the loading screen.
    expect(rss.at30, 200);
    expect(rss.end, 210);
    expect(rss.peak, 260);
    expect(rss.growth, closeTo(1.05, 1e-9));
    expect(rssSummary(const <List<num>>[]), isNull);
  });

  test('the P1 memory lines are held against the end of the run', () {
    final line = parseFailOn('rssGrowth=1.10,rssEnd=400');
    expect(line.keys, unorderedEquals(<String>['rssGrowth', 'rssEnd']));
    RssSummary rss(double at30, double end) =>
        RssSummary(at30: at30, end: end, peak: end, seconds: 150, samples: 150);
    expect(thresholdFailures(_pacing(), line, rss: rss(300, 330)), isEmpty);
    final grew = thresholdFailures(_pacing(), line, rss: rss(300, 340));
    expect(grew, hasLength(1));
    expect(grew.single, contains('rssGrowth'));
    final heavy = thresholdFailures(_pacing(), line, rss: rss(400, 401));
    expect(heavy.single, contains('rssEnd 401'));
  });

  test('a memory line with no memory measured fails, not passes', () {
    // Mutation: skip a memory key when nothing was sampled, and an iPhone run
    // (or one shorter than 30 s) holds the line by measuring nothing.
    final line = parseFailOn('rssGrowth=1.10');
    expect(thresholdFailures(_pacing(), line), hasLength(1));
    const short = RssSummary(
      at30: null,
      end: 200,
      peak: 200,
      seconds: 20,
      samples: 20,
    );
    expect(thresholdFailures(_pacing(), line, rss: short), hasLength(1));
  });

  test('a run sized in seconds loops whole passes of its tape', () {
    // 600 steps a pass is ten seconds: twenty seconds is two passes, and
    // twenty-one is three rather than two and a bit.
    expect(passesFor(20, steps: 600), 2);
    expect(passesFor(21, steps: 600), 3);
    expect(passesFor(0, steps: 600), 0);
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
