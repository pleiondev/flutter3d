import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException;

/// The digest of each step's events, kept while a run is recorded.
///
/// **What turns "the replay diverged" into "at this event".** [DigestTrace]
/// checks the whole state every so many steps and brackets a divergence to
/// an interval; this checks what every step *said* — each event's name and
/// fields — so a replay that lands a step later, or lands somewhere else,
/// is caught at the step it happened. And a tool reads a run's events step
/// by step without playing it.
///
/// Sparse: only steps that published something are written, since most
/// steps of most runs publish nothing.
final class EventTrace {
  EventTrace() : _steps = <int>[], _counts = <int>[], _digests = <int>[];

  EventTrace._parts(this._steps, this._counts, this._digests);

  final List<int> _steps;
  final List<int> _counts;
  final List<int> _digests;

  /// The steps that published events, in order.
  List<int> get steps => List<int>.unmodifiable(_steps);

  /// How many events each of [steps] published.
  List<int> get counts => List<int>.unmodifiable(_counts);

  /// Each of [steps]' digest (`StepEventSummary.digest`).
  List<int> get digests => List<int>.unmodifiable(_digests);

  bool get isEmpty => _steps.isEmpty;

  /// Writes down step [step]'s events. A step that published nothing writes
  /// nothing; a step at or before one already written — a step lived again
  /// after a level swap or a branch — first forgets everything from it on.
  void observe(int step, {required int count, required int digest}) {
    if (_steps.isNotEmpty && step <= _steps.last) forgetAfter(step - 1);
    if (count == 0) return;
    _steps.add(step);
    _counts.add(count);
    _digests.add(digest);
  }

  /// Drops what was written after [step].
  void forgetAfter(int step) {
    final keep = _steps.indexWhere((s) => s > step);
    if (keep < 0) return;
    _steps.removeRange(keep, _steps.length);
    _counts.removeRange(keep, _counts.length);
    _digests.removeRange(keep, _digests.length);
  }

  /// The first step at which this trace and [expected] disagree, up to
  /// [through]: one published where the other did not, a different number
  /// of events, or a different digest. Null when they agree.
  EventDivergence? divergenceFrom(EventTrace expected, {int? through}) {
    var a = 0;
    var b = 0;
    while (a < _steps.length || b < expected._steps.length) {
      final mine = a < _steps.length ? _steps[a] : null;
      final theirs = b < expected._steps.length ? expected._steps[b] : null;
      final at = mine == null
          ? theirs!
          : theirs == null
          ? mine
          : (mine < theirs ? mine : theirs);
      if (through != null && at > through) return null;
      final found = mine == at ? a : null;
      final wanted = theirs == at ? b : null;
      final divergence = EventDivergence(
        step: at,
        expectedCount: wanted == null ? 0 : expected._counts[wanted],
        expectedDigest: wanted == null ? null : expected._digests[wanted],
        foundCount: found == null ? 0 : _counts[found],
        foundDigest: found == null ? null : _digests[found],
      );
      if (divergence.expectedDigest != divergence.foundDigest ||
          divergence.expectedCount != divergence.foundCount) {
        return divergence;
      }
      if (found != null) a++;
      if (wanted != null) b++;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'steps': List<int>.of(_steps),
    'counts': List<int>.of(_counts),
    'digests': <String>[
      for (final digest in _digests) digest.toRadixString(16).padLeft(8, '0'),
    ],
  };

  /// Reads a trace back, or throws a [EventTraceFormatException] saying why not.
  factory EventTrace.fromJson(Map<String, Object?> json) {
    final steps = json['steps'];
    final counts = json['counts'];
    final digests = json['digests'];
    if (steps is! List || counts is! List || digests is! List) {
      throw EventTraceFormatException(
        'the event trace has no steps, counts or digests',
      );
    }
    if (steps.length != counts.length || steps.length != digests.length) {
      throw EventTraceFormatException(
        'the event trace has ${steps.length} steps, ${counts.length} counts '
        'and ${digests.length} digests',
      );
    }
    final readSteps = <int>[];
    final readCounts = <int>[];
    final readDigests = <int>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final count = counts[i];
      final digest = digests[i];
      final parsed = digest is String ? int.tryParse(digest, radix: 16) : null;
      if (step is! int || count is! int || count <= 0 || parsed == null) {
        throw EventTraceFormatException(
          'entry $i of the event trace is not a step, a count and a '
          'hexadecimal digest',
        );
      }
      if (readSteps.isNotEmpty && step <= readSteps.last) {
        throw EventTraceFormatException(
          'the event trace has step $step after step ${readSteps.last}',
        );
      }
      readSteps.add(step);
      readCounts.add(count);
      readDigests.add(parsed);
    }
    return EventTrace._parts(readSteps, readCounts, readDigests);
  }
}

/// The first step at which two runs' events differed.
final class EventDivergence {
  const EventDivergence({
    required this.step,
    required this.expectedCount,
    required this.expectedDigest,
    required this.foundCount,
    required this.foundDigest,
  });

  final int step;
  final int expectedCount;

  /// Null when the expected run published nothing at [step].
  final int? expectedDigest;
  final int foundCount;

  /// Null when this run published nothing at [step].
  final int? foundDigest;

  static String _show(int count, int? digest) => digest == null
      ? 'no events'
      : '$count event${count == 1 ? '' : 's'} '
            '(${digest.toRadixString(16).padLeft(8, '0')})';

  @override
  String toString() =>
      'step $step: expected ${_show(expectedCount, expectedDigest)}, '
      'found ${_show(foundCount, foundDigest)}';
}

/// Thrown when an event trace cannot be read.
final class EventTraceFormatException extends Flutter3dFormatException {
  const EventTraceFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'EventTraceFormatException: $message';
}
