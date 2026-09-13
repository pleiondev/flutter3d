/// How long each step of a run cost, keyed the same way [DigestTrace] keys a
/// run's state — by the step number, not by wall-clock time.
///
/// **`rp-06`: "trace of counters over a pass, keyed by run step."** A frame
/// rate is a number about *now*; this is a number about a *place in the
/// tape*, which is what makes it something rp-02's timeline can draw a strip
/// over and a click on the strip can jump to. The same reason `DigestTrace`
/// keys checkpoints by step instead of by when they happened: a step number
/// survives being replayed on a different machine, and a timestamp does not.
///
/// ## What this does not measure
///
/// Not a frame rate, not wall-clock elapsed play time, and not a profiler
/// hook of its own — it holds numbers a caller measured and handed over.
/// [record] is a convenience for the common case, timing one call with a
/// [Stopwatch]; a caller already holding a duration from somewhere else
/// calls [observe] directly.
final class StepTimeTrace {
  StepTimeTrace({this.every = 1})
    : assert(every > 0, 'a sample every no steps is no samples');

  /// How many steps pass between kept samples. One by default — unlike
  /// [DigestTrace], a step's own cost is cheap to keep every one of, and a
  /// profiler that only sampled one step in twenty-five would miss the one
  /// spike a person opened it to find.
  final int every;

  final List<int> _steps = <int>[];
  final List<double> _millis = <double>[];

  /// The step numbers sampled, in order.
  List<int> get steps => List<int>.unmodifiable(_steps);

  /// How long each of [steps] took, in milliseconds.
  List<double> get millis => List<double>.unmodifiable(_millis);

  /// Whether anything has been recorded yet.
  bool get isEmpty => _steps.isEmpty;

  /// Keeps [step]'s cost if it falls on [every], and drops it otherwise.
  void observe(int step, double ms) {
    if (step % every != 0) return;
    _steps.add(step);
    _millis.add(ms);
  }

  /// Times [body] with a [Stopwatch] and [observe]s the result — the shape
  /// most callers want: wrap the step, not the arithmetic.
  T record<T>(int step, T Function() body) {
    final watch = Stopwatch()..start();
    final result = body();
    watch.stop();
    observe(step, watch.elapsedMicroseconds / 1000.0);
    return result;
  }

  /// The step whose sample cost the most, or null if nothing has been
  /// recorded — what a spike on the strip is clicked through to.
  int? get worstStep {
    if (_millis.isEmpty) return null;
    var worst = 0;
    for (var i = 1; i < _millis.length; i++) {
      if (_millis[i] > _millis[worst]) worst = i;
    }
    return _steps[worst];
  }

  /// The cost at [worstStep], or null if nothing has been recorded.
  double? get worstMillis {
    if (_millis.isEmpty) return null;
    var worst = _millis[0];
    for (final ms in _millis) {
      if (ms > worst) worst = ms;
    }
    return worst;
  }

  /// The mean cost across every sample, or null if nothing has been recorded.
  double? get meanMillis {
    if (_millis.isEmpty) return null;
    var total = 0.0;
    for (final ms in _millis) {
      total += ms;
    }
    return total / _millis.length;
  }

  /// Writes this trace down: `every`, the sampled steps and their costs.
  Map<String, Object?> toJson() => <String, Object?>{
    'every': every,
    'steps': List<int>.of(_steps),
    'millis': List<double>.of(_millis),
  };

  /// Reads a trace back, or throws a [StepTimeTraceFormatException] that
  /// says why not.
  factory StepTimeTrace.fromJson(Map<String, Object?> json) {
    final every = json['every'];
    if (every is! num || every <= 0) {
      throw const StepTimeTraceFormatException(
        'a sample every no steps is no samples',
      );
    }
    final rawSteps = json['steps'];
    final rawMillis = json['millis'];
    if (rawSteps is! List || rawMillis is! List) {
      throw const StepTimeTraceFormatException(
        'the trace has no steps or no costs',
      );
    }
    if (rawSteps.length != rawMillis.length) {
      throw const StepTimeTraceFormatException(
        'the trace has a different number of steps and costs',
      );
    }
    final trace = StepTimeTrace(every: every.toInt());
    for (var i = 0; i < rawSteps.length; i++) {
      final step = rawSteps[i];
      final ms = rawMillis[i];
      if (step is! num || ms is! num) {
        throw const StepTimeTraceFormatException(
          'a sample is a step number and a cost in milliseconds',
        );
      }
      trace._steps.add(step.toInt());
      trace._millis.add(ms.toDouble());
    }
    return trace;
  }
}

/// Thrown when a [StepTimeTrace] cannot be read back at all.
final class StepTimeTraceFormatException implements Exception {
  const StepTimeTraceFormatException(this.message);

  final String message;

  @override
  String toString() => 'StepTimeTraceFormatException: $message';
}
